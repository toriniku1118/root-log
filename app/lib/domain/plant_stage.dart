/// 株の段階(節目の記録)。`id` は `firebase/firestore.rules` の記録の `stage` と同じ文字列。
///
/// 健康状態(いまの状態。`PlantHealth`)とは別のもの。失敗(枯死)も残せる。
enum PlantStage {
  acquired('acquired', '入手'),
  rooted('rooted', '発根'),
  newLeaf('new_leaf', '新芽'),
  repotted('repotted', '植え替え'),
  flowered('flowered', '開花'),
  divided('divided', '株分け'),
  recovered('recovered', '復活'),
  died('died', '枯死');

  const PlantStage(this.id, this.label);

  final String id;
  final String label;

  /// id から引く。知らない id は null。
  static PlantStage? fromId(String id) {
    for (final s in values) {
      if (s.id == id) return s;
    }
    return null;
  }
}
