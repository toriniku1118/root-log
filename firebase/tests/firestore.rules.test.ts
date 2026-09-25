// Firestore セキュリティルールの自動テスト
// 実行: npm test(Firebase エミュレーター上で動く。本番には接続しない)
// 目的:「見えてはいけないものが見えない」「書いてはいけないものが書けない」ことを確認する。
import { readFileSync } from 'node:fs';
import { afterAll, beforeAll, beforeEach, describe, it } from 'vitest';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  doc,
  getDoc,
  setDoc,
  updateDoc,
  deleteDoc,
  serverTimestamp,
  Timestamp,
  collection,
  getDocs,
} from 'firebase/firestore';

let env: RulesTestEnvironment;

const ALICE = 'alice';
const BOB = 'bob';

const validUser = () => ({
  displayName: 'アリス',
  ageBand: '18+',
  genres: ['caudex', 'agave'],
  prefecture: '13',
  notify: { photo: true, event: true },
  createdAt: serverTimestamp(),
  updatedAt: serverTimestamp(),
});

const validPlant = (overrides: Record<string, unknown> = {}) => ({
  name: 'パキプス 1号',
  genre: 'caudex',
  variety: 'Operculicarya pachypus',
  source: '〇〇植物店',
  locationName: '南の窓辺',
  potSize: '4号',
  tags: ['seedling'],
  visibility: { public: false, scope: 'photos' },
  createdAt: serverTimestamp(),
  updatedAt: serverTimestamp(),
  ...overrides,
});

const validLog = (overrides: Record<string, unknown> = {}) => ({
  type: 'water',
  occurredAt: Timestamp.fromDate(new Date(Date.now() - 60_000)),
  recordedAt: serverTimestamp(),
  note: '',
  ...overrides,
});

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: 'rootlog-rules-test',
    firestore: { rules: readFileSync('firestore.rules', 'utf8') },
  });
});

afterAll(async () => {
  await env.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
  // 前提データ(ルールを無視して投入)
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'users', ALICE), { ...validUser(), createdAt: Timestamp.now(), updatedAt: Timestamp.now() });
    await setDoc(doc(db, 'users', ALICE, 'plants', 'p1'), {
      ...validPlant(),
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
    });
    await setDoc(doc(db, 'users', ALICE, 'plants', 'p1', 'photos', 'ph1'), {
      storagePath: 'photos/alice/ph1.jpg',
      receivedAt: Timestamp.now(),
      provenance: true,
    });
    await setDoc(doc(db, 'publicPlants', 'alice_p1'), { ownerUid: ALICE, name: 'パキプス 1号' });
  });
});

const as = (uid: string | null) =>
  uid ? env.authenticatedContext(uid).firestore() : env.unauthenticatedContext().firestore();

describe('users(非公開の本人データ)', () => {
  it('本人は自分のユーザー情報を読める', async () => {
    await assertSucceeds(getDoc(doc(as(ALICE), 'users', ALICE)));
  });
  it('他人は読めない', async () => {
    await assertFails(getDoc(doc(as(BOB), 'users', ALICE)));
  });
  it('ログインしていない人は読めない', async () => {
    await assertFails(getDoc(doc(as(null), 'users', ALICE)));
  });
  it('本人は正しい形でユーザー情報を作成できる', async () => {
    await assertSucceeds(setDoc(doc(as(BOB), 'users', BOB), { ...validUser(), displayName: 'ボブ' }));
  });
  it('課金状態(plan)を自分で設定して作成できない', async () => {
    await assertFails(setDoc(doc(as(BOB), 'users', BOB), { ...validUser(), plan: 'premium' }));
  });
  it('知らない項目(例:住所)を含めて作成できない', async () => {
    await assertFails(setDoc(doc(as(BOB), 'users', BOB), { ...validUser(), address: '東京都…' }));
  });
  it('年齢区分(ageBand)は後から変更できない', async () => {
    await assertFails(updateDoc(doc(as(ALICE), 'users', ALICE), { ageBand: '13-17', updatedAt: serverTimestamp() }));
  });
  it('課金状態(plan)を後から付け足せない', async () => {
    await assertFails(updateDoc(doc(as(ALICE), 'users', ALICE), { plan: 'premium', updatedAt: serverTimestamp() }));
  });
  it('表示名は変更できる', async () => {
    await assertSucceeds(updateDoc(doc(as(ALICE), 'users', ALICE), { displayName: 'ありす', updatedAt: serverTimestamp() }));
  });
  it('作成日時を過去にしてユーザー情報を作成できない', async () => {
    await assertFails(
      setDoc(doc(as(BOB), 'users', BOB), { ...validUser(), createdAt: Timestamp.fromDate(new Date('2020-01-01')) }),
    );
  });
  it('通知設定にオン/オフ以外の値を入れられない', async () => {
    await assertFails(setDoc(doc(as(BOB), 'users', BOB), { ...validUser(), notify: { photo: 'x'.repeat(1000) } }));
  });
  it('ユーザー情報をアプリから直接削除できない(削除はサーバー処理)', async () => {
    await assertFails(deleteDoc(doc(as(ALICE), 'users', ALICE)));
  });
});

describe('plants(植物)', () => {
  it('本人は自分の植物を読める', async () => {
    await assertSucceeds(getDoc(doc(as(ALICE), 'users', ALICE, 'plants', 'p1')));
  });
  it('他人は非公開の植物を読めない', async () => {
    await assertFails(getDoc(doc(as(BOB), 'users', ALICE, 'plants', 'p1')));
  });
  it('他人は植物の一覧を取得できない', async () => {
    await assertFails(getDocs(collection(as(BOB), 'users', ALICE, 'plants')));
  });
  it('本人は非公開の状態で植物を登録できる', async () => {
    await assertSucceeds(setDoc(doc(as(ALICE), 'users', ALICE, 'plants', 'p2'), validPlant()));
  });
  it('最初から公開状態で登録できない(初期設定は非公開)', async () => {
    await assertFails(
      setDoc(doc(as(ALICE), 'users', ALICE, 'plants', 'p2'), validPlant({ visibility: { public: true, scope: 'photos' } })),
    );
  });
  it('他人の植物リストに書き込めない', async () => {
    await assertFails(setDoc(doc(as(BOB), 'users', ALICE, 'plants', 'p3'), validPlant()));
  });
  it('観葉植物全般(foliage)のジャンルで登録できる', async () => {
    await assertSucceeds(
      setDoc(doc(as(ALICE), 'users', ALICE, 'plants', 'p2'), validPlant({ name: 'パキラ', genre: 'foliage', variety: null })),
    );
  });
  it('決められたジャンル以外は登録できない', async () => {
    await assertFails(setDoc(doc(as(ALICE), 'users', ALICE, 'plants', 'p2'), validPlant({ genre: 'unknown' })));
  });
  it('クライアントは来歴のタグ(provenance)を自分で付けられない', async () => {
    await assertFails(setDoc(doc(as(ALICE), 'users', ALICE, 'plants', 'p2'), validPlant({ tags: ['provenance'] })));
  });
  it('作成日時を過去の日付にして登録できない', async () => {
    await assertFails(
      setDoc(doc(as(ALICE), 'users', ALICE, 'plants', 'p2'), validPlant({ createdAt: Timestamp.fromDate(new Date('2020-01-01')) })),
    );
  });
  it('公開設定を後から公開に変更できる(本人のみ)', async () => {
    await assertSucceeds(
      updateDoc(doc(as(ALICE), 'users', ALICE, 'plants', 'p1'), {
        visibility: { public: true, scope: 'history' },
        updatedAt: serverTimestamp(),
      }),
    );
  });
  it('来歴の印(hasProvenance)を自分で付けられない', async () => {
    await assertFails(setDoc(doc(as(ALICE), 'users', ALICE, 'plants', 'p2'), validPlant({ hasProvenance: true })));
    await assertFails(
      updateDoc(doc(as(ALICE), 'users', ALICE, 'plants', 'p1'), { hasProvenance: true, updatedAt: serverTimestamp() }),
    );
  });
  it('サーバーが来歴の印を付けた後も、本人は名前などを更新できる', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(doc(ctx.firestore(), 'users', ALICE, 'plants', 'p1'), { hasProvenance: true });
    });
    await assertSucceeds(
      updateDoc(doc(as(ALICE), 'users', ALICE, 'plants', 'p1'), { name: 'パキプス 改名', updatedAt: serverTimestamp() }),
    );
  });
  it('作成日時は後から変更できない', async () => {
    await assertFails(
      updateDoc(doc(as(ALICE), 'users', ALICE, 'plants', 'p1'), {
        createdAt: Timestamp.fromDate(new Date('2020-01-01')),
        updatedAt: serverTimestamp(),
      }),
    );
  });
});

describe('logs(水やり・植え替えなどの記録)', () => {
  it('本人は水やりを記録できる', async () => {
    await assertSucceeds(setDoc(doc(as(ALICE), 'users', ALICE, 'plants', 'p1', 'logs', 'l1'), validLog()));
  });
  it('他人は記録を書けない・読めない', async () => {
    await assertFails(setDoc(doc(as(BOB), 'users', ALICE, 'plants', 'p1', 'logs', 'l1'), validLog()));
    await assertFails(getDocs(collection(as(BOB), 'users', ALICE, 'plants', 'p1', 'logs')));
  });
  it('未来の日時の記録は作れない', async () => {
    await assertFails(
      setDoc(
        doc(as(ALICE), 'users', ALICE, 'plants', 'p1', 'logs', 'l1'),
        validLog({ occurredAt: Timestamp.fromDate(new Date(Date.now() + 86_400_000)) }),
      ),
    );
  });
  it('記録した時刻(recordedAt)を偽れない', async () => {
    await assertFails(
      setDoc(
        doc(as(ALICE), 'users', ALICE, 'plants', 'p1', 'logs', 'l1'),
        validLog({ recordedAt: Timestamp.fromDate(new Date('2020-01-01')) }),
      ),
    );
  });
  it('記録の種類と記録時刻は後から変更できない', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users', ALICE, 'plants', 'p1', 'logs', 'l0'), {
        ...validLog(),
        recordedAt: Timestamp.now(),
      });
    });
    const ref = doc(as(ALICE), 'users', ALICE, 'plants', 'p1', 'logs', 'l0');
    await assertFails(updateDoc(ref, { type: 'repot' }));
    await assertFails(updateDoc(ref, { recordedAt: Timestamp.fromDate(new Date('2020-01-01')) }));
    await assertSucceeds(updateDoc(ref, { note: 'たっぷり' }));
    await assertSucceeds(deleteDoc(ref));
  });
  it('サーバー用の種類(system)の記録は作れない', async () => {
    await assertFails(setDoc(doc(as(ALICE), 'users', ALICE, 'plants', 'p1', 'logs', 'l1'), validLog({ type: 'system' })));
  });
});

describe('photos(来歴の元になる写真の記録)', () => {
  it('本人は自分の写真の記録を読める', async () => {
    await assertSucceeds(getDoc(doc(as(ALICE), 'users', ALICE, 'plants', 'p1', 'photos', 'ph1')));
  });
  it('本人でもアプリから写真の記録を作れない(撮影日時の偽装を防ぐ)', async () => {
    await assertFails(
      setDoc(doc(as(ALICE), 'users', ALICE, 'plants', 'p1', 'photos', 'ph2'), {
        storagePath: 'photos/alice/ph2.jpg',
        receivedAt: Timestamp.fromDate(new Date('2020-01-01')),
        provenance: true,
      }),
    );
  });
  it('本人でもアプリから写真の記録を書き換えられない', async () => {
    await assertFails(
      updateDoc(doc(as(ALICE), 'users', ALICE, 'plants', 'p1', 'photos', 'ph1'), {
        receivedAt: Timestamp.fromDate(new Date('2020-01-01')),
      }),
    );
  });
  it('他人は写真の記録を読めない', async () => {
    await assertFails(getDoc(doc(as(BOB), 'users', ALICE, 'plants', 'p1', 'photos', 'ph1')));
  });
});

describe('公開用データ・サーバー専用データ', () => {
  it('ログインしている人は公開用の植物を読める', async () => {
    await assertSucceeds(getDoc(doc(as(BOB), 'publicPlants', 'alice_p1')));
  });
  it('ログインしていない人は公開用の植物も読めない', async () => {
    await assertFails(getDoc(doc(as(null), 'publicPlants', 'alice_p1')));
  });
  it('本人でも公開用データを直接書けない(サーバーだけが書き出す)', async () => {
    await assertFails(setDoc(doc(as(ALICE), 'publicPlants', 'alice_p1'), { ownerUid: ALICE, name: '書き換え' }));
    await assertFails(setDoc(doc(as(ALICE), 'publicProfiles', ALICE), { displayName: 'x' }));
  });
  it('写真の重複検出用データは誰も読み書きできない', async () => {
    await assertFails(getDoc(doc(as(ALICE), 'photoHashes', 'abc')));
    await assertFails(setDoc(doc(as(ALICE), 'photoHashes', 'abc'), { photoPath: 'x' }));
  });
  it('ログインしていない人は公開プロフィールを読めない', async () => {
    await assertFails(getDoc(doc(as(null), 'publicProfiles', ALICE)));
  });
  it('他人は来歴の欠落の記録(systemLogs)を読めない', async () => {
    await assertFails(getDocs(collection(as(BOB), 'users', ALICE, 'plants', 'p1', 'systemLogs')));
  });
  it('定義していない場所には書けない', async () => {
    await assertFails(setDoc(doc(as(ALICE), 'anything', 'x'), { a: 1 }));
  });
});
