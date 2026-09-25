import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/plant_repository.dart';
import 'domain/plant.dart';

/// 株の保存先。今はメモリ上(アプリを閉じると消える)。Firebase 接続後に Firestore 版へ差し替える。
final plantRepositoryProvider = Provider<PlantRepository>((ref) => InMemoryPlantRepository());

final plantsProvider = StreamProvider<List<Plant>>((ref) => ref.watch(plantRepositoryProvider).watchAll());
