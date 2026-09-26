import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rootlog/app.dart';
import 'package:rootlog/data/plant_repository.dart';
import 'package:rootlog/data/user_repository.dart';
import 'package:rootlog/domain/plant.dart';
import 'package:rootlog/domain/plant_input.dart';
import 'package:rootlog/domain/plant_log.dart';
import 'package:rootlog/domain/plant_photo.dart';
import 'package:rootlog/features/plants/story.dart';
import 'package:rootlog/providers.dart';

/// 今日から [days] 日前の、昼の12時(0のときは今)。
DateTime daysAgo(int days) {
  final now = DateTime.now();
  if (days == 0) return now;
  final d = DateTime(now.year, now.month, now.day).subtract(Duration(days: days));
  return DateTime(d.year, d.month, d.day, 12);
}

Future<(InMemoryPlantRepository, Plant)> pumpHome(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final repo = InMemoryPlantRepository();
  final plant = await repo.add(const PlantInput(name: 'モンステラ'));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        plantRepositoryProvider.overrideWithValue(repo),
        userRepositoryProvider.overrideWithValue(InMemoryUserRepository.registered()),
      ],
      child: const RootLogApp(),
    ),
  );
  await tester.pumpAndSettle();
  return (repo, plant);
}

Future<void> openDetail(WidgetTester tester) async {
  await tester.tap(find.text('モンステラ'));
  await tester.pumpAndSettle();
}

Future<void> tapKey(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void main() {
  group('栽培ストーリーの写真の行(来歴の表示)', () {
    testWidgets('来歴つき:印と「この日時までに撮影された写真 月/日 時:分」が出る', (tester) async {
      final (repo, plant) = await pumpHome(tester);
      final at = DateTime(2026, 9, 20, 10, 3);
      repo.simulateProcessedPhoto(plant.id, receivedAt: at);
      await openDetail(tester);
      expect(find.text('写真'), findsOneWidget);
      expect(find.text('この日時までに撮影された写真 09/20 10:03'), findsOneWidget);
      expect(find.byKey(const Key('provenance-mark')), findsOneWidget);
      expect(find.text('── 2026/09/20 ──'), findsOneWidget);
    });

    testWidgets('来歴にならなかった写真は、理由が出て、印は付かない(4つの理由)', (tester) async {
      final (repo, plant) = await pumpHome(tester);
      final cases = {
        ProvenanceReason.gallery: '端末の写真のため、来歴になりません',
        ProvenanceReason.noCaptureTime: '撮影時刻が読み取れないため、来歴になりません',
        ProvenanceReason.captureTimeMismatch: '撮影時刻と受信時刻が離れているため、来歴になりません',
        ProvenanceReason.duplicate: '同じ写真が登録済みのため、来歴になりません',
      };
      var day = 1;
      for (final r in cases.keys) {
        repo.simulateProcessedPhoto(plant.id, reason: r, receivedAt: DateTime(2026, 9, day++, 10));
      }
      await openDetail(tester);
      for (final text in cases.values) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      expect(find.byKey(const Key('provenance-mark')), findsNothing);
      expect(find.textContaining('この日時までに撮影された写真'), findsNothing);
    });

    testWidgets('記録と写真が、時刻の順に混ざって出る', (tester) async {
      final (repo, plant) = await pumpHome(tester);
      await repo.addLog(plant.id, PlantLogInput(type: PlantLogType.water, occurredAt: DateTime(2026, 9, 20, 8)));
      repo.simulateProcessedPhoto(plant.id, receivedAt: DateTime(2026, 9, 20, 10));
      await repo.addLog(plant.id, PlantLogInput(type: PlantLogType.note, occurredAt: DateTime(2026, 9, 20, 12), note: 'つぼみ'));
      await tester.pumpAndSettle();
      await openDetail(tester);
      final titles = tester.widgetList<ListTile>(find.byType(ListTile)).map((t) => (t.title as Text).data).toList();
      expect(titles, containsAllInOrder(['メモ', '写真', '水やり']));
    });

    testWidgets('写真がなければ、写真の行は出ない', (tester) async {
      await pumpHome(tester);
      await openDetail(tester);
      expect(find.text('写真'), findsNothing);
    });
  });

  group('写真の拡大と削除', () {
    testWidgets('タップすると、拡大(仮の画像)と来歴の表示・「この写真を削除」が出る', (tester) async {
      final (repo, plant) = await pumpHome(tester);
      final p = repo.simulateProcessedPhoto(plant.id, receivedAt: DateTime(2026, 9, 20, 10, 3));
      await openDetail(tester);
      await tapKey(tester, 'entry-photo-${p.id}');
      expect(find.byKey(const Key('photo-placeholder')), findsOneWidget);
      expect(find.text('この日時までに撮影された写真 09/20 10:03'), findsNWidgets(2)); // 一覧と拡大
      expect(find.byKey(const Key('photo-delete')), findsOneWidget);
      await tester.tap(find.text('閉じる'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('photo-placeholder')), findsNothing);
    });

    testWidgets('削除の確認:欠落が残ることを説明する。「やめる」なら残る', (tester) async {
      final (repo, plant) = await pumpHome(tester);
      final p = repo.simulateProcessedPhoto(plant.id);
      await openDetail(tester);
      await tapKey(tester, 'entry-photo-${p.id}');
      await tapKey(tester, 'photo-delete');
      expect(find.text('写真を削除しますか?'), findsOneWidget);
      expect(find.textContaining('「削除された写真あり」の記録が残り'), findsOneWidget);
      await tester.tap(find.text('やめる'));
      await tester.pumpAndSettle();
      expect(await tester.runAsync(() => repo.watchPhotos(plant.id).first), hasLength(1));
    });

    testWidgets('削除すると、写真が消え、「削除された写真があります(1枚)」が出る。「写真を削除しました」と出る', (tester) async {
      final (repo, plant) = await pumpHome(tester);
      final p = repo.simulateProcessedPhoto(plant.id);
      await openDetail(tester);
      expect(find.byKey(const Key('deleted-photos-line')), findsNothing);
      await tapKey(tester, 'entry-photo-${p.id}');
      await tapKey(tester, 'photo-delete');
      await tapKey(tester, 'photo-delete-confirm');

      expect(find.text('写真を削除しました'), findsOneWidget);
      expect(find.text('削除された写真があります(1枚)'), findsOneWidget);
      expect(find.text('写真'), findsNothing);
      expect(await tester.runAsync(() => repo.watchPhotos(plant.id).first), isEmpty);
      expect(await tester.runAsync(() => repo.watchDeletedPhotoCount(plant.id).first), 1);
    });

    testWidgets('来歴つきの写真を全部削除すると、ホームの「来歴あり」が消える', (tester) async {
      final (repo, plant) = await pumpHome(tester);
      final p = repo.simulateProcessedPhoto(plant.id);
      await tester.pumpAndSettle();
      expect(find.byKey(Key('provenance-chip-${plant.id}')), findsOneWidget);
      await openDetail(tester);
      await tapKey(tester, 'entry-photo-${p.id}');
      await tapKey(tester, 'photo-delete');
      await tapKey(tester, 'photo-delete-confirm');
      await tester.tap(find.byTooltip('戻る'));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('provenance-chip-${plant.id}')), findsNothing);
    });
  });

  group('ホームの表示', () {
    testWidgets('来歴つきの写真がある株に「来歴あり」が出る。来歴にならない写真だけなら出ない', (tester) async {
      final (repo, plant) = await pumpHome(tester);
      expect(find.text('来歴あり'), findsNothing);
      repo.simulateProcessedPhoto(plant.id, reason: ProvenanceReason.gallery);
      await tester.pumpAndSettle();
      expect(find.text('来歴あり'), findsNothing);
      repo.simulateProcessedPhoto(plant.id);
      await tester.pumpAndSettle();
      expect(find.text('来歴あり'), findsOneWidget);
    });

    testWidgets('写真があると「前回の撮影から3日」が出る。今日なら「前回の撮影:今日」。写真がなければ出ない', (tester) async {
      final (repo, plant) = await pumpHome(tester);
      expect(find.byKey(Key('shoot-line-${plant.id}')), findsNothing);
      repo.simulateProcessedPhoto(plant.id, receivedAt: daysAgo(3));
      await tester.pumpAndSettle();
      expect(find.text('前回の撮影から3日'), findsOneWidget);
      repo.simulateProcessedPhoto(plant.id, receivedAt: daysAgo(0)); // いちばん新しい写真で数える
      await tester.pumpAndSettle();
      expect(find.text('前回の撮影:今日'), findsOneWidget);
      expect(find.text('前回の撮影から3日'), findsNothing);
    });

    testWidgets('詳細で写真を見ても、日付の見出しは受信時刻の日付', (tester) async {
      final (repo, plant) = await pumpHome(tester);
      final at = daysAgo(2);
      repo.simulateProcessedPhoto(plant.id, receivedAt: at);
      await openDetail(tester);
      expect(find.text('── ${formatDate(at)} ──'), findsOneWidget);
    });
  });
}
