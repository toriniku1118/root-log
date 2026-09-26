import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rootlog/app.dart';
import 'package:rootlog/data/plant_repository.dart';
import 'package:rootlog/domain/plant.dart';
import 'package:rootlog/domain/plant_genre.dart';
import 'package:rootlog/domain/plant_health.dart';
import 'package:rootlog/domain/plant_input.dart';
import 'package:rootlog/domain/plant_log.dart';
import 'package:rootlog/domain/plant_stage.dart';
import 'package:rootlog/features/plants/story.dart';
import 'package:rootlog/providers.dart';

final _monstera = PlantInput(
  name: 'モンステラ',
  genres: const {PlantGenre.aroid},
  variety: 'アルボ',
  acquiredAt: DateTime(2026, 5, 1),
  locationName: '窓辺',
  potSize: '5号',
);

/// 株のあるホームを開き、その株の詳細を開く。
Future<(InMemoryPlantRepository, Plant)> pumpDetail(WidgetTester tester, {PlantInput? plant}) async {
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final repo = InMemoryPlantRepository();
  final input = plant ?? _monstera;
  final added = await repo.add(input);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [plantRepositoryProvider.overrideWithValue(repo)],
      child: const RootLogApp(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(input.name));
  await tester.pumpAndSettle();
  return (repo, added);
}

Future<List<PlantLog>> logsOf(WidgetTester tester, PlantRepository repo, String plantId) async =>
    (await tester.runAsync(() => repo.watchLogs(plantId).first))!;

Future<Plant> plantOf(WidgetTester tester, PlantRepository repo) async =>
    (await tester.runAsync(() => repo.watchAll().first))!.single;

String today() => formatDate(DateTime.now());

Future<void> tapKey(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

Future<void> saveDialog(WidgetTester tester) => tapKey(tester, 'log-save');

Finder get noteField => find.byKey(const Key('log-dialog-note'));

void main() {
  group('表示', () {
    testWidgets('株の情報が出る(名前・ジャンル・品種・置き場所・鉢・入手日)。記録がなければ案内が出る', (tester) async {
      await pumpDetail(tester);
      expect(find.text('モンステラ'), findsOneWidget); // 画面のタイトル
      expect(find.text('アロイド・アルボ'), findsOneWidget);
      expect(find.text('窓辺・5号・入手日 2026/05/01'), findsOneWidget);
      expect(find.text('まだ記録がありません。上のボタンから記録できます。'), findsOneWidget);
      expect(find.byKey(const Key('health-line')), findsNothing); // 初期のときは出さない
    });

    testWidgets('記録ボタンが並ぶ', (tester) async {
      await pumpDetail(tester);
      for (final label in ['水をやった', '植え替え', '肥料', '剪定', 'メモ', '段階 ▼', '健康状態 ▼', '編集']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('入手日・置き場所などがなければ、その行は出ない', (tester) async {
      await pumpDetail(tester, plant: const PlantInput(name: 'パキラ'));
      expect(find.text('観葉植物全般'), findsOneWidget);
      expect(find.textContaining('入手日'), findsNothing);
    });
  });

  group('水やり(1タップ)', () {
    testWidgets('1タップで、今日の日付の「水やり」が時系列に出る', (tester) async {
      final (repo, plant) = await pumpDetail(tester);
      await tapKey(tester, 'log-water');
      expect(find.text('水やりを記録しました'), findsOneWidget);
      expect(find.text('── ${today()} ──'), findsOneWidget);
      expect(find.text('水やり'), findsOneWidget);
      final logs = await logsOf(tester, repo, plant.id);
      expect(logs.single.type, PlantLogType.water);
      expect(find.text('まだ記録がありません。上のボタンから記録できます。'), findsNothing);
    });

    testWidgets('続けて押すと、その分だけ記録される', (tester) async {
      final (repo, plant) = await pumpDetail(tester);
      await tapKey(tester, 'log-water');
      await tapKey(tester, 'log-water');
      expect(await logsOf(tester, repo, plant.id), hasLength(2));
      expect(find.text('水やり'), findsNWidgets(2));
    });
  });

  group('記録の追加(植え替え・肥料・剪定・メモ)', () {
    testWidgets('植え替え:メモを添えて記録する(日時は今)', (tester) async {
      final (repo, plant) = await pumpDetail(tester);
      await tapKey(tester, 'log-repot');
      expect(find.text('植え替えを記録'), findsOneWidget);
      expect(find.text('日時:今'), findsOneWidget);
      await tester.enterText(noteField, '6号鉢に変えた');
      await saveDialog(tester);

      expect(find.text('植え替えを記録'), findsNothing); // ダイアログが閉じる
      expect(find.text('植え替え'), findsNWidgets(2)); // ボタンと、時系列の1件
      expect(find.text('6号鉢に変えた'), findsOneWidget);
      final log = (await logsOf(tester, repo, plant.id)).single;
      expect(log.type, PlantLogType.repot);
      expect(log.note, '6号鉢に変えた');
    });

    testWidgets('肥料・剪定:メモなしでも記録できる', (tester) async {
      final (repo, plant) = await pumpDetail(tester);
      await tapKey(tester, 'log-fertilize');
      await saveDialog(tester);
      await tapKey(tester, 'log-prune');
      await saveDialog(tester);
      final types = (await logsOf(tester, repo, plant.id)).map((l) => l.type).toSet();
      expect(types, {PlantLogType.fertilize, PlantLogType.prune});
    });

    testWidgets('メモの記録は、メモが必須(空だとエラーで閉じない)。入れると記録できる', (tester) async {
      final (repo, plant) = await pumpDetail(tester);
      await tapKey(tester, 'log-note');
      await saveDialog(tester);
      expect(find.text('メモを入力してください'), findsOneWidget);
      expect(find.text('メモを記録'), findsOneWidget); // ダイアログが残る
      expect(await logsOf(tester, repo, plant.id), isEmpty);

      await tester.enterText(noteField, '新しい葉が出た');
      await tester.pumpAndSettle();
      expect(find.text('メモを入力してください'), findsNothing);
      await saveDialog(tester);
      expect((await logsOf(tester, repo, plant.id)).single.note, '新しい葉が出た');
    });

    testWidgets('メモは500文字まで(501文字はエラー)', (tester) async {
      final (repo, plant) = await pumpDetail(tester);
      await tapKey(tester, 'log-fertilize');
      await tester.enterText(noteField, List.filled(501, 'あ').join());
      await saveDialog(tester);
      expect(find.text('メモは500文字以内で入力してください'), findsOneWidget);
      expect(await logsOf(tester, repo, plant.id), isEmpty);
      await tester.enterText(noteField, List.filled(500, 'あ').join());
      await saveDialog(tester);
      expect(await logsOf(tester, repo, plant.id), hasLength(1));
    });

    testWidgets('キャンセルすると、記録されない', (tester) async {
      final (repo, plant) = await pumpDetail(tester);
      await tapKey(tester, 'log-repot');
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();
      expect(await logsOf(tester, repo, plant.id), isEmpty);
    });

    testWidgets('日付を選ぶ:今日まで(未来は選べない)。過去の日を選ぶと、その日の記録になる', (tester) async {
      final (repo, plant) = await pumpDetail(tester);
      await tapKey(tester, 'log-fertilize');
      await tapKey(tester, 'log-pick-date');
      final now = DateTime.now();
      final todayDate = DateTime(now.year, now.month, now.day);
      expect(tester.widget<CalendarDatePicker>(find.byType(CalendarDatePicker)).lastDate, todayDate);

      await tester.tap(find.byTooltip('前月'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      final expected = DateTime(todayDate.year, todayDate.month - 1, 15);
      expect(find.text('日時:${formatDate(expected)}'), findsOneWidget);

      await saveDialog(tester);
      final log = (await logsOf(tester, repo, plant.id)).single;
      expect(DateTime(log.occurredAt.year, log.occurredAt.month, log.occurredAt.day), expected);
      expect(find.text('── ${formatDate(expected)} ──'), findsOneWidget);
    });
  });

  group('段階', () {
    testWidgets('メニューから8つの段階を選べる。選ぶと記録され、「段階:新芽」と出る', (tester) async {
      final (repo, plant) = await pumpDetail(tester);
      await tapKey(tester, 'stage-menu');
      for (final s in PlantStage.values) {
        expect(find.byKey(Key('stage-${s.id}')), findsOneWidget, reason: s.label);
      }
      await tester.tap(find.byKey(const Key('stage-new_leaf')));
      await tester.pumpAndSettle();
      expect(find.text('段階「新芽」を記録'), findsOneWidget);
      await tester.enterText(noteField, '新しい葉が出た');
      await saveDialog(tester);

      expect(find.text('段階:新芽'), findsOneWidget);
      final log = (await logsOf(tester, repo, plant.id)).single;
      expect(log.type, PlantLogType.stage);
      expect(log.stage, PlantStage.newLeaf);
    });

    testWidgets('失敗(枯死)も残せる', (tester) async {
      final (repo, plant) = await pumpDetail(tester);
      await tapKey(tester, 'stage-menu');
      await tester.tap(find.byKey(const Key('stage-died')));
      await tester.pumpAndSettle();
      await saveDialog(tester);
      expect(find.text('段階:枯死'), findsOneWidget);
      expect((await logsOf(tester, repo, plant.id)).single.stage, PlantStage.died);
    });
  });

  group('健康状態', () {
    testWidgets('メニューには5つ出る。いまの状態は選べない', (tester) async {
      await pumpDetail(tester);
      await tapKey(tester, 'health-menu');
      for (final h in PlantHealth.values) {
        expect(find.byKey(Key('health-${h.id}')), findsOneWidget, reason: h.label);
      }
      expect(find.text('初期(いま)'), findsOneWidget);
      // いまの状態を選んでも、何も起きない
      await tester.tap(find.byKey(const Key('health-initial')), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.textContaining('健康状態を「'), findsNothing);
    });

    testWidgets('変えると、株の状態が変わり、履歴に「初期 → 不調」と出る。詳細に「健康状態:不調(日付〜)」と出る', (tester) async {
      final (repo, plant) = await pumpDetail(tester);
      await tapKey(tester, 'health-menu');
      await tester.tap(find.byKey(const Key('health-bad')));
      await tester.pumpAndSettle();
      expect(find.text('健康状態を「不調」にする'), findsOneWidget);
      await tester.enterText(noteField, '葉がしおれてきた');
      await saveDialog(tester);

      expect(find.text('健康状態を「不調」にしました'), findsOneWidget);
      expect(find.text('健康状態:不調(${today()}〜)'), findsOneWidget);
      expect(find.text('健康状態:初期 → 不調'), findsOneWidget);
      expect(find.text('葉がしおれてきた'), findsOneWidget);
      expect((await plantOf(tester, repo)).health, PlantHealth.bad);
      final log = (await logsOf(tester, repo, plant.id)).single;
      expect(log.type, PlantLogType.health);
      expect(log.health, PlantHealth.bad);
    });

    testWidgets('続けて変えると、履歴で前の状態がたどれる(要観察 → 不調 → 復活中)', (tester) async {
      await pumpDetail(tester);
      for (final (key, label) in [('health-watch', '要観察'), ('health-bad', '不調'), ('health-recovering', '復活中')]) {
        await tapKey(tester, 'health-menu');
        await tester.tap(find.byKey(Key(key)));
        await tester.pumpAndSettle();
        expect(find.text('健康状態を「$label」にする'), findsOneWidget);
        await saveDialog(tester);
      }
      expect(find.text('健康状態:初期 → 要観察'), findsOneWidget);
      expect(find.text('健康状態:要観察 → 不調'), findsOneWidget);
      expect(find.text('健康状態:不調 → 復活中'), findsOneWidget);
      expect(find.text('健康状態:復活中(${today()}〜)'), findsOneWidget);
    });

    testWidgets('ホームの株の表示も、変えた状態に追随する(詳細から戻っても株が残っている)', (tester) async {
      final (repo, _) = await pumpDetail(tester);
      await tapKey(tester, 'health-menu');
      await tester.tap(find.byKey(const Key('health-good')));
      await tester.pumpAndSettle();
      await saveDialog(tester);
      expect((await plantOf(tester, repo)).health, PlantHealth.good);
      await tester.tap(find.byTooltip('戻る'));
      await tester.pumpAndSettle();
      expect(find.text('モンステラ'), findsOneWidget);
    });
  });

  group('記録の編集・削除', () {
    testWidgets('記録をタップすると、メモと日時を直せる。種類は変わらない', (tester) async {
      final (repo, plant) = await pumpDetail(tester);
      await tapKey(tester, 'log-fertilize');
      await tester.enterText(noteField, '液肥');
      await saveDialog(tester);
      final id = (await logsOf(tester, repo, plant.id)).single.id;

      await tester.tap(find.byKey(Key('entry-$id')));
      await tester.pumpAndSettle();
      expect(find.text('肥料の記録を直す'), findsOneWidget);
      expect(tester.widget<TextField>(noteField).controller!.text, '液肥');
      await tester.enterText(noteField, '固形肥料');
      await saveDialog(tester);

      expect(find.text('記録を直しました'), findsOneWidget);
      expect(find.text('固形肥料'), findsOneWidget);
      final log = (await logsOf(tester, repo, plant.id)).single;
      expect(log.id, id);
      expect(log.type, PlantLogType.fertilize);
      expect(log.note, '固形肥料');
    });

    testWidgets('メモの記録は、直すときもメモが必須', (tester) async {
      final (repo, plant) = await pumpDetail(tester);
      await tapKey(tester, 'log-note');
      await tester.enterText(noteField, 'つぼみ');
      await saveDialog(tester);
      final id = (await logsOf(tester, repo, plant.id)).single.id;
      await tester.tap(find.byKey(Key('entry-$id')));
      await tester.pumpAndSettle();
      await tester.enterText(noteField, '');
      await saveDialog(tester);
      expect(find.text('メモを入力してください'), findsOneWidget);
      expect((await logsOf(tester, repo, plant.id)).single.note, 'つぼみ');
    });

    testWidgets('削除:確認が出る。「やめる」なら残り、「削除する」で消える', (tester) async {
      final (repo, plant) = await pumpDetail(tester);
      await tapKey(tester, 'log-water');
      final id = (await logsOf(tester, repo, plant.id)).single.id;

      await tester.tap(find.byKey(Key('entry-$id')));
      await tester.pumpAndSettle();
      await tapKey(tester, 'log-delete');
      expect(find.text('記録を削除しますか?'), findsOneWidget);
      await tester.tap(find.text('やめる'));
      await tester.pumpAndSettle();
      expect(await logsOf(tester, repo, plant.id), hasLength(1));

      await tapKey(tester, 'log-delete');
      await tester.tap(find.text('削除する'));
      await tester.pumpAndSettle();
      expect(find.text('記録を削除しました'), findsOneWidget);
      expect(await logsOf(tester, repo, plant.id), isEmpty);
      expect(find.text('まだ記録がありません。上のボタンから記録できます。'), findsOneWidget);
    });

    testWidgets('健康状態の記録を削除しても、株のいまの状態は変わらない(履歴の記録だけが消える)', (tester) async {
      final (repo, plant) = await pumpDetail(tester);
      await tapKey(tester, 'health-menu');
      await tester.tap(find.byKey(const Key('health-bad')));
      await tester.pumpAndSettle();
      await saveDialog(tester);
      final id = (await logsOf(tester, repo, plant.id)).single.id;
      await tester.tap(find.byKey(Key('entry-$id')));
      await tester.pumpAndSettle();
      await tapKey(tester, 'log-delete');
      await tester.tap(find.text('削除する'));
      await tester.pumpAndSettle();
      expect((await plantOf(tester, repo)).health, PlantHealth.bad);
      expect(find.text('健康状態:不調'), findsOneWidget); // 日付は出ない(記録が消えたため)
    });
  });

  group('画面の行き来', () {
    testWidgets('編集ボタンで編集画面が開き、保存すると詳細に戻って、名前が変わっている', (tester) async {
      final (repo, _) = await pumpDetail(tester);
      await tapKey(tester, 'edit');
      expect(find.text('株を編集'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('field-name')), 'モンステラ アルボ');
      await tester.pump();
      await tester.tap(find.byKey(const Key('save')));
      await tester.pumpAndSettle();
      expect(find.text('更新しました'), findsOneWidget);
      expect(find.byKey(const Key('edit')), findsOneWidget); // 詳細に戻っている
      expect(find.text('モンステラ アルボ'), findsOneWidget);
      expect((await plantOf(tester, repo)).name, 'モンステラ アルボ');
    });

    testWidgets('編集画面で削除すると、ホームまで戻る(「株が見つかりません」は出ない)', (tester) async {
      await pumpDetail(tester);
      await tapKey(tester, 'edit');
      await tapKey(tester, 'delete');
      await tester.tap(find.text('削除する'));
      await tester.pumpAndSettle();
      expect(find.text('削除しました'), findsOneWidget);
      expect(find.text('株が見つかりません'), findsNothing);
      expect(find.byKey(const Key('edit')), findsNothing);
      expect(find.text('まだ株がありません'), findsOneWidget);
    });

    testWidgets('別の場所で株が消えたら、詳細は「株が見つかりません」を出して、ホームに戻る', (tester) async {
      final (repo, plant) = await pumpDetail(tester);
      await tester.runAsync(() => repo.delete(plant.id));
      await tester.pumpAndSettle();
      expect(find.text('株が見つかりません'), findsOneWidget);
      expect(find.byKey(const Key('edit')), findsNothing);
      expect(find.text('まだ株がありません'), findsOneWidget);
    });

    testWidgets('戻ると、ホームに戻る', (tester) async {
      await pumpDetail(tester);
      await tester.tap(find.byTooltip('戻る'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('edit')), findsNothing);
      expect(find.text('窓辺'), findsOneWidget); // ホームの置き場所の見出し
    });
  });
}
