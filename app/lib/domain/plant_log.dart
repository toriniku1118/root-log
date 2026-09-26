import 'plant_health.dart';
import 'plant_stage.dart';

/// 記録の種類。`id` は `firebase/firestore.rules` の記録の `type` と同じ文字列。
enum PlantLogType {
  water('water', '水やり'),
  repot('repot', '植え替え'),
  fertilize('fertilize', '肥料'),
  prune('prune', '剪定'),
  note('note', 'メモ'),
  stage('stage', '段階'),
  health('health', '健康状態');

  const PlantLogType(this.id, this.label);

  final String id;
  final String label;

  static PlantLogType? fromId(String id) {
    for (final t in values) {
      if (t.id == id) return t;
    }
    return null;
  }
}

/// 記録の入力条件。`firebase/firestore.rules` の `validLog` と同じ値。
abstract final class PlantLogLimits {
  /// メモの文字数の上限(UTF-16 の単位。絵文字は2文字分)。
  static const note = 500;
}

/// 株の記録(水やり・植え替え・肥料・剪定・メモ・段階・健康状態の変更)。
class PlantLog {
  const PlantLog({
    required this.id,
    required this.plantId,
    required this.type,
    required this.occurredAt,
    required this.recordedAt,
    this.note,
    this.stage,
    this.health,
  });

  final String id;
  final String plantId;
  final PlantLogType type;

  /// 出来事の日時(今日以前。本人が直せる)。
  final DateTime occurredAt;

  /// 記録した時刻(サーバー時刻で固定。後から変えられない)。
  final DateTime recordedAt;
  final String? note;

  /// 種類が段階のときの段階。
  final PlantStage? stage;

  /// 種類が健康状態のときの、変更後の健康状態。
  final PlantHealth? health;
}

enum PlantLogField { occurredAt, note, stage, health }

/// 記録の入力。メモは前後の空白を取り除き、空欄は「未設定」(null)にして扱う。
class PlantLogInput {
  const PlantLogInput({
    required this.type,
    required this.occurredAt,
    this.note,
    this.stage,
    this.health,
  });

  final PlantLogType type;
  final DateTime occurredAt;
  final String? note;
  final PlantStage? stage;
  final PlantHealth? health;

  PlantLogInput normalized() {
    final n = note?.trim();
    return PlantLogInput(
      type: type,
      occurredAt: occurredAt,
      note: (n == null || n.isEmpty) ? null : n,
      stage: stage,
      health: health,
    );
  }
}

/// 記録の検証。条件は `firebase/firestore.rules` の `validLog` と一致させる
/// (`test/domain/plant_rules_consistency_test.dart` で突き合わせている)。
///
/// - メモは500文字まで(UTF-16 の単位)。種類がメモのときは必須。
/// - 日時は今日以前(未来は不可)。
/// - 種類が段階のときは段階が必須、健康状態のときは健康状態が必須。ほかの種類では付けられない。
Map<PlantLogField, String> validatePlantLog(PlantLogInput input, {required DateTime now}) {
  final v = input.normalized();
  final errors = <PlantLogField, String>{};

  final note = v.note;
  if (note != null && note.length > PlantLogLimits.note) {
    errors[PlantLogField.note] = 'メモは${PlantLogLimits.note}文字以内で入力してください';
  } else if (v.type == PlantLogType.note && note == null) {
    errors[PlantLogField.note] = 'メモを入力してください';
  }
  if (v.occurredAt.isAfter(now)) {
    errors[PlantLogField.occurredAt] = '日時は今日以前を選んでください';
  }
  if (v.type == PlantLogType.stage) {
    if (v.stage == null) errors[PlantLogField.stage] = '段階を選んでください';
  } else if (v.stage != null) {
    errors[PlantLogField.stage] = '段階は、種類が段階のときだけ選べます';
  }
  if (v.type == PlantLogType.health) {
    if (v.health == null) errors[PlantLogField.health] = '健康状態を選んでください';
  } else if (v.health != null) {
    errors[PlantLogField.health] = '健康状態は、種類が健康状態のときだけ選べます';
  }
  return errors;
}

/// 記録の入力が条件を満たさないときに投げる。
class PlantLogValidationException implements Exception {
  const PlantLogValidationException(this.errors);

  final Map<PlantLogField, String> errors;

  @override
  String toString() => 'PlantLogValidationException($errors)';
}

class PlantLogNotFoundException implements Exception {
  const PlantLogNotFoundException(this.id);

  final String id;

  @override
  String toString() => 'PlantLogNotFoundException($id)';
}
