/// 株のジャンル。`id` は `firebase/firestore.rules` の `genres()` と同じ文字列。
enum PlantGenre {
  foliage('foliage', '観葉植物全般', 'パキラ・モンステラ・ポトス等'),
  caudex('caudex', '塊根', null),
  agave('agave', 'アガベ', null),
  succulentCactus('succulent_cactus', '多肉/サボテン', null),
  platycerium('platycerium', 'ビカクシダ', null),
  aroid('aroid', 'アロイド', null),
  rare('rare', '珍奇植物', null),
  seedling('seedling', '実生', null),
  other('other', 'その他', null);

  const PlantGenre(this.id, this.label, this.examples);

  final String id;
  final String label;
  final String? examples;

  /// 一覧や選択肢での表示。例:「観葉植物全般(パキラ・モンステラ・ポトス等)」
  String get labelWithExamples => examples == null ? label : '$label($examples)';

  static PlantGenre? fromId(String id) {
    for (final g in values) {
      if (g.id == id) return g;
    }
    return null;
  }
}

/// 株の初期ジャンル(観葉植物全般)。
const PlantGenre defaultPlantGenre = PlantGenre.foliage;
