import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rootlog/app.dart';
import 'package:rootlog/data/plant_repository.dart';
import 'package:rootlog/domain/plant.dart';
import 'package:rootlog/domain/plant_input.dart';
import 'package:rootlog/domain/plant_log.dart';
import 'package:rootlog/providers.dart';

/// 共有設定の保存が「株がない」で失敗する保存先(保存しようとしたら株がなくなっていた、を再現する)。
class _MissingOnSaveRepository extends InMemoryPlantRepository {
  @override
  Future<Plant> setVisibility(String id, PlantVisibility visibility) async => throw PlantNotFoundException(id);
}

/// 株のある詳細を開く。
Future<(InMemoryPlantRepository, Plant)> pumpDetail(WidgetTester tester, {InMemoryPlantRepository? repository}) async {
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final repo = repository ?? InMemoryPlantRepository();
  final plant = await repo.add(const PlantInput(name: 'モンステラ', variety: 'アルボ', source: '〇〇植物店', locationName: '窓辺'));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [plantRepositoryProvider.overrideWithValue(repo)],
      child: const RootLogApp(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('モンステラ'));
  await tester.pumpAndSettle();
  return (repo, plant);
}

Future<void> openVisibility(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('open-visibility')));
  await tester.pumpAndSettle();
}

Future<Plant> plantOf(WidgetTester tester, PlantRepository repo) async =>
    (await tester.runAsync(() => repo.watchAll().first))!.single;

Set<T> selected<T>(WidgetTester tester, String key) => tester.widget<SegmentedButton<T>>(find.byKey(Key(key))).selected;

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

Iterable<String> visibleLines(WidgetTester tester) =>
    tester.widgetList<Text>(find.byKey(const Key('visible-line'))).map((t) => t.data!);

void main() {
  group('入口と初期の表示', () {
    testWidgets('詳細に「共有:公開(写真のみ)」が出て、「共有設定」で画面が開く', (tester) async {
      await pumpDetail(tester);
      expect(find.text('共有:公開(写真のみ)'), findsOneWidget);
      await openVisibility(tester);
      expect(find.text('共有設定  モンステラ'), findsOneWidget);
      expect(find.text('公開する範囲を選びます。'), findsOneWidget);
    });

    testWidgets('初期は、公開・写真のみが選ばれている。誰に何が見えるかが出る', (tester) async {
      await pumpDetail(tester);
      await openVisibility(tester);
      expect(selected<bool>(tester, 'public-toggle'), {true});
      expect(selected<PlantScope>(tester, 'scope-toggle'), {PlantScope.photos});
      expect(visibleLines(tester), ['・名前・ジャンル・品種・タグと、写真が、ログインしている人に見えます。']);
      expect(find.text('・置き場所・鉢の号数・購入価格・健康状態・メモの中身は、どの範囲でも見えません。'), findsOneWidget);
    });

    testWidgets('説明の文(初期の公開・公開のよさ・ステップ3の注記)が出る', (tester) async {
      await pumpDetail(tester);
      await openVisibility(tester);
      expect(find.text('初期は、写真だけが公開されます(公開の説明を確認したあとから他の人に見えます)。'), findsOneWidget);
      expect(find.textContaining('交換・売買・レスキューのときに、相手があなたの記録を見て安心できます'), findsOneWidget);
      expect(find.text('※ 公開はステップ3から使えるようになります。今は設定だけ保存されます。'), findsOneWidget);
    });
  });

  group('選ぶと説明が変わる', () {
    testWidgets('範囲を広げると、見えるものが増える(履歴まで → 入手先まで)', (tester) async {
      await pumpDetail(tester);
      await openVisibility(tester);
      await tapText(tester, '履歴まで');
      expect(visibleLines(tester).length, 2);
      expect(visibleLines(tester).last, contains('記録の種類と日付'));
      await tapText(tester, '入手先まで');
      expect(visibleLines(tester).length, 3);
      expect(visibleLines(tester).last, '・入手先も見えます。');
      await tapText(tester, '写真のみ');
      expect(visibleLines(tester).length, 1);
    });

    testWidgets('非公開にすると、「自分だけ」と出る。範囲は選べなくなり、「どの範囲でも…」は出ない', (tester) async {
      await pumpDetail(tester);
      await openVisibility(tester);
      await tapText(tester, '非公開(自分だけ)');
      expect(selected<bool>(tester, 'public-toggle'), {false});
      expect(visibleLines(tester), ['・自分だけが見られます。他の人には見えません。']);
      expect(find.byKey(const Key('always-hidden')), findsNothing);
      expect(tester.widget<SegmentedButton<PlantScope>>(find.byKey(const Key('scope-toggle'))).onSelectionChanged, isNull);
      // 公開に戻すと、範囲を選べる
      await tapText(tester, '公開');
      expect(tester.widget<SegmentedButton<PlantScope>>(find.byKey(const Key('scope-toggle'))).onSelectionChanged, isNotNull);
    });
  });

  group('保存', () {
    testWidgets('保存すると、設定が変わり、詳細に戻って「共有設定を保存しました」と出る。ほかの項目は変わらない', (tester) async {
      final (repo, before) = await pumpDetail(tester);
      await openVisibility(tester);
      await tapText(tester, '履歴まで');
      await tester.tap(find.byKey(const Key('save')));
      await tester.pumpAndSettle();

      final after = await plantOf(tester, repo);
      expect(after.visibility.public, isTrue);
      expect(after.visibility.scope, PlantScope.history);
      expect(after.name, before.name);
      expect(after.source, before.source);
      expect(after.locationName, before.locationName);
      expect(after.createdAt, before.createdAt);
      expect(find.text('共有設定を保存しました'), findsOneWidget);
      expect(find.text('共有:公開(履歴まで)'), findsOneWidget); // 詳細に戻っている
    });

    testWidgets('非公開にして保存すると、詳細に「共有:非公開」と出る。開き直すと、非公開が選ばれている', (tester) async {
      final (repo, _) = await pumpDetail(tester);
      await openVisibility(tester);
      await tapText(tester, '非公開(自分だけ)');
      await tester.tap(find.byKey(const Key('save')));
      await tester.pumpAndSettle();
      expect((await plantOf(tester, repo)).visibility.public, isFalse);
      expect(find.text('共有:非公開'), findsOneWidget);

      await openVisibility(tester);
      expect(selected<bool>(tester, 'public-toggle'), {false});
    });

    testWidgets('記録には影響しない(共有設定を変えても、記録は変わらない)', (tester) async {
      final (repo, plant) = await pumpDetail(tester);
      await repo.addLog(plant.id, PlantLogInput(type: PlantLogType.water, occurredAt: DateTime.now()));
      await openVisibility(tester);
      await tapText(tester, '非公開(自分だけ)');
      await tester.tap(find.byKey(const Key('save')));
      await tester.pumpAndSettle();
      expect(await tester.runAsync(() => repo.watchLogs(plant.id).first), hasLength(1));
    });
  });

  group('戻る', () {
    testWidgets('変えていなければ、確認なしで戻る', (tester) async {
      await pumpDetail(tester);
      await openVisibility(tester);
      await tester.tap(find.byTooltip('戻る'));
      await tester.pumpAndSettle();
      expect(find.text('入力を破棄しますか?'), findsNothing);
      expect(find.byKey(const Key('open-visibility')), findsOneWidget);
    });

    testWidgets('変えていると確認が出る。「続ける」で残り、「破棄して戻る」で、元の設定のまま戻る', (tester) async {
      final (repo, _) = await pumpDetail(tester);
      await openVisibility(tester);
      await tapText(tester, '非公開(自分だけ)');
      await tester.tap(find.byTooltip('戻る'));
      await tester.pumpAndSettle();
      expect(find.text('入力を破棄しますか?'), findsOneWidget);
      await tester.tap(find.text('続ける'));
      await tester.pumpAndSettle();
      expect(selected<bool>(tester, 'public-toggle'), {false});

      await tester.tap(find.byTooltip('戻る'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('破棄して戻る'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('open-visibility')), findsOneWidget);
      expect((await plantOf(tester, repo)).visibility.public, isTrue);
    });

    testWidgets('変えたあと元に戻せば、確認は出ない', (tester) async {
      await pumpDetail(tester);
      await openVisibility(tester);
      await tapText(tester, '入手先まで');
      await tapText(tester, '写真のみ');
      await tester.tap(find.byTooltip('戻る'));
      await tester.pumpAndSettle();
      expect(find.text('入力を破棄しますか?'), findsNothing);
    });
  });

  group('株がなくなったとき', () {
    testWidgets('別の場所で株が消えたら、「株が見つかりません」と出て、ホームまで戻る', (tester) async {
      final (repo, plant) = await pumpDetail(tester);
      await openVisibility(tester);
      await tester.runAsync(() => repo.delete(plant.id));
      await tester.pumpAndSettle();
      expect(find.text('株が見つかりません'), findsOneWidget);
      expect(find.byKey(const Key('open-visibility')), findsNothing);
      expect(find.text('まだ株がありません'), findsOneWidget);
    });

    testWidgets('保存しようとしたら株がなかったとき(保存先が「ない」と答えた)は、「株が見つかりません」と出て、共有設定の画面が閉じる', (tester) async {
      await pumpDetail(tester, repository: _MissingOnSaveRepository());
      await openVisibility(tester);
      await tapText(tester, '非公開(自分だけ)');
      await tester.tap(find.byKey(const Key('save')));
      await tester.pumpAndSettle();
      expect(find.text('株が見つかりません'), findsOneWidget);
      expect(find.byKey(const Key('save')), findsNothing); // 共有設定の画面は閉じている
      // 一覧にはまだ株がある(保存先がないと答えただけ)ので、詳細は残る。実際に株が消えたときは、上のテストのとおりホームまで戻る
      expect(find.byKey(const Key('open-visibility')), findsOneWidget);
    });
  });
}
