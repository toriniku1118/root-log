import 'package:flutter_test/flutter_test.dart';
import 'package:rootlog/domain/plant.dart';
import 'package:rootlog/domain/plant_genre.dart';
import 'package:rootlog/features/home/plant_groups.dart';

Plant plant(String name, {String? location, DateTime? createdAt}) {
  final at = createdAt ?? DateTime(2026, 9, 25);
  return Plant(
    id: name,
    name: name,
    genre: PlantGenre.foliage,
    tags: const {},
    visibility: const PlantVisibility.privateDefault(),
    createdAt: at,
    updatedAt: at,
    locationName: location,
  );
}

void main() {
  test('株がなければグループもない', () {
    expect(groupPlantsByLocation([]), isEmpty);
  });

  test('置き場所ごとにまとまり、置き場所は名前順、未設定は最後', () {
    final groups = groupPlantsByLocation([
      plant('a', location: 'リビング'),
      plant('b'),
      plant('c', location: 'ベランダ'),
      plant('d', location: 'リビング'),
    ]);
    expect(groups.map((g) => g.locationName), ['ベランダ', 'リビング', null]);
    expect(groups[1].plants.map((p) => p.name), ['a', 'd']);
    expect(groups[2].plants.map((p) => p.name), ['b']);
  });

  test('置き場所の中は追加した順(古いものが上)。同じ日時なら元の並び', () {
    final groups = groupPlantsByLocation([
      plant('new', location: 'x', createdAt: DateTime(2026, 9, 25, 12)),
      plant('old', location: 'x', createdAt: DateTime(2026, 9, 20)),
      plant('same1', location: 'x', createdAt: DateTime(2026, 9, 22)),
      plant('same2', location: 'x', createdAt: DateTime(2026, 9, 22)),
    ]);
    expect(groups.single.plants.map((p) => p.name), ['old', 'same1', 'same2', 'new']);
  });

  test('大きい件数でも全株がどれかのグループに入る', () {
    final plants = [for (var i = 0; i < 500; i++) plant('p$i', location: 'loc${i % 7}')];
    final groups = groupPlantsByLocation(plants);
    expect(groups.length, 7);
    expect(groups.fold<int>(0, (n, g) => n + g.plants.length), 500);
  });
}
