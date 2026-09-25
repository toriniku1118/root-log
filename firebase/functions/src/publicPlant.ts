// 植物の公開用データ(publicPlants)を作る部分。外に出す項目をここだけで決めるため、
// 「書き出す項目だけを名指しで選ぶ」形にしてある(非公開の項目が、書き足しで漏れないように)。
// 購入価格(purchasePrice)・健康状態(health)・置き場所・メモ・鉢の号数は、ここでは書き出さない。

export type PublicScope = 'photos' | 'history' | 'source';

export interface PublicPhoto {
  path: string;
  receivedAt: unknown;
  provenance: boolean;
}

export interface LogSource {
  type?: unknown;
  occurredAt?: unknown;
  stage?: unknown;
}

export interface BuildPublicPlantInput {
  ownerUid: string;
  plantId: string;
  /** 本人の株のドキュメント(非公開の項目を含む)。この中から、公開してよい項目だけを選ぶ。 */
  plant: Record<string, unknown>;
  scope: PublicScope;
  photos: PublicPhoto[];
  logs: LogSource[];
  deletedPhotoCount: number;
}

/** 健康状態の変更(type: health)は、ステップ1では公開しない(要件 Q12)。 */
const PRIVATE_LOG_TYPES = new Set(['health']);

export function buildPublicPlantDoc(input: BuildPublicPlantInput): Record<string, unknown> {
  const { plant, scope } = input;
  const doc: Record<string, unknown> = {
    ownerUid: input.ownerUid,
    plantId: input.plantId,
    name: plant.name,
    genre: plant.genre,
    variety: plant.variety ?? null,
    tags: plant.tags ?? [],
    hasProvenance: plant.hasProvenance === true,
    photos: input.photos,
  };
  if (scope === 'history' || scope === 'source') {
    doc.logs = input.logs
      .filter((l) => !PRIVATE_LOG_TYPES.has(String(l.type)))
      .map((l) => ({ type: l.type, occurredAt: l.occurredAt, stage: l.stage ?? null }));
    doc.deletedPhotoCount = input.deletedPhotoCount;
  }
  if (scope === 'source') doc.source = plant.source ?? null; // 入手先は本人が選んだ場合だけ
  return doc;
}
