import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rootlog/app.dart';
import 'package:rootlog/data/plant_repository.dart';
import 'package:rootlog/data/user_repository.dart';
import 'package:rootlog/domain/plant.dart';
import 'package:rootlog/domain/plant_health.dart';
import 'package:rootlog/domain/plant_input.dart';
import 'package:rootlog/domain/plant_log.dart';
import 'package:rootlog/domain/plant_tag.dart';
import 'package:rootlog/features/plants/story.dart';
import 'package:rootlog/providers.dart';

/// 今日から [days] 日前の、昼の12時(今日の場合は今)。
DateTime daysAgo(int days) {
  final now = DateTime.now();
  if (days == 0) return now;
  final d = DateTime(now.year, now.month, now.day).subtract(Duration(days: days));
  return DateTime(d.year, d.month, d.day, 12);
}

Future<(InMemoryPlantRepository, List<Plant>)> pumpHome(WidgetTester tester, List<PlantInput> inputs) async {
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final repo = InMemoryPlantRepository();
  final plants = [for (final i in inputs) await repo.add(i)];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        plantRepositoryProvider.overrideWithValue(repo),
        userRepositoryProvider.overrideWithValue(InMemoryUserRepository.registered()), // 登録済みのユーザーで始める
      ],
      child: const RootLogApp(),
    ),
  );
  await tester.pumpAndSettle();
  return (repo, plants);
}

Future<List<PlantLog>> logsOf(WidgetTester tester, PlantRepository repo, String plantId) async =>
    (await tester.runAsync(() => repo.watchLogs(plantId).first))!;

PlantLogInput water(DateTime at) => PlantLogInput(type: PlantLogType.water, occurredAt: at);

void main() {
  group('長押しで水やり', () {
    testWidgets('株を長押しすると、水やりが記録され、メッセージと「取り消し」が出る。ホームに「水やり:今日」が出る', (tester) async {
      final (repo, plants) = await pumpHome(tester, [const PlantInput(name: 'モンステラ')]);
      expect(find.byKey(Key('water-line-${plants.single.id}')), findsNothing); // 記録がなければ出ない

      await tester.longPress(find.text('モンステラ'));
      await tester.pumpAndSettle();

      expect(find.text('「モンステラ」に水やりを記録しました'), findsOneWidget);
      expect(find.text('取り消し'), findsOneWidget);
      expect(find.text('水やり:今日'), findsOneWidget);
      final logs = await logsOf(tester, repo, plants.single.id);
      expect(logs.single.type, PlantLogType.water);
      // 詳細は開かない(長押しは、タップとは別の操作)
      expect(find.byKey(const Key('edit')), findsNothing);
    });

    testWidgets('「取り消し」で、記録が消え、「水やり:…」の行も消える', (tester) async {
      final (repo, plants) = await pumpHome(tester, [const PlantInput(name: 'モンステラ')]);
      await tester.longPress(find.text('モンステラ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取り消し'));
      await tester.pumpAndSettle();
      expect(await logsOf(tester, repo, plants.single.id), isEmpty);
      expect(find.text('水やり:今日'), findsNothing);
    });

    testWidgets('別の株を長押しすると、その株にだけ記録される', (tester) async {
      final (repo, plants) = await pumpHome(tester, [
        const PlantInput(name: 'モンステラ'),
        const PlantInput(name: 'パキラ'),
      ]);
      await tester.longPress(find.text('パキラ'));
      await tester.pumpAndSettle();
      expect(find.text('「パキラ」に水やりを記録しました'), findsOneWidget);
      expect(await logsOf(tester, repo, plants[0].id), isEmpty);
      expect(await logsOf(tester, repo, plants[1].id), hasLength(1));
      expect(find.text('水やり:今日'), findsOneWidget);
    });

    testWidgets('続けて長押しすると、その分だけ記録され、メッセージは新しいものに置き換わる', (tester) async {
      final (repo, plants) = await pumpHome(tester, [
        const PlantInput(name: 'モンステラ'),
        const PlantInput(name: 'パキラ'),
      ]);
      await tester.longPress(find.text('モンステラ'));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('パキラ'));
      await tester.pumpAndSettle();
      expect(find.text('「パキラ」に水やりを記録しました'), findsOneWidget);
      expect(find.text('「モンステラ」に水やりを記録しました'), findsNothing);
      expect(await logsOf(tester, repo, plants[0].id), hasLength(1));
      expect(await logsOf(tester, repo, plants[1].id), hasLength(1));
    });
  });

  group('前回の水やりからの日数', () {
    testWidgets('ホームに「水やり:3日前」と出る。水やりの記録がなければ出ない', (tester) async {
      final (repo, plants) = await pumpHome(tester, [
        const PlantInput(name: 'モンステラ'),
        const PlantInput(name: 'パキラ'),
      ]);
      await repo.addLog(plants[0].id, water(daysAgo(3)));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('water-line-${plants[0].id}')), findsOneWidget);
      expect(find.text('水やり:3日前'), findsOneWidget);
      expect(find.byKey(Key('water-line-${plants[1].id}')), findsNothing);
    });

    testWidgets('複数あるときは、いちばん新しい水やりで数える。水やり以外の記録は数えない', (tester) async {
      final (repo, plants) = await pumpHome(tester, [const PlantInput(name: 'モンステラ')]);
      final id = plants.single.id;
      await repo.addLog(id, water(daysAgo(10)));
      await repo.addLog(id, water(daysAgo(2)));
      await repo.addLog(id, PlantLogInput(type: PlantLogType.fertilize, occurredAt: daysAgo(0)));
      await tester.pumpAndSettle();
      expect(find.text('水やり:2日前'), findsOneWidget);
    });

    testWidgets('記録の日付を直すと、日数も追随する', (tester) async {
      final (repo, plants) = await pumpHome(tester, [const PlantInput(name: 'モンステラ')]);
      final log = await repo.addLog(plants.single.id, water(daysAgo(5)));
      await tester.pumpAndSettle();
      expect(find.text('水やり:5日前'), findsOneWidget);
      await repo.updateLog(plants.single.id, log.id, occurredAt: daysAgo(1));
      await tester.pumpAndSettle();
      expect(find.text('水やり:1日前'), findsOneWidget);
      await repo.deleteLog(plants.single.id, log.id);
      await tester.pumpAndSettle();
      expect(find.byKey(Key('water-line-${plants.single.id}')), findsNothing);
    });

    testWidgets('詳細にも、「前回の水やり:3日前(日付)」が出る。記録がなければ出ない', (tester) async {
      final (repo, plants) = await pumpHome(tester, [const PlantInput(name: 'モンステラ')]);
      await tester.tap(find.text('モンステラ'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('last-water')), findsNothing);

      final at = daysAgo(3);
      await repo.addLog(plants.single.id, water(at));
      await tester.pumpAndSettle();
      expect(find.text('前回の水やり:3日前(${formatDate(at)})'), findsOneWidget);
    });

    testWidgets('詳細で「水をやった」を押すと、ホームに戻ったとき「水やり:今日」になっている', (tester) async {
      await pumpHome(tester, [const PlantInput(name: 'モンステラ')]);
      await tester.tap(find.text('モンステラ'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('log-water')));
      await tester.pumpAndSettle();
      expect(find.text('前回の水やり:今日(${formatDate(DateTime.now())})'), findsOneWidget);
      await tester.tap(find.byTooltip('戻る'));
      await tester.pumpAndSettle();
      expect(find.text('水やり:今日'), findsOneWidget);
    });
  });

  group('ホームの健康状態の表示', () {
    testWidgets('「初期」のときは出さない。変えると、ホームに「健康状態:不調」と出る', (tester) async {
      final (repo, plants) = await pumpHome(tester, [const PlantInput(name: 'モンステラ')]);
      expect(find.byKey(Key('health-chip-${plants.single.id}')), findsNothing);

      await repo.changeHealth(plants.single.id, PlantHealth.bad);
      await tester.pumpAndSettle();
      expect(find.text('健康状態:不調'), findsOneWidget);

      await repo.changeHealth(plants.single.id, PlantHealth.recovering);
      await tester.pumpAndSettle();
      expect(find.text('健康状態:不調'), findsNothing);
      expect(find.text('健康状態:復活中'), findsOneWidget);
    });

    testWidgets('タグと並べて出る(タグの表示は変わらない)', (tester) async {
      final (repo, plants) = await pumpHome(tester, [
        const PlantInput(name: 'モンステラ', tags: {PlantTag.seedling}),
      ]);
      await repo.changeHealth(plants.single.id, PlantHealth.watch);
      await tester.pumpAndSettle();
      expect(find.text('健康状態:要観察'), findsOneWidget);
      expect(find.text('実生'), findsOneWidget);
    });
  });
}
