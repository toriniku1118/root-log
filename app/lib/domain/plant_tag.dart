/// 株のタグ。`id` は `firebase/firestore.rules` の tags と同じ文字列。
enum PlantTag {
  rescue('rescue', '復活チャレンジ'),
  seedling('seedling', '実生');

  const PlantTag(this.id, this.label);

  final String id;
  final String label;
}
