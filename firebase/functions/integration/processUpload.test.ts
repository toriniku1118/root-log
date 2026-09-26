// 写真の処理(processUpload)の通しテスト:元画像を置くと、処理済みの画像・写真の記録ができ、元画像が消える。
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import sharp from 'sharp';
import {
  bucket,
  createPlant,
  createUser,
  db,
  fileExists,
  makeJpeg,
  newUid,
  photosOf,
  staysTrue,
  upload,
  waitFor,
  waitForPhotos,
} from './helpers.js';

const recently = () => new Date(Date.now() - 60_000); // 1分前に撮影した写真

describe('processUpload:写真の処理と来歴の判定', () => {
  it('カメラで撮った直近の写真:来歴つき(ok)。位置情報・機種名は消え、元画像も消える', async () => {
    const uid = newUid();
    await createUser(uid);
    await createPlant(uid, 'p1');
    const before = Date.now();
    const uploadId = await upload(uid, 'p1', 'camera', await makeJpeg({ capturedAt: recently(), withPrivateInfo: true }));
    const [photo] = await waitForPhotos(uid, 'p1', 1);

    assert.equal(photo.get('provenance'), true);
    assert.equal(photo.get('provenanceReason'), 'ok');
    assert.equal(photo.get('source'), 'camera');
    assert.equal(photo.get('duplicateOf'), null);
    // 受信時刻は、サーバーが記録した時刻(この呼び出しの前後の間)
    const receivedMs = photo.get('receivedAt').toMillis();
    assert.ok(receivedMs >= before - 5_000 && receivedMs <= Date.now() + 1_000, '受信時刻がサーバーの時刻');

    // 処理済みの画像:JPEG で、EXIF(位置情報・機種名・撮影時刻)が残っていない
    const storagePath = photo.get('storagePath') as string;
    assert.equal(storagePath, `photos/${uid}/${photo.id}.jpg`);
    const [processed] = await bucket.file(storagePath).download();
    const meta = await sharp(processed).metadata();
    assert.equal(meta.format, 'jpeg');
    assert.equal(meta.exif, undefined, 'EXIF が残っていない');
    assert.equal(processed.includes(Buffer.from('Secret-Phone-9000')), false);

    // 元画像は必ず消える
    await waitFor('元画像の削除', async () => !(await fileExists(`uploads/${uid}/${uploadId}`)));

    // 株の来歴の印が付く(サーバーだけが付ける)
    await waitFor('hasProvenance', async () => (await db.doc(`users/${uid}/plants/p1`).get()).get('hasProvenance') === true);
  });

  it('端末の写真(gallery):来歴にならない(理由 gallery)。株に来歴の印は付かない', async () => {
    const uid = newUid();
    await createUser(uid);
    await createPlant(uid, 'p1');
    await upload(uid, 'p1', 'gallery', await makeJpeg({ capturedAt: recently(), color: '#c33' }));
    const [photo] = await waitForPhotos(uid, 'p1', 1);
    assert.equal(photo.get('provenance'), false);
    assert.equal(photo.get('provenanceReason'), 'gallery');
    assert.equal((await db.doc(`users/${uid}/plants/p1`).get()).get('hasProvenance'), false);
  });

  it('カメラでも、撮影時刻がなければ来歴にならない(no_capture_time)', async () => {
    const uid = newUid();
    await createUser(uid);
    await createPlant(uid, 'p1');
    await upload(uid, 'p1', 'camera', await makeJpeg({ color: '#39c' }));
    const [photo] = await waitForPhotos(uid, 'p1', 1);
    assert.equal(photo.get('provenance'), false);
    assert.equal(photo.get('provenanceReason'), 'no_capture_time');
  });

  it('撮影時刻が受信時刻から離れている(2時間前):来歴にならない(capture_time_mismatch)', async () => {
    const uid = newUid();
    await createUser(uid);
    await createPlant(uid, 'p1');
    await upload(uid, 'p1', 'camera', await makeJpeg({ capturedAt: new Date(Date.now() - 2 * 3_600_000), color: '#cc3' }));
    const [photo] = await waitForPhotos(uid, 'p1', 1);
    assert.equal(photo.get('provenance'), false);
    assert.equal(photo.get('provenanceReason'), 'capture_time_mismatch');
  });

  it('同じ画像をもう一度:2枚目は来歴にならない(duplicate)。1枚目の来歴は変わらない', async () => {
    const uid = newUid();
    await createUser(uid);
    await createPlant(uid, 'p1');
    const same = await makeJpeg({ capturedAt: recently(), color: '#909' });
    await upload(uid, 'p1', 'camera', same);
    await waitForPhotos(uid, 'p1', 1);
    await upload(uid, 'p1', 'camera', same);
    const docs = await waitForPhotos(uid, 'p1', 2);

    const oks = docs.filter((d) => d.get('provenanceReason') === 'ok');
    const dups = docs.filter((d) => d.get('provenanceReason') === 'duplicate');
    assert.equal(oks.length, 1);
    assert.equal(dups.length, 1);
    assert.equal(dups[0].get('provenance'), false);
    assert.equal(dups[0].get('duplicateOf'), `users/${uid}/plants/p1/photos/${oks[0].id}`);
    assert.equal((await db.doc(`users/${uid}/plants/p1`).get()).get('hasProvenance'), true);
  });

  it('大きい画像は、無料プランの大きさ(長辺1600px)に縮小される。小さい画像は拡大されない', async () => {
    const uid = newUid();
    await createUser(uid); // plan: free
    await createPlant(uid, 'p1');
    await upload(uid, 'p1', 'gallery', await makeJpeg({ width: 3200, height: 2400, color: '#111' }));
    await upload(uid, 'p1', 'gallery', await makeJpeg({ width: 320, height: 240, color: '#222' }));
    const docs = await waitForPhotos(uid, 'p1', 2);
    const sizes = docs.map((d) => [d.get('width'), d.get('height')]).sort((a, b) => a[0] - b[0]);
    assert.deepEqual(sizes, [
      [320, 240],
      [1600, 1200],
    ]);
  });

  it('プレミアムの利用者は、長辺3000pxまで', async () => {
    const uid = newUid();
    await createUser(uid, { plan: 'premium' });
    await createPlant(uid, 'p1');
    await upload(uid, 'p1', 'gallery', await makeJpeg({ width: 4000, height: 3000, color: '#333' }));
    const [photo] = await waitForPhotos(uid, 'p1', 1);
    assert.equal(photo.get('width'), 3000);
    assert.equal(photo.get('height'), 2250);
  });
});

describe('processUpload:受け付けないもの(記録を作らず、元画像も消す)', () => {
  const rejected = async (name: string, setup: (uid: string) => Promise<string>) => {
    const uid = newUid();
    await createUser(uid);
    await createPlant(uid, 'p1');
    const uploadId = await setup(uid);
    await waitFor(`${name}:元画像の削除`, async () => !(await fileExists(`uploads/${uid}/${uploadId}`)));
    await staysTrue(`${name}:写真の記録が作られない`, async () => (await photosOf(uid, 'p1')).length === 0, 1_500);
  };

  it('撮影元の指定がない/不正', async () => {
    await rejected('撮影元なし', async (uid) => upload(uid, 'p1', undefined, await makeJpeg({ color: '#a11' })));
    await rejected('撮影元が不正', async (uid) => upload(uid, 'p1', 'screenshot', await makeJpeg({ color: '#a12' })));
  });

  it('株の指定がない、または、その利用者の株ではない(他人の株に写真は作れない)', async () => {
    await rejected('株の指定なし', async (uid) => upload(uid, undefined, 'camera', await makeJpeg({ color: '#a13' })));
    await rejected('存在しない株', async (uid) => upload(uid, 'nothing', 'camera', await makeJpeg({ color: '#a14' })));

    const owner = newUid();
    await createUser(owner);
    await createPlant(owner, 'theirs');
    const other = newUid();
    const uploadId = await upload(other, 'theirs', 'camera', await makeJpeg({ color: '#a15' }));
    await waitFor('元画像の削除', async () => !(await fileExists(`uploads/${other}/${uploadId}`)));
    await staysTrue('他人の株に写真の記録が作られない', async () => (await photosOf(owner, 'theirs')).length === 0, 1_500);
  });

  it('画像ではないファイル', async () => {
    await rejected('画像でない', async (uid) => upload(uid, 'p1', 'camera', Buffer.from('これは画像ではありません')));
  });
});
