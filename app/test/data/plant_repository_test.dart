import 'package:flutter_test/flutter_test.dart';
import 'package:rootlog/data/plant_repository.dart';
import 'package:rootlog/domain/plant.dart';
import 'package:rootlog/domain/plant_genre.dart';
import 'package:rootlog/domain/plant_input.dart';
import 'package:rootlog/domain/plant_tag.dart';

void main() {
  late DateTime clockNow;
  late int idCounter;
  late InMemoryPlantRepository repo;

  setUp(() {
    clockNow = DateTime(2026, 9, 25, 12);
    idCounter = 0;
    repo = InMemoryPlantRepository(clock: () => clockNow, idGenerator: () => 'id${++idCounter}');
  });

  test('追加すると、正規化された内容・必ず非公開・作成日時つきで保存される', () async {
    final plant = await repo.add(const PlantInput(
      name: ' モンステラ ',
      genre: PlantGenre.foliage,
      variety: ' デリシオーサ ',
      source: '  ',
      locationName: 'リビング',
      potSize: '5号',
      tags: {PlantTag.seedling},
    ));
    expect(plant.id, 'id1');
    expect(plant.name, 'モンステラ');
    expect(plant.variety, 'デリシオーサ');
    expect(plant.source, isNull);
    expect(plant.locationName, 'リビング');
    expect(plant.tags, {PlantTag.seedling});
    expect(plant.visibility.public, isFalse);
    expect(plant.visibility.scope, PlantScope.photos);
    expect(plant.createdAt, clockNow);
    expect(plant.updatedAt, clockNow);
  });

  test('条件を満たさない入力は追加できず、1件も増えない', () async {
    await expectLater(repo.add(const PlantInput(name: '')), throwsA(isA<PlantValidationException>()));
    expect(await repo.watchAll().first, isEmpty);
  });

  test('9ジャンルのどれでも追加できる', () async {
    for (final g in PlantGenre.values) {
      await repo.add(PlantInput(name: g.label, genre: g));
    }
    final all = await repo.watchAll().first;
    expect(all.map((p) => p.genre), PlantGenre.values);
  });

  test('一覧は購読した時点の内容がすぐ流れ、変更のたびに流れる', () async {
    await repo.add(const PlantInput(name: 'a'));
    final emitted = <List<String>>[];
    final sub = repo.watchAll().listen((l) => emitted.add(l.map((p) => p.name).toList()));
    await pumpEventQueue();
    await repo.add(const PlantInput(name: 'b'));
    await repo.delete('id1');
    await pumpEventQueue();
    await sub.cancel();
    expect(emitted, [
      ['a'],
      ['a', 'b'],
      ['b'],
    ]);
  });

  test('更新しても、id・作成日時・共有設定は変わらず、更新日時だけ進む', () async {
    final created = await repo.add(const PlantInput(name: 'a'));
    clockNow = DateTime(2026, 9, 26);
    final updated = await repo.update(created.id, const PlantInput(name: 'b', genre: PlantGenre.agave));
    expect(updated.id, created.id);
    expect(updated.name, 'b');
    expect(updated.genre, PlantGenre.agave);
    expect(updated.createdAt, created.createdAt);
    expect(updated.updatedAt, DateTime(2026, 9, 26));
    expect(updated.visibility.public, isFalse);
  });

  test('存在しない株の更新はエラー。条件を満たさない更新は元の内容が残る', () async {
    await expectLater(repo.update('none', const PlantInput(name: 'a')), throwsA(isA<PlantNotFoundException>()));
    final created = await repo.add(const PlantInput(name: 'a'));
    await expectLater(repo.update(created.id, const PlantInput(name: '')), throwsA(isA<PlantValidationException>()));
    expect((await repo.watchAll().first).single.name, 'a');
  });

  test('生成する id は、写真のアップロード先の条件(英数字・_-・1〜64文字)を満たす', () {
    final pattern = RegExp(r'^[A-Za-z0-9_-]{1,64}$');
    final ids = {for (var i = 0; i < 100; i++) generatePlantId()};
    expect(ids.length, 100);
    expect(ids.every(pattern.hasMatch), isTrue);
  });

  test('同じ id が出ても、既存の株を上書きしない', () async {
    final ids = ['same', 'same', 'other'];
    final r = InMemoryPlantRepository(clock: () => clockNow, idGenerator: () => ids.removeAt(0));
    final a = await r.add(const PlantInput(name: 'a'));
    final b = await r.add(const PlantInput(name: 'b'));
    expect(a.id, 'same');
    expect(b.id, 'other');
    expect((await r.watchAll().first).length, 2);
  });
}
