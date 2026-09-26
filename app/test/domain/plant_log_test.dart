import 'package:flutter_test/flutter_test.dart';
import 'package:rootlog/domain/plant_health.dart';
import 'package:rootlog/domain/plant_log.dart';
import 'package:rootlog/domain/plant_stage.dart';

final now = DateTime(2026, 9, 26, 12, 0);

Map<PlantLogField, String> validate(PlantLogInput input) => validatePlantLog(input, now: now);

String chars(int n, [String c = 'あ']) => List.filled(n, c).join();

PlantLogInput log(
  PlantLogType type, {
  DateTime? occurredAt,
  String? note,
  PlantStage? stage,
  PlantHealth? health,
}) =>
    PlantLogInput(type: type, occurredAt: occurredAt ?? now, note: note, stage: stage, health: health);

void main() {
  test('記録の種類は7つで、id と日本語の表示名が決めたとおり', () {
    expect({for (final t in PlantLogType.values) t.id: t.label}, {
      'water': '水やり',
      'repot': '植え替え',
      'fertilize': '肥料',
      'prune': '剪定',
      'note': 'メモ',
      'stage': '段階',
      'health': '健康状態',
    });
    expect(PlantLogType.fromId('water'), PlantLogType.water);
    expect(PlantLogType.fromId('system'), isNull);
  });

  test('段階は8つで、id と日本語の表示名が決めたとおり(枯死も残せる)', () {
    expect({for (final s in PlantStage.values) s.id: s.label}, {
      'acquired': '入手',
      'rooted': '発根',
      'new_leaf': '新芽',
      'repotted': '植え替え',
      'flowered': '開花',
      'divided': '株分け',
      'recovered': '復活',
      'died': '枯死',
    });
    expect(PlantStage.fromId('new_leaf'), PlantStage.newLeaf);
    expect(PlantStage.fromId('unknown'), isNull);
  });

  group('メモ', () {
    test('水やりなどのメモは任意。500文字ちょうどは通り、501文字はエラー', () {
      expect(validate(log(PlantLogType.water)), isEmpty);
      expect(validate(log(PlantLogType.water, note: chars(500))), isEmpty);
      final errors = validate(log(PlantLogType.water, note: chars(501)));
      expect(errors.keys, [PlantLogField.note]);
      expect(errors[PlantLogField.note], 'メモは500文字以内で入力してください');
    });
    test('前後の空白は取り除いて数える。空白だけは未設定', () {
      expect(validate(log(PlantLogType.water, note: '  ${chars(500)}  ')), isEmpty);
      expect(log(PlantLogType.water, note: '  \n ').normalized().note, isNull);
      expect(log(PlantLogType.water, note: ' 新芽 ').normalized().note, '新芽');
    });
    test('絵文字は2文字分として数える(ルールの size() に合わせる。250個は通り、251個はエラー)', () {
      expect(validate(log(PlantLogType.water, note: chars(250, '🌱'))), isEmpty);
      expect(validate(log(PlantLogType.water, note: chars(251, '🌱'))).keys, [PlantLogField.note]);
    });
    test('種類がメモのときは、メモが必須', () {
      final errors = validate(log(PlantLogType.note));
      expect(errors.keys, [PlantLogField.note]);
      expect(errors[PlantLogField.note], 'メモを入力してください');
      expect(validate(log(PlantLogType.note, note: '   ')).keys, [PlantLogField.note]);
      expect(validate(log(PlantLogType.note, note: '新しい葉が出た')), isEmpty);
    });
  });

  group('日時', () {
    test('今の日時と過去は通り、未来はエラー', () {
      expect(validate(log(PlantLogType.water, occurredAt: now)), isEmpty);
      expect(validate(log(PlantLogType.water, occurredAt: DateTime(2020, 1, 1))), isEmpty);
      final errors = validate(log(PlantLogType.water, occurredAt: now.add(const Duration(minutes: 1))));
      expect(errors.keys, [PlantLogField.occurredAt]);
      expect(errors[PlantLogField.occurredAt], '日時は今日以前を選んでください');
    });
  });

  group('段階・健康状態', () {
    test('種類が段階のときは、段階が必須', () {
      final errors = validate(log(PlantLogType.stage));
      expect(errors.keys, [PlantLogField.stage]);
      expect(errors[PlantLogField.stage], '段階を選んでください');
      for (final s in PlantStage.values) {
        expect(validate(log(PlantLogType.stage, stage: s)), isEmpty);
      }
    });
    test('種類が健康状態のときは、健康状態が必須', () {
      final errors = validate(log(PlantLogType.health));
      expect(errors.keys, [PlantLogField.health]);
      expect(errors[PlantLogField.health], '健康状態を選んでください');
      for (final h in PlantHealth.values) {
        expect(validate(log(PlantLogType.health, health: h)), isEmpty);
      }
    });
    test('ほかの種類には、段階・健康状態を付けられない(ルールと同じ)', () {
      for (final t in PlantLogType.values.where((t) => t != PlantLogType.stage && t != PlantLogType.health)) {
        expect(
          validate(log(t, note: 'x', stage: PlantStage.rooted)).keys,
          [PlantLogField.stage],
          reason: '${t.id} に段階を付けた',
        );
        expect(
          validate(log(t, note: 'x', health: PlantHealth.bad)).keys,
          [PlantLogField.health],
          reason: '${t.id} に健康状態を付けた',
        );
      }
      expect(validate(log(PlantLogType.stage, stage: PlantStage.rooted, health: PlantHealth.bad)).keys, [PlantLogField.health]);
    });
    test('複数のエラーはまとめて返す', () {
      final errors = validate(log(PlantLogType.note, note: chars(501), occurredAt: DateTime(2030, 1, 1), stage: PlantStage.died));
      expect(errors.keys.toSet(), {PlantLogField.note, PlantLogField.occurredAt, PlantLogField.stage});
    });
  });
}
