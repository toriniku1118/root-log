/**
 * RootLog サーバー処理(Cloud Functions 第2世代)ステップ1 版
 *
 * 1. processUpload  … アップロードされた写真の位置情報などのメタデータを削除・縮小して保存し、
 *                     サーバーの受信時刻で「写真の記録」を作る(来歴の元。アプリからは作れない)。
 * 2. deletePhoto    … 本人による写真の削除。来歴の欠落として systemLogs に記録を残す。
 * 3. onPlantDeleted … 植物の削除時に、写真・記録・公開用データを後片付けする。
 * 4. onPlantWritten / onPlantLogWritten / onUserWritten
 *                   … 公開を選んだ植物だけを、選んだ範囲で公開用データ(publicPlants)に書き出す。
 *                      本人が公開の説明を確認する(users.publishAckAt)までは書き出さない。確認した時点でまとめて書き出す。
 * 5. deleteAccount  … アカウント削除(App Store の要件)。本人のデータをすべて削除する。
 *
 * セキュリティ要件:「植物アプリ_セキュリティ要件」4・5・10章。
 */
import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore, Timestamp, type QueryDocumentSnapshot, type DocumentSnapshot } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { setGlobalOptions } from 'firebase-functions/v2';
import { onObjectFinalized } from 'firebase-functions/v2/storage';
import { onDocumentDeleted, onDocumentWritten } from 'firebase-functions/v2/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions';
import sharp from 'sharp';
import { cleanImage } from './image.js';
import { extractCaptureTime, judgeProvenance } from './provenance.js';
import { buildPublicPlantDoc, hasPublishAck, type PublicScope } from './publicPlant.js';
import { createHash, randomUUID } from 'node:crypto';

initializeApp();
// 注意:Storage トリガーのリージョンは、デフォルトバケットの場所と合わせる(バケットは東京に作成すること)
setGlobalOptions({ region: 'asia-northeast1', maxInstances: 10 });

const db = getFirestore();
const bucket = () => getStorage().bucket();

/** 無料プランの保存サイズ(長辺)。有料プランは高画質 */
const FREE_LONG_EDGE = 1600;
const PREMIUM_LONG_EDGE = 3000;
/** 巨大な画像による負荷を防ぐ上限(画素数) */
const MAX_INPUT_PIXELS = 40_000_000;

/** 公開用データのID。植物IDは利用者が決められるため、必ず所有者のIDと組み合わせる */
const publicPlantId = (uid: string, plantId: string) => `${uid}_${plantId}`;

/** 植物に来歴の写真が1枚以上あるかを数え直して、来歴の印を更新する */
async function refreshProvenanceFlag(uid: string, plantId: string) {
  const plantRef = db.doc(`users/${uid}/plants/${plantId}`);
  const prov = await plantRef.collection('photos').where('provenance', '==', true).limit(1).get();
  await plantRef.update({ hasProvenance: !prov.empty }).catch(() => undefined);
}

/** 写真の重複検出用データのうち、この利用者が最初に登録したものだけを削除する */
async function deleteOwnedHashes(uid: string, photoDocs: Array<QueryDocumentSnapshot | DocumentSnapshot>) {
  await Promise.all(
    photoDocs
      .filter((p) => p.get('duplicateOf') == null && typeof p.get('sha256') === 'string')
      .map((p) =>
        db.runTransaction(async (tx) => {
          const ref = db.doc(`photoHashes/${p.get('sha256')}`);
          const h = await tx.get(ref);
          if (h.exists && String(h.get('photoPath') ?? '').startsWith(`users/${uid}/`)) tx.delete(ref);
        }),
      ),
  );
}

// ---------------------------------------------------------------------------
// 1. 写真の処理
// ---------------------------------------------------------------------------
export const processUpload = onObjectFinalized(
  { memory: '1GiB', cpu: 1, concurrency: 1, timeoutSeconds: 120 },
  async (event) => {
    const path = event.data.name ?? '';
    const match = /^uploads\/([^/]+)\/([^/]+)$/.exec(path);
    if (!match) return;
    const [, uid, uploadId] = match;
    const file = bucket().file(path);
    const receivedAt = Timestamp.now(); // 来歴の日時はサーバーの受信時刻(端末の時計は信用しない)

    try {
      const plantId = event.data.metadata?.plantId;
      const source = event.data.metadata?.source;
      if (!plantId || (source !== 'camera' && source !== 'gallery')) throw new Error('invalid metadata');

      // 本人の植物であることを確認
      const plantRef = db.doc(`users/${uid}/plants/${plantId}`);
      if (!(await plantRef.get()).exists) throw new Error('plant not found');

      const [original] = await file.download();
      const input = () => sharp(original, { limitInputPixels: MAX_INPUT_PIXELS });

      // 実際の画像形式を確認(アプリが申告する contentType は信用しない)
      const meta = await input().metadata();
      if (meta.format !== 'jpeg' && meta.format !== 'png') throw new Error(`unsupported format: ${meta.format}`);

      // 元画像の撮影時刻(EXIF)は来歴の判定にだけ使い、保存しない。編集時刻(Image.DateTime)は使わない
      const captured = extractCaptureTime(meta.exif);

      const isPremium = (await db.doc(`users/${uid}`).get()).get('plan') === 'premium';
      const longEdge = isPremium ? PREMIUM_LONG_EDGE : FREE_LONG_EDGE;

      // 位置情報を含むメタデータをすべて削除して縮小する
      const cleaned = await cleanImage(original, longEdge, MAX_INPUT_PIXELS);
      const sha256 = createHash('sha256').update(cleaned.data).digest('hex');

      // 先に画像を保存し、その後で写真の記録と重複検出用データを同じトランザクションで作る
      const photoId = randomUUID();
      const storagePath = `photos/${uid}/${photoId}.jpg`;
      const photoPath = `users/${uid}/plants/${plantId}/photos/${photoId}`;
      await bucket().file(storagePath).save(cleaned.data, {
        contentType: 'image/jpeg',
        resumable: false,
        metadata: { cacheControl: 'private, max-age=3600' },
      });

      try {
        await db.runTransaction(async (tx) => {
          const hashRef = db.doc(`photoHashes/${sha256}`);
          const h = await tx.get(hashRef);
          const duplicateOf = h.exists ? (h.get('photoPath') as string) : null;
          if (!duplicateOf) tx.set(hashRef, { photoPath, createdAt: receivedAt });
          // 来歴の判定(重複は、ほかの理由より優先)
          const { provenance, provenanceReason } = judgeProvenance({
            source,
            captured,
            receivedMs: receivedAt.toMillis(),
            isDuplicate: duplicateOf != null,
          });
          tx.set(db.doc(photoPath), {
            storagePath,
            width: cleaned.info.width,
            height: cleaned.info.height,
            source,
            receivedAt,
            provenance,
            provenanceReason,
            sha256,
            duplicateOf,
          });
        });
      } catch (e) {
        await bucket().file(storagePath).delete({ ignoreNotFound: true }); // 記録が作れなければ画像も残さない
        throw e;
      }

      await refreshProvenanceFlag(uid, plantId);
      await syncPublicPlant(uid, plantId);
    } catch (err) {
      logger.warn('processUpload rejected', { uid, uploadId, error: String(err) });
    } finally {
      // 元画像(位置情報を含みうる)は必ず削除する
      await file.delete({ ignoreNotFound: true });
    }
  },
);

// ---------------------------------------------------------------------------
// 2. 写真の削除(本人)
// ---------------------------------------------------------------------------
export const deletePhoto = onCall({ enforceAppCheck: true }, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'ログインが必要です');
  const { plantId, photoId } = req.data ?? {};
  if (typeof plantId !== 'string' || typeof photoId !== 'string') {
    throw new HttpsError('invalid-argument', 'plantId と photoId が必要です');
  }
  const photoRef = db.doc(`users/${uid}/plants/${plantId}/photos/${photoId}`);
  const snap = await photoRef.get();
  if (!snap.exists) throw new HttpsError('not-found', '写真が見つかりません');

  await bucket().file(snap.get('storagePath')).delete({ ignoreNotFound: true });
  await bucket().file(`public/${uid}/${photoId}.jpg`).delete({ ignoreNotFound: true });
  await deleteOwnedHashes(uid, [snap]);
  await photoRef.delete();
  // 来歴の欠落として記録を残す(取引で相手に見せるときに「削除された写真あり」と表示する)
  await db.collection(`users/${uid}/plants/${plantId}/systemLogs`).add({
    type: 'photo_deleted',
    photoReceivedAt: snap.get('receivedAt'),
    wasProvenance: snap.get('provenance') === true,
    at: FieldValue.serverTimestamp(),
  });
  await refreshProvenanceFlag(uid, plantId);
  await syncPublicPlant(uid, plantId);
  return { ok: true };
});

// ---------------------------------------------------------------------------
// 3. 植物の削除時の後片付け
// ---------------------------------------------------------------------------
export const onPlantDeleted = onDocumentDeleted('users/{uid}/plants/{plantId}', async (event) => {
  const { uid, plantId } = event.params;
  const plantPath = `users/${uid}/plants/${plantId}`;
  const photos = await db.collection(`${plantPath}/photos`).get();
  await deleteOwnedHashes(uid, photos.docs);
  await Promise.all(
    photos.docs.map(async (p) => {
      await bucket().file(p.get('storagePath')).delete({ ignoreNotFound: true });
      await bucket().file(`public/${uid}/${p.id}.jpg`).delete({ ignoreNotFound: true });
    }),
  );
  await db.recursiveDelete(db.doc(plantPath)); // サブコレクション(logs/photos/systemLogs)も削除
  await db.doc(`publicPlants/${publicPlantId(uid, plantId)}`).delete().catch(() => undefined);
});

// ---------------------------------------------------------------------------
// 4. 公開用データの書き出し(公開を選んだ項目だけ)
// ---------------------------------------------------------------------------
async function unpublish(uid: string, plantId: string, photoIds: string[]) {
  await db.doc(`publicPlants/${publicPlantId(uid, plantId)}`).delete().catch(() => undefined);
  await Promise.all(photoIds.map((id) => bucket().file(`public/${uid}/${id}.jpg`).delete({ ignoreNotFound: true })));
}

/**
 * 植物の公開用データを、現在の状態から作り直す。
 * トリガーは順番どおりに届くとは限らないため、イベントの中身ではなく毎回データベースを読み直し、
 * 書き込む直前にトランザクションで「まだ公開のままか」を確認する。
 */
async function syncPublicPlant(uid: string, plantId: string): Promise<void> {
  const plantRef = db.doc(`users/${uid}/plants/${plantId}`);
  const userRef = db.doc(`users/${uid}`);
  const publicRef = db.doc(`publicPlants/${publicPlantId(uid, plantId)}`);
  const plant = await plantRef.get();
  const user = await userRef.get();
  const photos = await plantRef.collection('photos').orderBy('receivedAt').get();
  const photoIds = photos.docs.map((d) => d.id);

  // 公開の初期値は「公開」だが、本人が公開の説明を確認する(publishAckAt)までは書き出さない
  if (!plant.exists || plant.get('visibility.public') !== true || !hasPublishAck(user.data())) {
    await unpublish(uid, plantId, photoIds);
    return;
  }

  const scope = plant.get('visibility.scope') as PublicScope;

  // 公開用の写真を書き出す(処理済み=メタデータ削除済みの画像のみ)
  const publicPhotos = [];
  for (const p of photos.docs) {
    const dest = `public/${uid}/${p.id}.jpg`;
    const [exists] = await bucket().file(dest).exists();
    if (!exists) await bucket().file(p.get('storagePath')).copy(bucket().file(dest));
    publicPhotos.push({ path: dest, receivedAt: p.get('receivedAt'), provenance: p.get('provenance') === true });
  }

  let logSources: { type?: unknown; occurredAt?: unknown; stage?: unknown }[] = [];
  let deletedPhotoCount = 0;
  if (scope === 'history' || scope === 'source') {
    const logs = await plantRef.collection('logs').orderBy('occurredAt').get();
    logSources = logs.docs.map((l) => ({ type: l.get('type'), occurredAt: l.get('occurredAt'), stage: l.get('stage') }));
    const sys = await plantRef.collection('systemLogs').where('type', '==', 'photo_deleted').get();
    deletedPhotoCount = sys.size;
  }
  // 公開する項目は buildPublicPlantDoc だけで決める(置き場所・メモ・鉢の号数・購入価格・健康状態は公開しない)
  const doc: Record<string, unknown> = {
    ...buildPublicPlantDoc({
      ownerUid: uid,
      plantId,
      plant: plant.data() ?? {},
      scope,
      photos: publicPhotos,
      logs: logSources,
      deletedPhotoCount,
    }),
    updatedAt: FieldValue.serverTimestamp(),
  };

  const stillPublic = await db.runTransaction(async (tx) => {
    const latest = await tx.get(plantRef);
    const latestUser = await tx.get(userRef);
    if (!latest.exists || latest.get('visibility.public') !== true || !hasPublishAck(latestUser.data())) return false;
    tx.set(publicRef, doc);
    return true;
  });
  if (!stillPublic) await unpublish(uid, plantId, photoIds);
}

export const onPlantWritten = onDocumentWritten('users/{uid}/plants/{plantId}', async (event) => {
  if (!event.data?.after.exists) return; // 削除は onPlantDeleted が担当
  await syncPublicPlant(event.params.uid, event.params.plantId);
});

// 本人が公開の説明を確認した(publishAckAt が新しく付いた)とき、公開中の株をまとめて書き出す
export const onUserWritten = onDocumentWritten('users/{uid}', async (event) => {
  const after = event.data?.after;
  if (!after?.exists) return;
  if (!hasPublishAck(after.data()) || hasPublishAck(event.data?.before.data())) return;
  const uid = event.params.uid;
  const plants = await db.collection(`users/${uid}/plants`).get();
  for (const p of plants.docs) await syncPublicPlant(uid, p.id);
});

export const onPlantLogWritten = onDocumentWritten('users/{uid}/plants/{plantId}/logs/{logId}', async (event) => {
  await syncPublicPlant(event.params.uid, event.params.plantId);
});

// ---------------------------------------------------------------------------
// 5. アカウント削除
// ---------------------------------------------------------------------------
export const deleteAccount = onCall({ enforceAppCheck: true }, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'ログインが必要です');

  // 公開用データ
  const pub = await db.collection('publicPlants').where('ownerUid', '==', uid).get();
  await Promise.all(pub.docs.map((d) => d.ref.delete()));
  await db.doc(`publicProfiles/${uid}`).delete().catch(() => undefined);

  // 写真の重複検出用データ(本人が最初に登録した分だけ)
  const plants = await db.collection(`users/${uid}/plants`).get();
  for (const pl of plants.docs) {
    await deleteOwnedHashes(uid, (await pl.ref.collection('photos').get()).docs);
  }

  // 本人のデータ一式
  await db.recursiveDelete(db.doc(`users/${uid}`));
  await Promise.all(['uploads', 'photos', 'public'].map((prefix) => bucket().deleteFiles({ prefix: `${prefix}/${uid}/` })));
  await getAuth().deleteUser(uid);
  logger.info('account deleted', { uid });
  return { ok: true };
});
