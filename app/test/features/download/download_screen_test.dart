import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rootlog/app.dart';
import 'package:rootlog/data/photo_saver.dart';
import 'package:rootlog/data/plant_repository.dart';
import 'package:rootlog/data/user_repository.dart';
import 'package:rootlog/domain/plant_input.dart';
import 'package:rootlog/domain/plant_photo.dart';
import 'package:rootlog/providers.dart';

class Fixture {
  Fixture(this.repo, this.saver, this.monstera, this.agave);

  final InMemoryPlantRepository repo;
  final InMemoryPhotoSaver saver;
  final String monstera;
  final String agave;
}

/// モンステラ2枚・アガベ1枚(受信時刻はそれぞれ違う日)がある状態でアプリを開く。
Future<Fixture> pumpApp(WidgetTester tester, {InMemoryPhotoSaver? saver}) async {
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final repo = InMemoryPlantRepository();
  final m = (await repo.add(const PlantInput(name: 'モンステラ'))).id;
  final a = (await repo.add(const PlantInput(name: 'アガベ'))).id;
  repo.simulateProcessedPhoto(m, receivedAt: DateTime(2026, 9, 1, 10));
  repo.simulateProcessedPhoto(m, receivedAt: DateTime(2026, 9, 20, 10, 3, 5));
  repo.simulateProcessedPhoto(a, receivedAt: DateTime(2026, 9, 10, 9, 30), reason: ProvenanceReason.gallery);
  final s = saver ?? InMemoryPhotoSaver();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        plantRepositoryProvider.overrideWithValue(repo),
        userRepositoryProvider.overrideWithValue(InMemoryUserRepository.registered()),
        photoSaverProvider.overrideWithValue(s),
      ],
      child: const RootLogApp(),
    ),
  );
  await tester.pumpAndSettle();
  return Fixture(repo, s, m, a);
}

Future<void> tapKey(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

Future<void> openFromSettings(WidgetTester tester) async {
  await tapKey(tester, 'open-settings');
  await tapKey(tester, 'open-download');
}

String countText(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('dl-count'))).data!;

void main() {
  group('入口', () {
    testWidgets('設定から開くと、全株が選ばれている', (tester) async {
      final f = await pumpApp(tester);
      await openFromSettings(tester);
      expect(find.text('写真をダウンロード'), findsOneWidget); // 画面のタイトル(設定の項目は下に隠れる)
      expect(tester.widget<CheckboxListTile>(find.byKey(const Key('dl-plant-all'))).value, isTrue);
      expect(tester.widget<CheckboxListTile>(find.byKey(Key('dl-plant-${f.monstera}'))).value, isTrue);
      expect(tester.widget<CheckboxListTile>(find.byKey(Key('dl-plant-${f.agave}'))).value, isTrue);
      expect(countText(tester), '3枚が対象です');
      expect(find.byKey(const Key('dl-period-all')), findsOneWidget);
    });

    testWidgets('株の詳細から開くと、その株だけが選ばれている', (tester) async {
      final f = await pumpApp(tester);
      await tester.tap(find.text('アガベ'));
      await tester.pumpAndSettle();
      await tapKey(tester, 'open-download');
      expect(tester.widget<CheckboxListTile>(find.byKey(const Key('dl-plant-all'))).value, isFalse);
      expect(tester.widget<CheckboxListTile>(find.byKey(Key('dl-plant-${f.agave}'))).value, isTrue);
      expect(tester.widget<CheckboxListTile>(find.byKey(Key('dl-plant-${f.monstera}'))).value, isFalse);
      expect(countText(tester), '1枚が対象です');
    });

    testWidgets('アカウント削除の画面の「先に写真をダウンロード」から開ける。戻ると削除の画面に戻る', (tester) async {
      await pumpApp(tester);
      await tapKey(tester, 'open-settings');
      await tapKey(tester, 'open-delete-account');
      await tapKey(tester, 'download-first');
      expect(find.byKey(const Key('dl-save')), findsOneWidget);
      await tester.tap(find.byTooltip('戻る'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('delete-account')), findsOneWidget);
    });
  });

  group('絞り込み', () {
    testWidgets('株を外すと、枚数が減る。「すべて」で戻る', (tester) async {
      final f = await pumpApp(tester);
      await openFromSettings(tester);
      await tapKey(tester, 'dl-plant-${f.monstera}');
      expect(countText(tester), '1枚が対象です');
      expect(tester.widget<CheckboxListTile>(find.byKey(const Key('dl-plant-all'))).value, isFalse);
      await tapKey(tester, 'dl-plant-all');
      expect(countText(tester), '3枚が対象です');
    });

    testWidgets('株をすべて外すと「対象の写真がありません」で、保存できない', (tester) async {
      final f = await pumpApp(tester);
      await openFromSettings(tester);
      await tapKey(tester, 'dl-plant-${f.monstera}');
      await tapKey(tester, 'dl-plant-${f.agave}');
      expect(find.text('対象の写真がありません'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const Key('dl-save'))).onPressed, isNull);
    });

    testWidgets('写真を選ぶ:1枚外すと枚数が減る。「やめる」なら変わらない。戻すと増える', (tester) async {
      final f = await pumpApp(tester);
      await openFromSettings(tester);
      final photos = await tester.runAsync(() => f.repo.watchPhotos(f.monstera).first);
      final oldest = photos!.last;

      await tapKey(tester, 'dl-choose-photos');
      await tapKey(tester, 'dl-photo-${oldest.id}');
      await tester.tap(find.text('やめる'));
      await tester.pumpAndSettle();
      expect(countText(tester), '3枚が対象です');

      await tapKey(tester, 'dl-choose-photos');
      await tapKey(tester, 'dl-photo-${oldest.id}');
      await tapKey(tester, 'dl-photos-apply');
      expect(countText(tester), '2枚が対象です');

      await tapKey(tester, 'dl-choose-photos');
      expect(tester.widget<CheckboxListTile>(find.byKey(Key('dl-photo-${oldest.id}'))).value, isFalse);
      await tapKey(tester, 'dl-photo-${oldest.id}');
      await tapKey(tester, 'dl-photos-apply');
      expect(countText(tester), '3枚が対象です');
    });

    testWidgets('期間:開始日を「今日」にすると、今日より前の写真が外れる。「すべての期間」で戻る', (tester) async {
      final f = await pumpApp(tester);
      f.repo.simulateProcessedPhoto(f.monstera, receivedAt: DateTime.now());
      await openFromSettings(tester);
      expect(countText(tester), '4枚が対象です');

      await tapKey(tester, 'dl-from');
      expect(tester.widget<CalendarDatePicker>(find.byType(CalendarDatePicker)).lastDate.day, DateTime.now().day);
      await tester.tap(find.text('OK')); // 初期表示は今日
      await tester.pumpAndSettle();
      expect(countText(tester), '1枚が対象です');
      expect(find.byKey(const Key('dl-period-all')), findsNothing);

      await tapKey(tester, 'dl-clear-period');
      expect(countText(tester), '4枚が対象です');
      expect(find.byKey(const Key('dl-period-all')), findsOneWidget);
    });

    testWidgets('期間:終了日を「今日」にしても、今日までの写真は全部入る', (tester) async {
      await pumpApp(tester);
      await openFromSettings(tester);
      await tapKey(tester, 'dl-to');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(countText(tester), '3枚が対象です');
    });
  });

  group('保存', () {
    testWidgets('保存すると、受信時刻の古い順・株ごとの連番で、1枚ずつ保存される', (tester) async {
      final f = await pumpApp(tester);
      await openFromSettings(tester);
      await tapKey(tester, 'dl-save');
      expect(f.saver.saved, [
        'モンステラ_001_20260901-100000.jpg',
        'アガベ_001_20260910-093000.jpg',
        'モンステラ_002_20260920-100305.jpg',
      ]);
      expect(find.text('3枚を保存しました'), findsOneWidget);
      expect(find.byKey(const Key('dl-progress')), findsNothing); // 終わったら進み具合は消える
    });

    testWidgets('外した写真・外した株は保存されない', (tester) async {
      final f = await pumpApp(tester);
      await openFromSettings(tester);
      await tapKey(tester, 'dl-plant-${f.agave}');
      await tapKey(tester, 'dl-save');
      expect(f.saver.saved, hasLength(2));
      expect(f.saver.saved.every((n) => n.startsWith('モンステラ_')), isTrue);
    });

    testWidgets('実際には保存しない版であることを、画面に出す', (tester) async {
      await pumpApp(tester);
      await openFromSettings(tester);
      expect(find.byKey(const Key('dl-placeholder-note')), findsOneWidget);
      expect(find.textContaining('実際には保存されません'), findsOneWidget);
    });

    testWidgets('保存中は「1 / 3枚」と進み、条件は変えられない。「やめる」で止まり、保存済みは残る', (tester) async {
      final gate = Completer<void>();
      final saver = InMemoryPhotoSaver(beforeSave: (name) async {
        // 2枚目の保存を、テストが許すまで止めておく
        if (name.startsWith('アガベ_')) await gate.future;
      });
      await pumpApp(tester, saver: saver);
      await openFromSettings(tester);
      await tester.tap(find.byKey(const Key('dl-save')));
      await tester.pump();
      await tester.pump();

      expect(find.text('1 / 3枚'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(find.byKey(const Key('dl-from'))).onPressed, isNull);
      expect(find.byKey(const Key('dl-save')), findsNothing);

      await tester.tap(find.byKey(const Key('dl-cancel')));
      await tester.pump();
      expect(find.text('やめています…'), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();

      // 止めた時点で保存中だった1枚(2枚目)は終わり、3枚目は保存されない
      expect(saver.saved, ['モンステラ_001_20260901-100000.jpg', 'アガベ_001_20260910-093000.jpg']);
      expect(find.text('やめました(2枚は保存済みです)'), findsOneWidget);
      expect(find.byKey(const Key('dl-save')), findsOneWidget);
    });

    testWidgets('保存が許可されていないとき:許可の案内。保存済みは残る', (tester) async {
      final saver = InMemoryPhotoSaver(failure: PhotoSaveFailure.permissionDenied, failAtCount: 1);
      await pumpApp(tester, saver: saver);
      await openFromSettings(tester);
      await tapKey(tester, 'dl-save');
      expect(saver.saved, hasLength(1));
      expect(find.text('保存できませんでした。写真フォルダへの保存を許可してください(1枚は保存済みです)'), findsOneWidget);
      expect(find.byKey(const Key('dl-save')), findsOneWidget); // もう一度試せる
    });

    testWidgets('写真を読み込めなかったとき:「写真を読み込めませんでした」', (tester) async {
      final saver = InMemoryPhotoSaver(failure: PhotoSaveFailure.readFailed, failAtCount: 0);
      await pumpApp(tester, saver: saver);
      await openFromSettings(tester);
      await tapKey(tester, 'dl-save');
      expect(find.text('写真を読み込めませんでした。もう一度試してください'), findsOneWidget);
      expect(saver.saved, isEmpty);
    });

    testWidgets('写真がない人は「対象の写真がありません」', (tester) async {
      tester.view.physicalSize = const Size(800, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            plantRepositoryProvider.overrideWithValue(InMemoryPlantRepository()),
            userRepositoryProvider.overrideWithValue(InMemoryUserRepository.registered()),
          ],
          child: const RootLogApp(),
        ),
      );
      await tester.pumpAndSettle();
      await openFromSettings(tester);
      expect(find.text('対象の写真がありません'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const Key('dl-save'))).onPressed, isNull);
    });

    testWidgets('削除した写真は対象に入らない', (tester) async {
      final f = await pumpApp(tester);
      final photos = await tester.runAsync(() => f.repo.watchPhotos(f.agave).first);
      await tester.runAsync(() => f.repo.deletePhoto(f.agave, photos!.single.id));
      await tester.pumpAndSettle();
      await openFromSettings(tester);
      expect(countText(tester), '2枚が対象です');
      await tapKey(tester, 'dl-save');
      expect(f.saver.saved.any((n) => n.startsWith('アガベ_')), isFalse);
    });
  });
}
