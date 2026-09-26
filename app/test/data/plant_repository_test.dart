import 'package:flutter_test/flutter_test.dart';
import 'package:rootlog/data/plant_repository.dart';
import 'package:rootlog/domain/plant.dart';
import 'package:rootlog/domain/plant_genre.dart';
import 'package:rootlog/domain/plant_health.dart';
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

  test('追加すると、正規化された内容・初期公開(写真のみ)・作成日時つきで保存される', () async {
    final plant = await repo.add(const PlantInput(
      name: ' モンステラ ',
      genres: {PlantGenre.foliage, PlantGenre.aroid},
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
    expect(plant.visibility.public, isTrue);
    expect(plant.visibility.scope, PlantScope.photos);
    expect(plant.createdAt, clockNow);
    expect(plant.updatedAt, clockNow);
  });

  test('購入価格は保存され、更新で変えられる。未設定は null のまま', () async {
    final none = await repo.add(const PlantInput(name: 'a'));
    expect(none.purchasePrice, isNull);
    final priced = await repo.add(const PlantInput(name: 'b', purchasePrice: 12800));
    expect(priced.purchasePrice, 12800);
    final updated = await repo.update(priced.id, const PlantInput(name: 'b', purchasePrice: 15000));
    expect(updated.purchasePrice, 15000);
    final cleared = await repo.update(priced.id, const PlantInput(name: 'b'));
    expect(cleared.purchasePrice, isNull);
  });

  test('購入価格が範囲外の入力は追加できない', () async {
    await expectLater(
      repo.add(const PlantInput(name: 'x', purchasePrice: -1)),
      throwsA(isA<PlantValidationException>()),
    );
    await expectLater(
      repo.add(const PlantInput(name: 'x', purchasePrice: PlantLimits.purchasePrice + 1)),
      throwsA(isA<PlantValidationException>()),
    );
    expect(await repo.watchAll().first, isEmpty);
  });

  test('新しい株の健康状態は「初期」。更新しても健康状態は変わらない', () async {
    final plant = await repo.add(const PlantInput(name: 'a'));
    expect(plant.health, PlantHealth.initial);
    final updated = await repo.update(plant.id, const PlantInput(name: 'a2'));
    expect(updated.health, PlantHealth.initial);
  });

  test('共有設定を変えられる。変わるのは共有設定と更新日時だけ', () async {
    final created = await repo.add(const PlantInput(
      name: 'a',
      genres: {PlantGenre.aroid},
      variety: 'v',
      source: 's',
      locationName: 'l',
      potSize: '5号',
      purchasePrice: 1000,
      tags: {PlantTag.rescue},
    ));
    expect(created.visibility.public, isTrue); // 初期公開
    expect(created.visibility.scope, PlantScope.photos);

    clockNow = DateTime(2026, 9, 27);
    final updated = await repo.setVisibility(created.id, const PlantVisibility(public: true, scope: PlantScope.source));
    expect(updated.visibility.public, isTrue);
    expect(updated.visibility.scope, PlantScope.source);
    expect(updated.updatedAt, DateTime(2026, 9, 27));
    expect(updated.createdAt, created.createdAt);
    expect(updated.name, 'a');
    expect(updated.genres, {PlantGenre.aroid});
    expect(updated.variety, 'v');
    expect(updated.source, 's');
    expect(updated.locationName, 'l');
    expect(updated.potSize, '5号');
    expect(updated.purchasePrice, 1000);
    expect(updated.tags, {PlantTag.rescue});
    expect(updated.health, created.health);
    expect((await repo.watchAll().first).single.visibility.scope, PlantScope.source);

    final priv = await repo.setVisibility(created.id, const PlantVisibility(public: false, scope: PlantScope.photos));
    expect(priv.visibility.public, isFalse);
  });

  test('共有設定を変えても、編集(update)は共有設定を変えない', () async {
    final created = await repo.add(const PlantInput(name: 'a'));
    await repo.setVisibility(created.id, const PlantVisibility(public: false, scope: PlantScope.history));
    final edited = await repo.update(created.id, const PlantInput(name: 'b'));
    expect(edited.visibility.public, isFalse);
    expect(edited.visibility.scope, PlantScope.history);
  });

  test('存在しない株の共有設定は変えられない', () async {
    await expectLater(
      repo.setVisibility('nothing', const PlantVisibility(public: false, scope: PlantScope.photos)),
      throwsA(isA<PlantNotFoundException>()),
    );
  });

  test('条件を満たさない入力は追加できず、1件も増えない', () async {
    await expectLater(repo.add(const PlantInput(name: '')), throwsA(isA<PlantValidationException>()));
    expect(await repo.watchAll().first, isEmpty);
  });

  test('株に選べる8ジャンルのどれでも追加できる。実生はジャンルには選べない', () async {
    for (final g in PlantGenre.plantChoices) {
      await repo.add(PlantInput(name: g.label, genres: {g}));
    }
    final all = await repo.watchAll().first;
    expect(all.map((p) => p.genres.single), PlantGenre.plantChoices);
    expect(PlantGenre.plantChoices, isNot(contains(PlantGenre.seedling)));
    await expectLater(
      repo.add(const PlantInput(name: 'x', genres: {PlantGenre.seedling})),
      throwsA(isA<PlantValidationException>()),
    );
  });

  test('ジャンルは複数(1〜3個)を保存できる。0個・4個は追加できない', () async {
    final plant = await repo.add(const PlantInput(name: 'a', genres: {PlantGenre.aroid, PlantGenre.rare}));
    expect(plant.genres, {PlantGenre.aroid, PlantGenre.rare});
    await expectLater(repo.add(const PlantInput(name: 'b', genres: {})), throwsA(isA<PlantValidationException>()));
    await expectLater(
      repo.add(const PlantInput(
        name: 'c',
        genres: {PlantGenre.caudex, PlantGenre.agave, PlantGenre.aroid, PlantGenre.rare},
      )),
      throwsA(isA<PlantValidationException>()),
    );
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
    final updated = await repo.update(created.id, const PlantInput(name: 'b', genres: {PlantGenre.agave}));
    expect(updated.id, created.id);
    expect(updated.name, 'b');
    expect(updated.genres, {PlantGenre.agave});
    expect(updated.createdAt, created.createdAt);
    expect(updated.updatedAt, DateTime(2026, 9, 26));
    expect(updated.visibility.public, created.visibility.public);
    expect(updated.visibility.scope, created.visibility.scope);
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
