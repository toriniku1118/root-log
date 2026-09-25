import '../../domain/plant.dart';

/// ホームで、同じ置き場所の株をまとめたもの。[locationName] が null は「置き場所未設定」。
class PlantGroup {
  const PlantGroup(this.locationName, this.plants);

  final String? locationName;
  final List<Plant> plants;
}

/// 株を置き場所ごとにまとめる。置き場所は名前順で、未設定は最後。
/// 置き場所の中は、追加した順(古いものが上)。
List<PlantGroup> groupPlantsByLocation(List<Plant> plants) {
  final byLocation = <String?, List<Plant>>{};
  for (final p in plants) {
    byLocation.putIfAbsent(p.locationName, () => []).add(p);
  }
  final groups = [
    for (final entry in byLocation.entries) PlantGroup(entry.key, _byCreatedAt(entry.value)),
  ];
  groups.sort((a, b) {
    final an = a.locationName, bn = b.locationName;
    if (an == null && bn == null) return 0;
    if (an == null) return 1;
    if (bn == null) return -1;
    return an.compareTo(bn);
  });
  return groups;
}

/// 追加した日時の順。同じ日時のときは、元の並びを保つ(Dart の sort は安定ではないため添字で決める)。
List<Plant> _byCreatedAt(List<Plant> plants) {
  final indexed = [for (var i = 0; i < plants.length; i++) (i, plants[i])];
  indexed.sort((a, b) {
    final c = a.$2.createdAt.compareTo(b.$2.createdAt);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}
