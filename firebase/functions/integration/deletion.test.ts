// 削除の通しテスト:写真の削除(deletePhoto)・株の削除(onPlantDeleted)・アカウント削除(deleteAccount)。
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  Timestamp,
  auth,
  callFunction,
  createPlant,
  createUser,
  db,
  fileExists,
  makeJpeg,
  newUid,
  photosOf,
  upload,
  waitFor,
  waitForPhotos,
} from './helpers.js';

const acked = () => ({ publishAckAt: Timestamp.now() });
const recently = () => new Date(Date.now() - 30_000);

/** 来歴つきの写真が1枚ある株(公開済み)を作る。 */
async function setupWithPhoto(uid: string, color: string) {
  await createUser(uid, acked());
  await createPlant(uid, 'p1');
  const img = await makeJpeg({ capturedAt: recently(), color });
  await upload(uid, 'p1', 'camera', img);
  const [photo] = await waitForPhotos(uid, 'p1', 1);
  const publicPhoto = `public/${uid}/${photo.id}.jpg`;
  await waitFor('公開用の写真のコピー', () => fileExists(publicPhoto));
  return { photo, publicPhoto, img };
}

describe('deletePhoto:写真の削除', () => {
  it('写真・公開用のコピーが消え、「削除された写真あり」が残り、来歴の印が数え直される', async () => {
    const uid = newUid();
    const { photo, publicPhoto } = await setupWithPhoto(uid, '#e11');
    assert.equal((await db.doc(`users/${uid}/plants/p1`).get()).get('hasProvenance'), true);

    const res = await callFunction('deletePhoto', uid, { plantId: 'p1', photoId: photo.id });
    assert.equal(res.status, 200, JSON.stringify(res.body));

    assert.equal((await photosOf(uid, 'p1')).length, 0);
    assert.equal(await fileExists(`photos/${uid}/${photo.id}.jpg`), false);
    assert.equal(await fileExists(publicPhoto), false);
    const logs = await db.collection(`users/${uid}/plants/p1/systemLogs`).get();
    assert.equal(logs.size, 1);
    assert.equal(logs.docs[0].get('type'), 'photo_deleted');
    assert.equal(logs.docs[0].get('wasProvenance'), true);
    assert.equal((await db.doc(`users/${uid}/plants/p1`).get()).get('hasProvenance'), false);
    // 公開用データの写真からも消える
    await waitFor('公開用データの写真が0件', async () => {
      const s = await db.doc(`publicPlants/${uid}_p1`).get();
      return s.exists && (s.get('photos') as unknown[]).length === 0 ? s : null;
    });
  });

  it('削除した写真と同じ画像を、あとでもう一度登録すると、また来歴つきになる(重複の記録も消える)', async () => {
    const uid = newUid();
    const { photo, img } = await setupWithPhoto(uid, '#e12');
    await callFunction('deletePhoto', uid, { plantId: 'p1', photoId: photo.id });
    await upload(uid, 'p1', 'camera', img);
    const [again] = await waitForPhotos(uid, 'p1', 1);
    assert.equal(again.get('provenanceReason'), 'ok');
  });

  it('他人の写真は削除できない(見つからない扱い)。写真は残る', async () => {
    const uid = newUid();
    const { photo } = await setupWithPhoto(uid, '#e13');
    const other = newUid();
    const res = await callFunction('deletePhoto', other, { plantId: 'p1', photoId: photo.id });
    assert.equal(res.status, 404, JSON.stringify(res.body));
    assert.equal((await photosOf(uid, 'p1')).length, 1);
    assert.equal(await fileExists(`photos/${uid}/${photo.id}.jpg`), true);
  });

  it('App Check のトークンがない呼び出し(アプリ以外)は、ログインしていても拒否される。写真は残る', async () => {
    const uid = newUid();
    const { photo } = await setupWithPhoto(uid, '#e15');
    const res = await callFunction('deletePhoto', uid, { plantId: 'p1', photoId: photo.id }, false);
    assert.equal(res.status, 401, JSON.stringify(res.body));
    assert.equal((await photosOf(uid, 'p1')).length, 1);
    assert.equal((await callFunction('deleteAccount', uid, {}, false)).status, 401);
    assert.equal((await db.doc(`users/${uid}`).get()).exists, true);
  });

  it('ログインしていない呼び出しは拒否される。存在しない写真・引数がないときもエラー', async () => {
    const uid = newUid();
    const { photo } = await setupWithPhoto(uid, '#e14');
    const anon = await callFunction('deletePhoto', null, { plantId: 'p1', photoId: photo.id });
    assert.equal(anon.status, 401, JSON.stringify(anon.body));
    assert.equal((await photosOf(uid, 'p1')).length, 1);

    assert.equal((await callFunction('deletePhoto', uid, { plantId: 'p1', photoId: 'nothing' })).status, 404);
    assert.equal((await callFunction('deletePhoto', uid, { plantId: 'p1' })).status, 400);
  });
});

describe('onPlantDeleted:株を削除したときの後片付け', () => {
  it('写真・記録・公開用データ・画像がすべて消える', async () => {
    const uid = newUid();
    const { photo, publicPhoto } = await setupWithPhoto(uid, '#d21');
    await db.collection(`users/${uid}/plants/p1/logs`).add({ type: 'water', occurredAt: Timestamp.now(), recordedAt: Timestamp.now() });

    await db.doc(`users/${uid}/plants/p1`).delete();

    await waitFor('後片付け', async () => {
      const gone =
        (await photosOf(uid, 'p1')).length === 0 &&
        (await db.collection(`users/${uid}/plants/p1/logs`).get()).empty &&
        !(await db.doc(`publicPlants/${uid}_p1`).get()).exists &&
        !(await fileExists(`photos/${uid}/${photo.id}.jpg`)) &&
        !(await fileExists(publicPhoto));
      return gone || null;
    });
  });

  it('ほかの株・ほかの利用者のデータは消えない', async () => {
    const uid = newUid();
    const { photo } = await setupWithPhoto(uid, '#d22');
    await createPlant(uid, 'p2');
    const other = newUid();
    const otherSetup = await setupWithPhoto(other, '#d23');

    await db.doc(`users/${uid}/plants/p2`).delete();
    await new Promise((r) => setTimeout(r, 2_000));
    assert.equal((await photosOf(uid, 'p1')).length, 1);
    assert.equal(await fileExists(`photos/${uid}/${photo.id}.jpg`), true);
    assert.equal(await fileExists(`photos/${other}/${otherSetup.photo.id}.jpg`), true);
  });
});

describe('deleteAccount:アカウント削除', () => {
  it('本人のデータ一式・画像・公開用データ・ログイン情報が消える。ほかの利用者は消えない', async () => {
    const uid = newUid();
    const { photo, publicPhoto } = await setupWithPhoto(uid, '#b31');
    await auth.createUser({ uid });
    await db.doc(`publicProfiles/${uid}`).set({ displayName: 'テスト' });
    await db.collection(`users/${uid}/plants/p1/logs`).add({ type: 'water', occurredAt: Timestamp.now(), recordedAt: Timestamp.now() });
    const other = newUid();
    const otherSetup = await setupWithPhoto(other, '#b32');

    const res = await callFunction('deleteAccount', uid);
    assert.equal(res.status, 200, JSON.stringify(res.body));

    assert.equal((await db.doc(`users/${uid}`).get()).exists, false);
    assert.equal((await db.collection(`users/${uid}/plants`).get()).size, 0);
    assert.equal((await photosOf(uid, 'p1')).length, 0);
    assert.equal((await db.doc(`publicPlants/${uid}_p1`).get()).exists, false);
    assert.equal((await db.doc(`publicProfiles/${uid}`).get()).exists, false);
    assert.equal(await fileExists(`photos/${uid}/${photo.id}.jpg`), false);
    assert.equal(await fileExists(publicPhoto), false);
    await assert.rejects(auth.getUser(uid), /no user record/i);

    // 重複検出用のデータも消える(同じ画像を、別の利用者が登録できるようになる)
    const dupCheck = newUid();
    await createUser(dupCheck);
    await createPlant(dupCheck, 'p1');
    await upload(dupCheck, 'p1', 'camera', await makeJpeg({ capturedAt: recently(), color: '#b31' }));
    const [again] = await waitForPhotos(dupCheck, 'p1', 1);
    assert.equal(again.get('provenanceReason'), 'ok');

    // ほかの利用者は消えない
    assert.equal((await photosOf(other, 'p1')).length, 1);
    assert.equal(await fileExists(`photos/${other}/${otherSetup.photo.id}.jpg`), true);
  });

  it('ログインしていない呼び出しは拒否される。何も消えない', async () => {
    const uid = newUid();
    await createUser(uid);
    const res = await callFunction('deleteAccount', null);
    assert.equal(res.status, 401, JSON.stringify(res.body));
    assert.equal((await db.doc(`users/${uid}`).get()).exists, true);
  });
});
