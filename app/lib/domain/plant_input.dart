import 'plant_genre.dart';
import 'plant_tag.dart';

/// 各項目の文字数の上限。`firebase/firestore.rules` の `validPlantFields` と同じ値。
abstract final class PlantLimits {
  static const name = 50;
  static const variety = 80;
  static const source = 100;
  static const locationName = 30;
  static const potSize = 10;
}

enum PlantField { name, variety, acquiredAt, source, locationName, potSize }

/// 株の入力(画面のフォームの値)。文字は前後の空白を取り除き、空欄は「未設定」(null)にして扱う。
class PlantInput {
  const PlantInput({
    this.name = '',
    this.genre = defaultPlantGenre,
    this.variety,
    this.acquiredAt,
    this.source,
    this.locationName,
    this.potSize,
    this.tags = const {},
  });

  final String name;
  final PlantGenre genre;
  final String? variety;
  final DateTime? acquiredAt;
  final String? source;
  final String? locationName;
  final String? potSize;
  final Set<PlantTag> tags;

  PlantInput normalized() => PlantInput(
        name: name.trim(),
        genre: genre,
        variety: _clean(variety),
        acquiredAt: acquiredAt,
        source: _clean(source),
        locationName: _clean(locationName),
        potSize: _clean(potSize),
        tags: Set.unmodifiable(tags),
      );

  static String? _clean(String? value) {
    final v = value?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }
}

/// 入力の検証。条件は `firebase/firestore.rules` の `validPlantFields` と一致させる
/// (`test/domain/plant_rules_consistency_test.dart` で突き合わせている)。
///
/// 文字数はルールの `size()` に合わせて、UTF-16 の単位で数える(Dart の `length`。絵文字は2文字分)。
/// エミュレーターでの実測(`firebase/tests/firestore.rules.test.ts`)に基づく。
/// 戻り値は、エラーのある項目とその日本語のメッセージ。空なら問題なし。
Map<PlantField, String> validatePlantInput(PlantInput input, {required DateTime now}) {
  final v = input.normalized();
  final errors = <PlantField, String>{};

  if (v.name.isEmpty) {
    errors[PlantField.name] = '名前を入力してください';
  } else if (_length(v.name) > PlantLimits.name) {
    errors[PlantField.name] = '名前は${PlantLimits.name}文字以内で入力してください';
  }
  _checkMax(errors, PlantField.variety, '品種', v.variety, PlantLimits.variety);
  _checkMax(errors, PlantField.source, '入手先', v.source, PlantLimits.source);
  _checkMax(errors, PlantField.locationName, '置き場所', v.locationName, PlantLimits.locationName);
  _checkMax(errors, PlantField.potSize, '鉢の号数', v.potSize, PlantLimits.potSize);

  final acquiredAt = v.acquiredAt;
  if (acquiredAt != null && _dateOnly(acquiredAt).isAfter(_dateOnly(now))) {
    errors[PlantField.acquiredAt] = '入手日は今日以前の日付を選んでください';
  }
  return errors;
}

void _checkMax(Map<PlantField, String> errors, PlantField field, String label, String? value, int max) {
  if (value != null && _length(value) > max) {
    errors[field] = '$labelは$max文字以内で入力してください';
  }
}

int _length(String s) => s.length;

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// 入力が条件を満たさないときに投げる。
class PlantValidationException implements Exception {
  const PlantValidationException(this.errors);

  final Map<PlantField, String> errors;

  @override
  String toString() => 'PlantValidationException($errors)';
}
