import 'dart:async';
import 'dart:math';

import '../domain/plant.dart';
import '../domain/plant_health.dart';
import '../domain/plant_input.dart';

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

  Future<void> delete(String id);
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
  InMemoryPlantRepository({DateTime Function()? clock, IdGenerator? idGenerator})
      : _clock = clock ?? DateTime.now,
        _newId = idGenerator ?? generatePlantId;

  final DateTime Function() _clock;
  final IdGenerator _newId;
  final Map<String, Plant> _plants = {};
  final StreamController<List<Plant>> _changes = StreamController<List<Plant>>.broadcast(sync: true);

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
    if (_plants.remove(id) != null) _changes.add(_snapshot());
  }

  PlantInput _validated(PlantInput input, DateTime now) {
    final errors = validatePlantInput(input, now: now);
    if (errors.isNotEmpty) throw PlantValidationException(errors);
    return input.normalized();
  }
}
