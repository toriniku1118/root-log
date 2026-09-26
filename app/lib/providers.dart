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

/// 株ごとの、最後の水やりの日時(出来事の日時)。水やりの記録がなければ null。
/// ホームの「水やり:3日前」と、詳細の「前回の水やり」が使う。
final lastWateredProvider = Provider.family<DateTime?, String>((ref, plantId) {
  final logs = ref.watch(plantLogsProvider(plantId)).value ?? const <PlantLog>[];
  // 記録は新しい順。最初の水やりが、最後の水やり
  return logs.where((l) => l.type == PlantLogType.water).firstOrNull?.occurredAt;
});
