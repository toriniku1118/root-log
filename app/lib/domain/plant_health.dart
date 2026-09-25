/// 株の健康状態(いまの状態)。`id` は `firebase/firestore.rules` の `healthStates()` と同じ文字列。
///
/// 段階(入手・発根など。節目の記録)とは別のもの。変えるたびに記録として残す(株の履歴でたどれる)。
enum PlantHealth {
  /// 登録直後で、まだ状態を決めていない。名前は仮(要件 Q13)。
  initial('initial', '初期'),
  good('good', '元気'),
  watch('watch', '要観察'),
  bad('bad', '不調'),
  recovering('recovering', '復活中');

  const PlantHealth(this.id, this.label);

  final String id;
  final String label;

  /// id から引く。知らない id は null。
  static PlantHealth? fromId(String id) {
    for (final h in values) {
      if (h.id == id) return h;
    }
    return null;
  }
}

/// 新しい株の健康状態。
const defaultPlantHealth = PlantHealth.initial;
