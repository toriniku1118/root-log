import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/plant_repository.dart';
import 'data/user_repository.dart';
import 'domain/plant.dart';
import 'domain/plant_log.dart';
import 'domain/plant_photo.dart';

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

/// ユーザー情報の保存先。今はメモリ上(1人分の仮のユーザー。アプリを閉じると消える)。
/// Firebase 接続後に、本物のサインインと Firestore 版へ差し替える。
final userRepositoryProvider = Provider<UserRepository>((ref) => InMemoryUserRepository());

/// サインインの状態と、登録済みのユーザー情報。アプリの入口が、どの画面から始めるかを決めるのに使う。
final sessionProvider = StreamProvider<Session>((ref) => ref.watch(userRepositoryProvider).watchSession());

/// 株の写真の記録(新しい順)。サーバーが作ったものを、アプリは読むだけ。
final plantPhotosProvider = StreamProvider.family<List<PlantPhoto>, String>(
  (ref, plantId) => ref.watch(plantRepositoryProvider).watchPhotos(plantId),
);

/// 削除された写真の数(「削除された写真あり」)。
final deletedPhotoCountProvider = StreamProvider.family<int, String>(
  (ref, plantId) => ref.watch(plantRepositoryProvider).watchDeletedPhotoCount(plantId),
);

/// 株ごとの、最後に撮影した(サーバーが受信した)日時。写真がなければ null。ホームの「前回の撮影から○日」が使う。
final lastPhotoProvider = Provider.family<DateTime?, String>((ref, plantId) {
  final photos = ref.watch(plantPhotosProvider(plantId)).value ?? const <PlantPhoto>[];
  return photos.firstOrNull?.receivedAt; // 新しい順。最初が最新
});
