import 'package:flutter_test/flutter_test.dart';
import 'package:rootlog/data/plant_repository.dart';
import 'package:rootlog/domain/plant_health.dart';
import 'package:rootlog/domain/plant_input.dart';
import 'package:rootlog/domain/plant_log.dart';
import 'package:rootlog/domain/plant_stage.dart';

void main() {
  late DateTime clockNow;
  late int logCounter;
  late InMemoryPlantRepository repo;
  late String plantId;

  setUp(() async {
    clockNow = DateTime(2026, 9, 26, 12);
    logCounter = 0;
    repo = InMemoryPlantRepository(
      clock: () => clockNow,
      idGenerator: () => 'plant1',
      logIdGenerator: () => 'log${++logCounter}',
    );
    plantId = (await repo.add(const PlantInput(name: 'モンステラ'))).id;
  });

  PlantLogInput water({DateTime? at, String? note}) =>
      PlantLogInput(type: PlantLogType.water, occurredAt: at ?? clockNow, note: note);

  group('記録の追加・一覧', () {
    test('追加すると、正規化された内容と、記録した時刻(保存先の時刻)つきで保存される', () async {
      final at = DateTime(2026, 9, 20, 10);
      final log = await repo.addLog(plantId, PlantLogInput(type: PlantLogType.stage, occurredAt: at, note: ' 新芽が出た ', stage: PlantStage.newLeaf));
      expect(log.id, 'log1');
      expect(log.plantId, plantId);
      expect(log.type, PlantLogType.stage);
      expect(log.stage, PlantStage.newLeaf);
      expect(log.note, '新芽が出た');
      expect(log.occurredAt, at);
      expect(log.recordedAt, clockNow); // 入力した日時ではなく、記録した時刻
      expect(await repo.watchLogs(plantId).first, [log]);
    });

    test('一覧は新しい順(出来事の日時 → 記録した時刻 → あとに追加したものが上)', () async {
      final a = await repo.addLog(plantId, water(at: DateTime(2026, 9, 10)));
      final b = await repo.addLog(plantId, water(at: DateTime(2026, 9, 20)));
      clockNow = DateTime(2026, 9, 26, 13);
      final c = await repo.addLog(plantId, water(at: DateTime(2026, 9, 20))); // 同じ日時なら、あとに記録したものが上
      final d = await repo.addLog(plantId, water(at: DateTime(2026, 9, 20))); // 記録した時刻も同じなら、あとに追加したものが上
      expect((await repo.watchLogs(plantId).first).map((l) => l.id), [d.id, c.id, b.id, a.id]);
    });

    test('株ごとに分かれる。株がなければ空', () async {
      expect(await repo.watchLogs('nothing').first, isEmpty);
      await repo.addLog(plantId, water());
      expect(await repo.watchLogs('nothing').first, isEmpty);
    });

    test('存在しない株には追加できない', () async {
      await expectLater(repo.addLog('nothing', water()), throwsA(isA<PlantNotFoundException>()));
    });

    test('条件を満たさない記録は追加できず、1件も増えない', () async {
      await expectLater(
        repo.addLog(plantId, water(at: clockNow.add(const Duration(days: 1)))),
        throwsA(isA<PlantLogValidationException>()),
      );
      await expectLater(
        repo.addLog(plantId, PlantLogInput(type: PlantLogType.note, occurredAt: DateTime(2026, 9, 1))), // メモが空
        throwsA(isA<PlantLogValidationException>()),
      );
      expect(await repo.watchLogs(plantId).first, isEmpty);
    });

    test('一覧は購読した時点の内容がすぐ流れ、変更のたびに流れる', () async {
      final seen = <int>[];
      final sub = repo.watchLogs(plantId).listen((l) => seen.add(l.length));
      await Future<void>.delayed(Duration.zero);
      await repo.addLog(plantId, water());
      await repo.addLog(plantId, water());
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(seen, [0, 1, 2]);
    });
  });

  group('記録の更新・削除', () {
    test('メモと日時を直せる。種類・段階・記録した時刻は変わらない', () async {
      final created = await repo.addLog(plantId, PlantLogInput(type: PlantLogType.stage, occurredAt: DateTime(2026, 9, 1), stage: PlantStage.rooted));
      clockNow = DateTime(2026, 9, 27);
      final updated = await repo.updateLog(plantId, created.id, occurredAt: DateTime(2026, 9, 2), note: ' 根が出た ');
      expect(updated.id, created.id);
      expect(updated.type, PlantLogType.stage);
      expect(updated.stage, PlantStage.rooted);
      expect(updated.occurredAt, DateTime(2026, 9, 2));
      expect(updated.note, '根が出た');
      expect(updated.recordedAt, created.recordedAt);
      expect(await repo.watchLogs(plantId).first, [updated]);
      // メモは消せる
      expect((await repo.updateLog(plantId, created.id, occurredAt: DateTime(2026, 9, 2))).note, isNull);
    });

    test('条件を満たさない更新はできず、元の内容が残る。種類がメモの記録は、メモを空にできない', () async {
      final water1 = await repo.addLog(plantId, water(note: 'たっぷり'));
      await expectLater(
        repo.updateLog(plantId, water1.id, occurredAt: clockNow.add(const Duration(days: 1))),
        throwsA(isA<PlantLogValidationException>()),
      );
      final memo = await repo.addLog(plantId, PlantLogInput(type: PlantLogType.note, occurredAt: clockNow, note: 'メモ'));
      await expectLater(
        repo.updateLog(plantId, memo.id, occurredAt: clockNow),
        throwsA(isA<PlantLogValidationException>()),
      );
      final all = await repo.watchLogs(plantId).first;
      expect(all.firstWhere((l) => l.id == water1.id).note, 'たっぷり');
      expect(all.firstWhere((l) => l.id == memo.id).note, 'メモ');
    });

    test('存在しない記録の更新はエラー', () async {
      await expectLater(
        repo.updateLog(plantId, 'nothing', occurredAt: clockNow),
        throwsA(isA<PlantLogNotFoundException>()),
      );
    });

    test('削除できる。存在しなくてもエラーにしない', () async {
      final a = await repo.addLog(plantId, water());
      final b = await repo.addLog(plantId, water());
      await repo.deleteLog(plantId, a.id);
      expect((await repo.watchLogs(plantId).first).map((l) => l.id), [b.id]);
      await repo.deleteLog(plantId, 'nothing');
      await repo.deleteLog('nothing', 'nothing');
      expect(await repo.watchLogs(plantId).first, hasLength(1));
    });

    test('株を削除すると、その株の記録も消える', () async {
      await repo.addLog(plantId, water());
      await repo.delete(plantId);
      expect(await repo.watchLogs(plantId).first, isEmpty);
    });
  });

  group('健康状態の変更', () {
    test('株の健康状態が変わり、変更が記録として残る(株の更新日時も進む。それ以外は変わらない)', () async {
      final before = (await repo.watchAll().first).single;
      expect(before.health, PlantHealth.initial);
      clockNow = DateTime(2026, 9, 27, 9);
      final plant = await repo.changeHealth(plantId, PlantHealth.bad, note: '葉がしおれてきた');

      expect(plant.health, PlantHealth.bad);
      expect(plant.updatedAt, clockNow);
      expect(plant.createdAt, before.createdAt);
      expect(plant.name, before.name);
      expect(plant.visibility.public, before.visibility.public);
      expect((await repo.watchAll().first).single.health, PlantHealth.bad);

      final logs = await repo.watchLogs(plantId).first;
      expect(logs, hasLength(1));
      expect(logs.single.type, PlantLogType.health);
      expect(logs.single.health, PlantHealth.bad);
      expect(logs.single.note, '葉がしおれてきた');
      expect(logs.single.occurredAt, clockNow);
      expect(logs.single.recordedAt, clockNow);
    });

    test('日時を指定できる(今日以前)。変えるたびに記録が増え、履歴で前の値がたどれる', () async {
      await repo.changeHealth(plantId, PlantHealth.watch, occurredAt: DateTime(2026, 9, 13));
      await repo.changeHealth(plantId, PlantHealth.bad, occurredAt: DateTime(2026, 9, 20));
      await repo.changeHealth(plantId, PlantHealth.recovering);
      final logs = await repo.watchLogs(plantId).first;
      expect(logs.map((l) => l.health), [PlantHealth.recovering, PlantHealth.bad, PlantHealth.watch]);
      expect((await repo.watchAll().first).single.health, PlantHealth.recovering);
    });

    test('いまと同じ状態なら、何もしない(記録も増えない)', () async {
      await repo.changeHealth(plantId, PlantHealth.good);
      final again = await repo.changeHealth(plantId, PlantHealth.good);
      expect(again.health, PlantHealth.good);
      expect(await repo.watchLogs(plantId).first, hasLength(1));
    });

    test('条件を満たさないと、株も記録も変わらない(同時に成功・失敗する)', () async {
      await expectLater(
        repo.changeHealth(plantId, PlantHealth.bad, occurredAt: clockNow.add(const Duration(days: 1))),
        throwsA(isA<PlantLogValidationException>()),
      );
      await expectLater(
        repo.changeHealth(plantId, PlantHealth.bad, note: List.filled(501, 'あ').join()),
        throwsA(isA<PlantLogValidationException>()),
      );
      expect((await repo.watchAll().first).single.health, PlantHealth.initial);
      expect(await repo.watchLogs(plantId).first, isEmpty);
    });

    test('存在しない株はエラー', () async {
      await expectLater(repo.changeHealth('nothing', PlantHealth.bad), throwsA(isA<PlantNotFoundException>()));
    });

    test('編集で株を更新しても、健康状態は変わらない', () async {
      await repo.changeHealth(plantId, PlantHealth.bad);
      final updated = await repo.update(plantId, const PlantInput(name: '改名'));
      expect(updated.health, PlantHealth.bad);
    });
  });
}
