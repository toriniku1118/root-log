// サーバー処理の通しテスト用の道具。エミュレーター(Auth・Firestore・Storage・Functions)が動いている前提
// (`firebase/` で `npm run test:integration`)。
import { randomUUID } from 'node:crypto';
import sharp from 'sharp';
import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';

export const projectId = process.env.GCLOUD_PROJECT ?? 'demo-rootlog-int';
const app = initializeApp({ projectId, storageBucket: `${projectId}.appspot.com` });
export const db = getFirestore(app);
export const bucket = getStorage(app).bucket();
export const auth = getAuth(app);
export { Timestamp };

/** テストごとに別の利用者にする(ほかのテストのデータと混ざらないように)。 */
export const newUid = () => `u${randomUUID().replaceAll('-', '').slice(0, 12)}`;

export const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/** 条件が満たされる(null・undefined・false 以外を返す)まで、少しずつ待つ。 */
export async function waitFor<T>(what: string, fn: () => Promise<T | null | undefined | false>, timeoutMs = 20_000): Promise<T> {
  const start = Date.now();
  for (;;) {
    const v = await fn();
    if (v) return v;
    if (Date.now() - start > timeoutMs) throw new Error(`時間内に条件が満たされませんでした: ${what}`);
    await sleep(300);
  }
}

/** しばらく待って、その間ずっと条件が成り立たない(起きてはいけないことが起きない)ことを確かめる。 */
export async function staysTrue(what: string, fn: () => Promise<boolean>, forMs = 2_000): Promise<void> {
  const start = Date.now();
  do {
    if (!(await fn())) throw new Error(`途中で条件が崩れました: ${what}`);
    await sleep(300);
  } while (Date.now() - start < forMs);
}

/** EXIF の日時の書式(2026:09:26 10:00:00)。 */
export function exifTime(d: Date): string {
  const p = (n: number) => String(n).padStart(2, '0');
  return `${d.getUTCFullYear()}:${p(d.getUTCMonth() + 1)}:${p(d.getUTCDate())} ${p(d.getUTCHours())}:${p(d.getUTCMinutes())}:${p(d.getUTCSeconds())}`;
}

export interface JpegOptions {
  /** 撮影時刻(UTC。時差 +00:00 として書く)。なければ撮影時刻なし。 */
  capturedAt?: Date;
  /** 位置情報・機種名を入れる(処理後に消えていることを確かめる用)。 */
  withPrivateInfo?: boolean;
  /** 画像を区別するための色(同じ色・同じ大きさなら、同じ画像=重複になる)。 */
  color?: string;
  width?: number;
  height?: number;
}

export async function makeJpeg(o: JpegOptions = {}): Promise<Buffer> {
  const exif: Record<string, Record<string, string>> = {};
  if (o.withPrivateInfo) {
    exif.IFD0 = { Make: 'TestCam', Model: 'Secret-Phone-9000' };
    exif.IFD3 = { GPSLatitudeRef: 'N', GPSLatitude: '35/1 40/1 0/1', GPSLongitudeRef: 'E', GPSLongitude: '139/1 45/1 0/1' };
  }
  if (o.capturedAt) exif.IFD2 = { DateTimeOriginal: exifTime(o.capturedAt), OffsetTimeOriginal: '+00:00' };
  let img = sharp({
    create: { width: o.width ?? 64, height: o.height ?? 48, channels: 3, background: o.color ?? '#3a7' },
  });
  if (Object.keys(exif).length > 0) img = img.withExif(exif);
  return img.jpeg().toBuffer();
}

/** 元画像を `uploads/` に置く(ここからサーバーの `processUpload` が動く)。 */
export async function upload(uid: string, plantId: string | undefined, source: string | undefined, data: Buffer): Promise<string> {
  const uploadId = randomUUID();
  const metadata: Record<string, string> = {};
  if (plantId) metadata.plantId = plantId;
  if (source) metadata.source = source;
  await bucket.file(`uploads/${uid}/${uploadId}`).save(data, { contentType: 'image/jpeg', resumable: false, metadata: { metadata } });
  return uploadId;
}

export const photosOf = async (uid: string, plantId: string) => (await db.collection(`users/${uid}/plants/${plantId}/photos`).get()).docs;

/** 株の写真の記録が n 件になるまで待つ。 */
export async function waitForPhotos(uid: string, plantId: string, n: number) {
  return waitFor(`写真の記録が${n}件`, async () => {
    const docs = await photosOf(uid, plantId);
    return docs.length >= n ? docs : null;
  });
}

export const fileExists = async (path: string) => (await bucket.file(path).exists())[0];

/** 利用者と株を作る(テストが直接作る。アプリのルールを通さない)。 */
export async function createPlant(uid: string, plantId: string, extra: Record<string, unknown> = {}) {
  await db.doc(`users/${uid}/plants/${plantId}`).set({
    name: 'モンステラ',
    genres: ['foliage'],
    tags: [],
    visibility: { public: true, scope: 'photos' },
    hasProvenance: false,
    createdAt: Timestamp.now(),
    updatedAt: Timestamp.now(),
    ...extra,
  });
}

export async function createUser(uid: string, extra: Record<string, unknown> = {}) {
  await db.doc(`users/${uid}`).set({ displayName: 'テスト', ageBand: 'adult', plan: 'free', createdAt: Timestamp.now(), ...extra });
}

/** エミュレーターは、署名を確かめない(中身だけ読む)ので、署名なしの App Check トークンで通る。 */
function fakeAppCheckToken(): string {
  const b64 = (o: object) => Buffer.from(JSON.stringify(o)).toString('base64url');
  return `${b64({ alg: 'none', typ: 'JWT' })}.${b64({ sub: 'test-app', app_id: 'test-app', aud: [`projects/${projectId}`] })}.`;
}

/**
 * 呼び出し型の関数を、その利用者として呼ぶ(Auth エミュレーターのトークン)。
 * `appCheck: false` にすると、App Check のトークンを付けない(アプリ以外からの呼び出しの想定)。
 */
export async function callFunction(name: string, uid: string | null, data: Record<string, unknown> = {}, appCheck = true) {
  const headers: Record<string, string> = { 'Content-Type': 'application/json' };
  if (appCheck) headers['X-Firebase-AppCheck'] = fakeAppCheckToken();
  if (uid) {
    const customToken = await auth.createCustomToken(uid);
    const res = await fetch(
      `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=fake`,
      { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ token: customToken, returnSecureToken: true }) },
    );
    const { idToken } = (await res.json()) as { idToken: string };
    headers.Authorization = `Bearer ${idToken}`;
  }
  const res = await fetch(`http://127.0.0.1:5001/${projectId}/asia-northeast1/${name}`, {
    method: 'POST',
    headers,
    body: JSON.stringify({ data }),
  });
  const body = (await res.json()) as { result?: unknown; error?: { status?: string; message?: string } };
  return { status: res.status, body };
}
