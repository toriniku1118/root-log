// 公開用データ(publicPlants)の作り方の自動テスト:
// 「見えてはいけないものが見えない」= 購入価格・健康状態・置き場所などが、公開用データに出ないことを確認する。
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { buildPublicPlantDoc, type PublicScope } from './publicPlant.js';

/** 本人の株のドキュメント(非公開の項目をすべて含む) */
const privatePlant = {
  name: 'パキプス 1号',
  genre: 'caudex',
  variety: 'Operculicarya pachypus',
  source: '〇〇植物店',
  locationName: '南の窓辺',
  potSize: '4号',
  purchasePrice: 30_000,
  health: 'bad',
  tags: ['seedling'],
  hasProvenance: true,
  visibility: { public: true, scope: 'source' },
  createdAt: 'x',
  updatedAt: 'y',
};

const logs = [
  { type: 'water', occurredAt: 't1', stage: undefined },
  { type: 'health', occurredAt: 't2', stage: undefined },
  { type: 'stage', occurredAt: 't3', stage: 'rooted' },
];

const build = (scope: PublicScope, plant: Record<string, unknown> = privatePlant) =>
  buildPublicPlantDoc({ ownerUid: 'alice', plantId: 'p1', plant, scope, photos: [], logs, deletedPhotoCount: 1 });

const PRIVATE_KEYS = ['purchasePrice', 'health', 'locationName', 'potSize', 'visibility', 'createdAt', 'updatedAt', 'note'];

describe('公開用データに、非公開の項目が出ない', () => {
  for (const scope of ['photos', 'history', 'source'] as const) {
    it(`公開範囲が ${scope} でも、購入価格・健康状態・置き場所・鉢の号数は出ない`, () => {
      const doc = build(scope);
      for (const key of PRIVATE_KEYS) {
        assert.ok(!(key in doc), `${key} が公開用データに含まれている(scope=${scope})`);
      }
      // 値としても出ない(入れ子の中に紛れていない)
      const text = JSON.stringify(doc);
      assert.ok(!text.includes('30000'), '購入価格の値が含まれている');
      assert.ok(!text.includes('南の窓辺'), '置き場所の値が含まれている');
    });
  }

  it('株のドキュメントに知らない項目が増えても、公開用データには出ない(項目を名指しで選んでいる)', () => {
    const doc = build('source', { ...privatePlant, memo: '盗まれたら困る', newPrivateField: 123 });
    assert.ok(!('memo' in doc));
    assert.ok(!('newPrivateField' in doc));
  });
});

describe('公開範囲ごとの出し分け', () => {
  it('photos:写真だけ。記録と入手先は出ない', () => {
    const doc = build('photos');
    assert.ok(!('logs' in doc));
    assert.ok(!('source' in doc));
    assert.ok(!('deletedPhotoCount' in doc));
  });
  it('history:記録と削除された写真の数が出る。入手先は出ない', () => {
    const doc = build('history');
    assert.ok('logs' in doc);
    assert.equal(doc.deletedPhotoCount, 1);
    assert.ok(!('source' in doc));
  });
  it('source:入手先まで出る', () => {
    assert.equal(build('source').source, '〇〇植物店');
  });
});

describe('健康状態の変更の記録は、公開しない(要件 Q12)', () => {
  it('公開用の記録に、種類 health が含まれない', () => {
    const doc = build('history') as { logs: { type: string }[] };
    assert.deepEqual(
      doc.logs.map((l) => l.type),
      ['water', 'stage'],
    );
  });
});
