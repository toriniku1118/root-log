/// ジャンル。「育ててみたい」「集めている」という傾向の整理に使う(正確な分類ではない)。
/// `id` は `firebase/firestore.rules` の `genres()`(好きなジャンル。9つ)と同じ文字列。
/// 株に選べるのは、実生を除く8つ([plantChoices]。ルールの `plantGenres()`)。実生は株の側ではタグで表す。
enum PlantGenre {
  foliage('foliage', '観葉植物全般', 'パキラ・ゴムの木・ガジュマル・サンスベリア等'),
  caudex('caudex', '塊根', null),
  agave('agave', 'アガベ', null),
  succulentCactus('succulent_cactus', '多肉/サボテン', null),
  platycerium('platycerium', 'ビカクシダ', null),
  aroid('aroid', 'アロイド', 'モンステラ・ポトス・アンスリウム・アロカシア等'),
  rare('rare', '珍奇植物', null),
  seedling('seedling', '実生', null),
  other('other', 'その他', null);

  const PlantGenre(this.id, this.label, this.examples);

  final String id;
  final String label;
  final String? examples;

  /// 一覧や選択肢での表示。例:「観葉植物全般(パキラ・ゴムの木・ガジュマル・サンスベリア等)」
  String get labelWithExamples => examples == null ? label : '$label($examples)';

  /// 株のジャンルとして選べるもの(実生を除く8つ)。ルールの `plantGenres()` と同じ。
  static final List<PlantGenre> plantChoices = List.unmodifiable(values.where((g) => g != seedling));

  static PlantGenre? fromId(String id) {
    for (final g in values) {
      if (g.id == id) return g;
    }
    return null;
  }
}

/// 株の初期ジャンル(観葉植物全般)。
const PlantGenre defaultPlantGenre = PlantGenre.foliage;
