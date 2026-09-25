import 'package:flutter_test/flutter_test.dart';
import 'package:rootlog/domain/plant_genre.dart';
import 'package:rootlog/domain/plant_input.dart';
import 'package:rootlog/domain/plant_tag.dart';

final now = DateTime(2026, 9, 25, 12, 0);

Map<PlantField, String> validate(PlantInput input) => validatePlantInput(input, now: now);

String chars(int n, [String c = 'あ']) => List.filled(n, c).join();

void main() {
  group('購入価格(任意・円の整数。0〜99,999,999)', () {
    test('未設定(null)・0・上限ちょうどは通る', () {
      expect(validate(const PlantInput(name: 'x')), isEmpty);
      expect(validate(const PlantInput(name: 'x', purchasePrice: 0)), isEmpty);
      expect(validate(const PlantInput(name: 'x', purchasePrice: 12800)), isEmpty);
      expect(validate(const PlantInput(name: 'x', purchasePrice: PlantLimits.purchasePrice)), isEmpty);
    });
    test('上限を1円超えるとエラー(メッセージにはカンマ区切りの上限が入る)', () {
      final errors = validate(const PlantInput(name: 'x', purchasePrice: PlantLimits.purchasePrice + 1));
      expect(errors.keys, [PlantField.purchasePrice]);
      expect(errors[PlantField.purchasePrice], '購入価格は99,999,999円以下で入力してください');
    });
    test('負の数はエラー', () {
      final errors = validate(const PlantInput(name: 'x', purchasePrice: -1));
      expect(errors.keys, [PlantField.purchasePrice]);
      expect(errors[PlantField.purchasePrice], '購入価格は0以上の整数で入力してください');
    });
    test('正規化しても購入価格はそのまま', () {
      expect(const PlantInput(name: ' x ', purchasePrice: 500).normalized().purchasePrice, 500);
    });
  });

  group('名前', () {
    test('1文字と50文字は通る', () {
      expect(validate(PlantInput(name: 'a')), isEmpty);
      expect(validate(PlantInput(name: chars(50))), isEmpty);
    });
    test('空・空白だけはエラー', () {
      expect(validate(const PlantInput()).keys, [PlantField.name]);
      expect(validate(const PlantInput(name: '   　 ')).keys, [PlantField.name]);
    });
    test('51文字はエラー', () {
      final errors = validate(PlantInput(name: chars(51)));
      expect(errors.keys, [PlantField.name]);
      expect(errors[PlantField.name], '名前は50文字以内で入力してください');
    });
    test('前後の空白は取り除いて数える', () {
      expect(validate(PlantInput(name: '  ${chars(50)}  ')), isEmpty);
    });
    test('絵文字は2文字分として数える(ルールの size() の実測に合わせる。25個は通り、26個はエラー)', () {
      expect(validate(PlantInput(name: chars(25, '🌱'))), isEmpty);
      expect(validate(PlantInput(name: chars(26, '🌱'))).keys, [PlantField.name]);
    });
  });

  group('任意の文字項目(上限ちょうどは通り、1文字超えるとエラー)', () {
    final cases = <String, (int, PlantField, PlantInput Function(String))>{
      '品種': (80, PlantField.variety, (s) => PlantInput(name: 'x', variety: s)),
      '入手先': (100, PlantField.source, (s) => PlantInput(name: 'x', source: s)),
      '置き場所': (30, PlantField.locationName, (s) => PlantInput(name: 'x', locationName: s)),
      '鉢の号数': (10, PlantField.potSize, (s) => PlantInput(name: 'x', potSize: s)),
    };
    cases.forEach((label, c) {
      final (max, field, build) = c;
      test('$label:$max文字は通る', () => expect(validate(build(chars(max))), isEmpty));
      test('$label:${max + 1}文字はエラー', () {
        final errors = validate(build(chars(max + 1)));
        expect(errors.keys, [field]);
        expect(errors[field], '$labelは$max文字以内で入力してください');
      });
    });
    test('空欄・空白だけは「未設定」として通る', () {
      expect(validate(const PlantInput(name: 'x', variety: '', source: '  ', locationName: '　', potSize: '')), isEmpty);
    });
  });

  group('入手日', () {
    test('今日・過去は通る。未設定も通る', () {
      expect(validate(PlantInput(name: 'x', acquiredAt: DateTime(2026, 9, 25, 23, 59))), isEmpty);
      expect(validate(PlantInput(name: 'x', acquiredAt: DateTime(2020, 1, 1))), isEmpty);
      expect(validate(const PlantInput(name: 'x')), isEmpty);
    });
    test('明日以降はエラー', () {
      final errors = validate(PlantInput(name: 'x', acquiredAt: DateTime(2026, 9, 26)));
      expect(errors.keys, [PlantField.acquiredAt]);
    });
  });

  group('正規化', () {
    test('前後の空白を取り除き、空欄は null にする', () {
      final v = const PlantInput(name: ' モンステラ ', variety: ' デリシオーサ ', source: '   ', tags: {PlantTag.rescue}).normalized();
      expect(v.name, 'モンステラ');
      expect(v.variety, 'デリシオーサ');
      expect(v.source, isNull);
      expect(v.tags, {PlantTag.rescue});
    });
    test('初期ジャンルは観葉植物全般', () {
      expect(const PlantInput().genre, PlantGenre.foliage);
    });
    test('複数のエラーはまとめて返す', () {
      final errors = validate(PlantInput(name: '', variety: chars(81), acquiredAt: DateTime(2027, 1, 1)));
      expect(errors.keys.toSet(), {PlantField.name, PlantField.variety, PlantField.acquiredAt});
    });
  });
}
