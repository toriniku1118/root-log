import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rootlog/app.dart';
import 'package:rootlog/data/plant_repository.dart';
import 'package:rootlog/domain/plant_genre.dart';
import 'package:rootlog/domain/plant_input.dart';
import 'package:rootlog/domain/plant_tag.dart';
import 'package:rootlog/providers.dart';

Future<InMemoryPlantRepository> pumpApp(WidgetTester tester, {List<PlantInput> plants = const []}) async {
  final repo = InMemoryPlantRepository();
  for (final p in plants) {
    await repo.add(p);
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [plantRepositoryProvider.overrideWithValue(repo)],
      child: const RootLogApp(),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  testWidgets('株が0件のとき、案内と「最初の株を追加」だけが出る(右下のボタンは出ない)', (tester) async {
    await pumpApp(tester);
    expect(find.text('RootLog'), findsOneWidget);
    expect(find.text('まだ株がありません'), findsOneWidget);
    expect(find.text('最初の株を追加'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('「最初の株を追加」で、株を追加する画面に進む', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('最初の株を追加'));
    await tester.pumpAndSettle();
    expect(find.text('株を追加'), findsOneWidget); // 画面のタイトル
    expect(find.text('準備中'), findsOneWidget);
  });

  testWidgets('置き場所ごとに見出しが出て、置き場所は名前順・未設定は最後', (tester) async {
    await pumpApp(tester, plants: const [
      PlantInput(name: 'パキラ', locationName: 'リビング'),
      PlantInput(name: 'チタノタ', genre: PlantGenre.agave),
      PlantInput(name: 'モンステラ', locationName: 'ベランダ'),
    ]);
    final positions = ['ベランダ', 'リビング', '置き場所未設定'].map((t) => tester.getTopLeft(find.text(t)).dy).toList();
    expect(positions, orderedEquals([...positions]..sort()));
    expect(find.text('パキラ'), findsOneWidget);
    expect(find.text('チタノタ'), findsOneWidget);
    expect(find.text('モンステラ'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets('各株に、名前・ジャンル・品種・タグが出る', (tester) async {
    await pumpApp(tester, plants: const [
      PlantInput(name: 'モンステラ', variety: 'デリシオーサ', tags: {PlantTag.seedling, PlantTag.rescue}),
      PlantInput(name: 'ユーフォルビア', genre: PlantGenre.caudex),
    ]);
    expect(find.text('観葉植物全般・デリシオーサ'), findsOneWidget);
    expect(find.text('塊根'), findsOneWidget);
    expect(find.text('復活チャレンジ'), findsOneWidget);
    expect(find.text('実生'), findsOneWidget);
  });

  testWidgets('「株を追加」ボタンで、株を追加する画面に進み、戻ると一覧に戻る', (tester) async {
    await pumpApp(tester, plants: const [PlantInput(name: 'パキラ')]);
    await tester.tap(find.text('株を追加'));
    await tester.pumpAndSettle();
    expect(find.text('準備中'), findsOneWidget);
    await tester.tap(find.byTooltip('戻る'));
    await tester.pumpAndSettle();
    expect(find.text('パキラ'), findsOneWidget);
  });

  testWidgets('株が追加されると、一覧がその場で更新される', (tester) async {
    final repo = await pumpApp(tester);
    expect(find.text('まだ株がありません'), findsOneWidget);
    await repo.add(const PlantInput(name: 'ポトス', locationName: '玄関'));
    await tester.pumpAndSettle();
    expect(find.text('まだ株がありません'), findsNothing);
    expect(find.text('玄関'), findsOneWidget);
    expect(find.text('ポトス'), findsOneWidget);
  });

  testWidgets('株が多くても、見えている分だけ描画する(500株)', (tester) async {
    await pumpApp(tester, plants: [for (var i = 0; i < 500; i++) PlantInput(name: '株$i', locationName: '場所${i % 5}')]);
    expect(find.byType(Card).evaluate().length, lessThan(30));
    expect(find.text('株499'), findsNothing); // 画面外(まだ描画されていない)
  });

  testWidgets('表示は日本語で、日付選択なども日本語の設定になっている', (tester) async {
    await pumpApp(tester);
    final context = tester.element(find.byType(Scaffold).first);
    expect(Localizations.localeOf(context), const Locale('ja'));
    expect(MaterialLocalizations.of(context).cancelButtonLabel, 'キャンセル');
  });
}
