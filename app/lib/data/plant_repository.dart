import 'dart:async';
import 'dart:math';

import '../domain/plant.dart';
import '../domain/plant_health.dart';
import '../domain/plant_input.dart';
import '../domain/plant_log.dart';

/// 株の保存先の差し替え口。画面は保存先(メモリ・Firestore)を知らない。
///
/// 更新は、サーバーが付ける項目(来歴の印など)を消さないこと。
abstract interface class PlantRepository {
  /// 株の一覧。購読した時点の内容がすぐ流れ、変更のたびに新しい一覧が流れる。
  Stream<List<Plant>> watchAll();

  /// 株を追加する。新しい株は初期公開(範囲は写真のみ)。条件を満たさない入力は [PlantValidationException]。
  Future<Plant> add(PlantInput input);

  /// 株を更新する(共有設定・作成日時は変えない)。存在しなければ [PlantNotFoundException]。
  Future<Plant> update(String id, PlantInput input);

  /// 株を削除する。存在しなくてもエラーにしない。その株の記録も消える(サーバーの後片付けに相当)。
  Future<void> delete(String id);

  /// 株の記録の一覧(新しい順:出来事の日時 → 記録した時刻の順)。購読した時点の内容がすぐ流れ、
  /// 変更のたびに新しい一覧が流れる。株がなければ空。
  Stream<List<PlantLog>> watchLogs(String plantId);

  /// 記録を追加する。記録した時刻(`recordedAt`)は保存先の時刻で決まる。
  /// 株がなければ [PlantNotFoundException]、条件を満たさなければ [PlantLogValidationException]。
  Future<PlantLog> addLog(String plantId, PlantLogInput input);

  /// 記録のメモと日時を直す。種類・段階・健康状態・記録した時刻は変えられない。
  /// 記録がなければ [PlantLogNotFoundException]、条件を満たさなければ [PlantLogValidationException]。
  Future<PlantLog> updateLog(String plantId, String logId, {required DateTime occurredAt, String? note});

  /// 記録を削除する。存在しなくてもエラーにしない。
  Future<void> deleteLog(String plantId, String logId);

  /// 株の健康状態を変え、変更を記録(種類 health)として残す。株の更新と記録の追加は、同時に成功するか同時に失敗する。
  /// いまと同じ状態なら、何もしない(記録も増えない)。株がなければ [PlantNotFoundException]、
  /// 条件を満たさなければ [PlantLogValidationException](株も記録も変わらない)。
  Future<Plant> changeHealth(String plantId, PlantHealth health, {String? note, DateTime? occurredAt});
}

class PlantNotFoundException implements Exception {
  const PlantNotFoundException(this.id);

  final String id;

  @override
  String toString() => 'PlantNotFoundException($id)';
}

typedef IdGenerator = String Function();

/// 20文字の英数字。写真のアップロード先の植物ID条件(`^[A-Za-z0-9_-]{1,64}$`)を満たす。
String generatePlantId() {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  final random = Random.secure();
  return List.generate(20, (_) => chars[random.nextInt(chars.length)]).join();
}

/// メモリ上の保存先。アプリを閉じると消える。Firebase 接続前と、テストで使う。
class InMemoryPlantRepository implements PlantRepository {
  InMemoryPlantRepository({DateTime Function()? clock, IdGenerator? idGenerator, IdGenerator? logIdGenerator})
      : _clock = clock ?? DateTime.now,
        _newId = idGenerator ?? generatePlantId,
        _newLogId = logIdGenerator ?? generatePlantId;

  final DateTime Function() _clock;
  final IdGenerator _newId;
  final IdGenerator _newLogId;
  final Map<String, Plant> _plants = {};
  final StreamController<List<Plant>> _changes = StreamController<List<Plant>>.broadcast(sync: true);

  /// 株の id → 記録(追加した順)。
  final Map<String, List<PlantLog>> _logs = {};
  final StreamController<String> _logChanges = StreamController<String>.broadcast(sync: true);

  List<Plant> _snapshot() => List.unmodifiable(_plants.values);

  @override
  Stream<List<Plant>> watchAll() {
    late final StreamController<List<Plant>> controller;
    StreamSubscription<List<Plant>>? subscription;
    controller = StreamController<List<Plant>>(
      onListen: () {
        controller.add(_snapshot());
        subscription = _changes.stream.listen(controller.add);
      },
      onCancel: () => subscription?.cancel(),
    );
    return controller.stream;
  }

  @override
  Future<Plant> add(PlantInput input) async {
    final now = _clock();
    final v = _validated(input, now);
    var id = _newId();
    while (_plants.containsKey(id)) {
      id = _newId();
    }
    final plant = Plant(
      id: id,
      name: v.name,
      genres: v.genres,
      variety: v.variety,
      acquiredAt: v.acquiredAt,
      source: v.source,
      locationName: v.locationName,
      potSize: v.potSize,
      purchasePrice: v.purchasePrice,
      health: defaultPlantHealth,
      tags: v.tags,
      visibility: const PlantVisibility.defaultVisibility(),
      createdAt: now,
      updatedAt: now,
    );
    _plants[id] = plant;
    _changes.add(_snapshot());
    return plant;
  }

  @override
  Future<Plant> update(String id, PlantInput input) async {
    final current = _plants[id];
    if (current == null) throw PlantNotFoundException(id);
    final now = _clock();
    final v = _validated(input, now);
    final plant = Plant(
      id: id,
      name: v.name,
      genres: v.genres,
      variety: v.variety,
      acquiredAt: v.acquiredAt,
      source: v.source,
      locationName: v.locationName,
      potSize: v.potSize,
      purchasePrice: v.purchasePrice,
      health: current.health, // 健康状態は、編集画面ではなく、株の詳細で変える(変更は記録として残す)
      tags: v.tags,
      visibility: current.visibility,
      createdAt: current.createdAt,
      updatedAt: now,
    );
    _plants[id] = plant;
    _changes.add(_snapshot());
    return plant;
  }

  @override
  Future<void> delete(String id) async {
    final hadLogs = _logs.remove(id) != null;
    if (_plants.remove(id) != null) _changes.add(_snapshot());
    if (hadLogs) _logChanges.add(id);
  }

  /// 新しい順:出来事の日時 → 記録した時刻 → 追加した順(あとのものが上)。
  List<PlantLog> _logSnapshot(String plantId) {
    final logs = _logs[plantId] ?? const <PlantLog>[];
    final indexed = [for (var i = 0; i < logs.length; i++) (i, logs[i])];
    indexed.sort((a, b) {
      final byOccurred = b.$2.occurredAt.compareTo(a.$2.occurredAt);
      if (byOccurred != 0) return byOccurred;
      final byRecorded = b.$2.recordedAt.compareTo(a.$2.recordedAt);
      return byRecorded != 0 ? byRecorded : b.$1.compareTo(a.$1);
    });
    return List.unmodifiable([for (final e in indexed) e.$2]);
  }

  @override
  Stream<List<PlantLog>> watchLogs(String plantId) {
    late final StreamController<List<PlantLog>> controller;
    StreamSubscription<String>? subscription;
    controller = StreamController<List<PlantLog>>(
      onListen: () {
        controller.add(_logSnapshot(plantId));
        subscription = _logChanges.stream.where((id) => id == plantId).listen((_) => controller.add(_logSnapshot(plantId)));
      },
      onCancel: () => subscription?.cancel(),
    );
    return controller.stream;
  }

  @override
  Future<PlantLog> addLog(String plantId, PlantLogInput input) async {
    if (!_plants.containsKey(plantId)) throw PlantNotFoundException(plantId);
    final now = _clock();
    final v = _validatedLog(input, now);
    final log = _newLog(plantId, v, now);
    _logs.putIfAbsent(plantId, () => []).add(log);
    _logChanges.add(plantId);
    return log;
  }

  @override
  Future<PlantLog> updateLog(String plantId, String logId, {required DateTime occurredAt, String? note}) async {
    final logs = _logs[plantId];
    final index = logs?.indexWhere((l) => l.id == logId) ?? -1;
    if (logs == null || index < 0) throw PlantLogNotFoundException(logId);
    final current = logs[index];
    final v = _validatedLog(
      PlantLogInput(type: current.type, occurredAt: occurredAt, note: note, stage: current.stage, health: current.health),
      _clock(),
    );
    final updated = PlantLog(
      id: current.id,
      plantId: plantId,
      type: current.type,
      occurredAt: v.occurredAt,
      recordedAt: current.recordedAt, // 記録した時刻は変えられない
      note: v.note,
      stage: current.stage,
      health: current.health,
    );
    logs[index] = updated;
    _logChanges.add(plantId);
    return updated;
  }

  @override
  Future<void> deleteLog(String plantId, String logId) async {
    final logs = _logs[plantId];
    if (logs == null) return;
    final before = logs.length;
    logs.removeWhere((l) => l.id == logId);
    if (logs.length != before) _logChanges.add(plantId);
  }

  @override
  Future<Plant> changeHealth(String plantId, PlantHealth health, {String? note, DateTime? occurredAt}) async {
    final current = _plants[plantId];
    if (current == null) throw PlantNotFoundException(plantId);
    if (current.health == health) return current;
    final now = _clock();
    // 先に検証する(失敗したら、株も記録も変えない)
    final v = _validatedLog(
      PlantLogInput(type: PlantLogType.health, occurredAt: occurredAt ?? now, note: note, health: health),
      now,
    );
    final plant = current.withHealth(health, updatedAt: now);
    final log = _newLog(plantId, v, now);
    _plants[plantId] = plant;
    _logs.putIfAbsent(plantId, () => []).add(log);
    _changes.add(_snapshot());
    _logChanges.add(plantId);
    return plant;
  }

  PlantLog _newLog(String plantId, PlantLogInput v, DateTime recordedAt) {
    final existing = {for (final l in _logs[plantId] ?? const <PlantLog>[]) l.id};
    var id = _newLogId();
    while (existing.contains(id)) {
      id = _newLogId();
    }
    return PlantLog(
      id: id,
      plantId: plantId,
      type: v.type,
      occurredAt: v.occurredAt,
      recordedAt: recordedAt,
      note: v.note,
      stage: v.stage,
      health: v.health,
    );
  }

  PlantLogInput _validatedLog(PlantLogInput input, DateTime now) {
    final errors = validatePlantLog(input, now: now);
    if (errors.isNotEmpty) throw PlantLogValidationException(errors);
    return input.normalized();
  }

  PlantInput _validated(PlantInput input, DateTime now) {
    final errors = validatePlantInput(input, now: now);
    if (errors.isNotEmpty) throw PlantValidationException(errors);
    return input.normalized();
  }
}
