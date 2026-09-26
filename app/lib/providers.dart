import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/plant_repository.dart';
import 'domain/plant.dart';
import 'domain/plant_log.dart';

/// 株の保存先。今はメモリ上(アプリを閉じると消える)。Firebase 接続後に Firestore 版へ差し替える。
final plantRepositoryProvider = Provider<PlantRepository>((ref) => InMemoryPlantRepository());

final plantsProvider = StreamProvider<List<Plant>>((ref) => ref.watch(plantRepositoryProvider).watchAll());

/// 株の記録(新しい順)。株の詳細の栽培ストーリーが使う。
final plantLogsProvider = StreamProvider.family<List<PlantLog>, String>(
  (ref, plantId) => ref.watch(plantRepositoryProvider).watchLogs(plantId),
);
