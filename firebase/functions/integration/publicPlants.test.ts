// 公開用データ(publicPlants・public/ の画像)の通しテスト:
// 公開の説明を確認するまで書き出さない・非公開の項目(購入価格・置き場所・健康状態など)は出ない・非公開にすると消える。
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import sharp from 'sharp';
import {
  Timestamp,
  bucket,
  createPlant,
  createUser,
  db,
  fileExists,
  makeJpeg,
  newUid,
  staysTrue,
  upload,
  waitFor,
  waitForPhotos,
} from './helpers.js';

const publicRef = (uid: string, plantId: string) => db.doc(`publicPlants/${uid}_${plantId}`);
const acked = () => ({ publishAckAt: Timestamp.now() });

/** 非公開の項目に、あとで探せる目印のある値を入れた株。 */
const privateFields = {
  variety: 'デリシオーサ',
  source: '近所のお店ABC',
  locationName: '窓辺の秘密の場所',
  potSize: '5号鉢',
  purchasePrice: 98765,
  health: 'bad',
  memo: '内緒のメモ',
};

const PRIVATE_MARKERS = ['98765', '窓辺の秘密の場所', '5号鉢', '内緒のメモ'];

async function waitForPublic(uid: string, plantId: string) {
  return waitFor('公開用データ', async () => {
    const s = await publicRef(uid, plantId).get();
    return s.exists ? s : null;
  });
}

describe('公開の説明の確認(REQ-049)', () => {
  it('確認する前は、公開設定が「公開」でも書き出さない。確認すると、まとめて書き出す', async () => {
    const uid = newUid();
    await createUser(uid); // publishAckAt なし
    await createPlant(uid, 'p1', privateFields);
    await createPlant(uid, 'p2', { ...privateFields, name: 'アガベ' });
    await staysTrue('確認前は書き出されない', async () => !(await publicRef(uid, 'p1').get()).exists, 2_000);

    await db.doc(`users/${uid}`).update(acked());
    const p1 = await waitForPublic(uid, 'p1');
    const p2 = await waitForPublic(uid, 'p2');
    assert.equal(p1.get('name'), 'モンステラ');
    assert.equal(p2.get('name'), 'アガベ');
  });

  it('確認前は、写真も公開用の場所にコピーしない', async () => {
    const uid = newUid();
    await createUser(uid);
    await createPlant(uid, 'p1');
    await upload(uid, 'p1', 'gallery', await makeJpeg({ color: '#f80' }));
    const [photo] = await waitForPhotos(uid, 'p1', 1);
    await staysTrue('公開用の写真がない', async () => !(await fileExists(`public/${uid}/${photo.id}.jpg`)), 2_000);
  });
});

describe('公開してよい項目だけが出る', () => {
  it('写真のみ(初期):名前・ジャンル・品種・タグ・来歴の印・写真だけ。価格・置き場所・号数・健康状態・メモ・入手先は出ない', async () => {
    const uid = newUid();
    await createUser(uid, acked());
    await createPlant(uid, 'p1', { ...privateFields, genres: ['foliage', 'caudex'], tags: ['seedling'] });
    const doc = await waitForPublic(uid, 'p1');
    const data = doc.data()!;

    assert.deepEqual(Object.keys(data).sort(), ['genres', 'hasProvenance', 'name', 'ownerUid', 'photos', 'plantId', 'tags', 'updatedAt', 'variety']);
    assert.equal(data.ownerUid, uid);
    assert.equal(data.name, 'モンステラ');
    assert.deepEqual(data.genres, ['foliage', 'caudex']);
    assert.equal(data.variety, 'デリシオーサ');
    const text = JSON.stringify(data);
    for (const marker of [...PRIVATE_MARKERS, '近所のお店ABC']) assert.equal(text.includes(marker), false, `公開用データに「${marker}」が含まれている`);
  });

  it('履歴まで:記録の種類・日時・段階と、削除された写真の数が出る。メモ・健康状態の記録は出ない', async () => {
    const uid = newUid();
    await createUser(uid, acked());
    await createPlant(uid, 'p1', { ...privateFields, visibility: { public: true, scope: 'history' } });
    const at = Timestamp.fromDate(new Date(Date.now() - 86_400_000));
    await db.collection(`users/${uid}/plants/p1/logs`).add({ type: 'water', occurredAt: at, recordedAt: Timestamp.now() });
    await db.collection(`users/${uid}/plants/p1/logs`).add({ type: 'stage', stage: 'new_leaf', occurredAt: at, recordedAt: Timestamp.now(), note: '内緒のメモ' });
    await db.collection(`users/${uid}/plants/p1/logs`).add({ type: 'health', health: 'bad', occurredAt: at, recordedAt: Timestamp.now(), note: '不調の理由' });

    const doc = await waitFor('履歴の書き出し', async () => {
      const s = await publicRef(uid, 'p1').get();
      return s.exists && (s.get('logs') as unknown[] | undefined)?.length === 2 ? s : null;
    });
    const logs = doc.get('logs') as Array<{ type: string; stage: string | null }>;
    assert.deepEqual(logs.map((l) => l.type).sort(), ['stage', 'water']);
    assert.equal(logs.find((l) => l.type === 'stage')?.stage, 'new_leaf');
    assert.equal(doc.get('deletedPhotoCount'), 0);
    assert.equal(doc.get('source'), undefined, '入手先は「入手先まで」のときだけ');
    const text = JSON.stringify(doc.data());
    for (const marker of [...PRIVATE_MARKERS, '不調の理由', 'bad']) assert.equal(text.includes(marker), false, `公開用データに「${marker}」が含まれている`);
  });

  it('入手先まで:入手先が出る(価格・置き場所などは、それでも出ない)', async () => {
    const uid = newUid();
    await createUser(uid, acked());
    await createPlant(uid, 'p1', { ...privateFields, visibility: { public: true, scope: 'source' } });
    const doc = await waitFor('入手先の書き出し', async () => {
      const s = await publicRef(uid, 'p1').get();
      return s.exists && s.get('source') != null ? s : null;
    });
    assert.equal(doc.get('source'), '近所のお店ABC');
    const text = JSON.stringify(doc.data());
    for (const marker of PRIVATE_MARKERS) assert.equal(text.includes(marker), false, `公開用データに「${marker}」が含まれている`);
  });

  it('写真:公開用の場所にコピーされ、位置情報などが入っていない。来歴の印が付く', async () => {
    const uid = newUid();
    await createUser(uid, acked());
    await createPlant(uid, 'p1');
    await upload(uid, 'p1', 'camera', await makeJpeg({ capturedAt: new Date(Date.now() - 30_000), withPrivateInfo: true, color: '#0af' }));
    const [photo] = await waitForPhotos(uid, 'p1', 1);
    const doc = await waitFor('公開用の写真', async () => {
      const s = await publicRef(uid, 'p1').get();
      return s.exists && (s.get('photos') as unknown[] | undefined)?.length === 1 ? s : null;
    });
    const pub = (doc.get('photos') as Array<{ path: string; provenance: boolean }>)[0];
    assert.equal(pub.path, `public/${uid}/${photo.id}.jpg`);
    assert.equal(pub.provenance, true);
    assert.equal(doc.get('hasProvenance'), true);
    const [bytes] = await bucket.file(pub.path).download();
    assert.equal((await sharp(bytes).metadata()).exif, undefined);
    assert.equal(bytes.includes(Buffer.from('Secret-Phone-9000')), false);
    // 元画像・撮影した場所のデータは、公開用に出ない
    assert.equal(JSON.stringify(doc.data()).includes('uploads/'), false);
  });
});

describe('非公開にする・戻す', () => {
  it('非公開にすると、公開用データと公開用の写真が消える。公開に戻すと、また書き出される', async () => {
    const uid = newUid();
    await createUser(uid, acked());
    await createPlant(uid, 'p1');
    await upload(uid, 'p1', 'gallery', await makeJpeg({ color: '#a0f' }));
    const [photo] = await waitForPhotos(uid, 'p1', 1);
    const publicPhoto = `public/${uid}/${photo.id}.jpg`;
    await waitFor('公開用の写真のコピー', () => fileExists(publicPhoto));

    await db.doc(`users/${uid}/plants/p1`).update({ visibility: { public: false, scope: 'photos' } });
    await waitFor('公開用データの削除', async () => !(await publicRef(uid, 'p1').get()).exists);
    await waitFor('公開用の写真の削除', async () => !(await fileExists(publicPhoto)));
    assert.equal(await fileExists(`photos/${uid}/${photo.id}.jpg`), true, '本人の写真は残る');

    await db.doc(`users/${uid}/plants/p1`).update({ visibility: { public: true, scope: 'photos' } });
    await waitForPublic(uid, 'p1');
    await waitFor('公開用の写真のコピー', () => fileExists(publicPhoto));
  });

  it('非公開のまま作った株は、書き出されない', async () => {
    const uid = newUid();
    await createUser(uid, acked());
    await createPlant(uid, 'p1', { visibility: { public: false, scope: 'photos' } });
    await staysTrue('書き出されない', async () => !(await publicRef(uid, 'p1').get()).exists, 2_000);
  });
});
