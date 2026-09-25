// Cloud Storage セキュリティルールの自動テスト
import { readFileSync } from 'node:fs';
import { afterAll, beforeAll, beforeEach, describe, it } from 'vitest';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import { ref, uploadBytes, getBytes, deleteObject } from 'firebase/storage';

let env: RulesTestEnvironment;
const ALICE = 'alice';
const BOB = 'bob';
const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10]); // テスト用の小さなデータ

const meta = (custom: Record<string, string> = { plantId: 'p1', source: 'camera' }, contentType = 'image/jpeg') => ({
  contentType,
  customMetadata: custom,
});

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: 'rootlog-rules-test',
    storage: { rules: readFileSync('storage.rules', 'utf8') },
  });
});
afterAll(async () => {
  await env.cleanup();
});
beforeEach(async () => {
  await env.clearStorage();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const s = ctx.storage();
    await uploadBytes(ref(s, `photos/${ALICE}/ph1.jpg`), jpeg, { contentType: 'image/jpeg' });
    await uploadBytes(ref(s, `public/${ALICE}/ph1.jpg`), jpeg, { contentType: 'image/jpeg' });
    await uploadBytes(ref(s, `uploads/${ALICE}/u0`), jpeg, meta());
  });
});

const st = (uid: string | null) => (uid ? env.authenticatedContext(uid).storage() : env.unauthenticatedContext().storage());

describe('uploads(アップロード受付)', () => {
  it('本人は自分の受付場所に写真をアップロードできる', async () => {
    await assertSucceeds(uploadBytes(ref(st(ALICE), `uploads/${ALICE}/u1`), jpeg, meta()));
  });
  it('他人の受付場所にはアップロードできない', async () => {
    await assertFails(uploadBytes(ref(st(BOB), `uploads/${ALICE}/u1`), jpeg, meta()));
  });
  it('空のファイル・15MB以上のファイルはアップロードできない', async () => {
    await assertFails(uploadBytes(ref(st(ALICE), `uploads/${ALICE}/u1`), new Uint8Array(0), meta()));
    await assertFails(uploadBytes(ref(st(ALICE), `uploads/${ALICE}/u2`), new Uint8Array(15 * 1024 * 1024), meta()));
  });
  it('画像以外はアップロードできない', async () => {
    await assertFails(uploadBytes(ref(st(ALICE), `uploads/${ALICE}/u1`), jpeg, meta(undefined, 'application/pdf')));
  });
  it('植物IDと撮影元の情報がないとアップロードできない', async () => {
    await assertFails(uploadBytes(ref(st(ALICE), `uploads/${ALICE}/u1`), jpeg, meta({ plantId: 'p1' })));
  });
  it('撮影元は camera / gallery 以外を指定できない', async () => {
    await assertFails(uploadBytes(ref(st(ALICE), `uploads/${ALICE}/u1`), jpeg, meta({ plantId: 'p1', source: 'server' })));
  });
  it('アップロード元の画像(位置情報を含みうる)は本人でも読めない', async () => {
    await assertFails(getBytes(ref(st(ALICE), `uploads/${ALICE}/u0`)));
  });
  it('アップロード元の画像を上書き・削除できない', async () => {
    await assertFails(uploadBytes(ref(st(ALICE), `uploads/${ALICE}/u0`), jpeg, meta()));
    await assertFails(deleteObject(ref(st(ALICE), `uploads/${ALICE}/u0`)));
  });
});

describe('photos / public(処理済みの写真)', () => {
  it('本人は処理済みの自分の写真を読める', async () => {
    await assertSucceeds(getBytes(ref(st(ALICE), `photos/${ALICE}/ph1.jpg`)));
  });
  it('他人は非公開の写真を読めない', async () => {
    await assertFails(getBytes(ref(st(BOB), `photos/${ALICE}/ph1.jpg`)));
  });
  it('本人でも処理済みの写真を直接書き換えられない', async () => {
    await assertFails(uploadBytes(ref(st(ALICE), `photos/${ALICE}/ph2.jpg`), jpeg, { contentType: 'image/jpeg' }));
  });
  it('ログインしている人は公開用の写真を読める', async () => {
    await assertSucceeds(getBytes(ref(st(BOB), `public/${ALICE}/ph1.jpg`)));
  });
  it('ログインしていない人は公開用の写真も読めない', async () => {
    await assertFails(getBytes(ref(st(null), `public/${ALICE}/ph1.jpg`)));
  });
  it('公開用の写真を直接書けない', async () => {
    await assertFails(uploadBytes(ref(st(ALICE), `public/${ALICE}/ph2.jpg`), jpeg, { contentType: 'image/jpeg' }));
  });
});
