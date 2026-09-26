import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rootlog/app.dart';
import 'package:rootlog/data/plant_repository.dart';
import 'package:rootlog/domain/plant.dart';
import 'package:rootlog/domain/plant_genre.dart';
import 'package:rootlog/domain/plant_health.dart';
import 'package:rootlog/domain/plant_input.dart';
import 'package:rootlog/domain/plant_tag.dart';
import 'package:rootlog/providers.dart';

/// 編集に使う株(全項目に値がある)。
final _monstera = PlantInput(
  name: 'モンステラ',
  genres: const {PlantGenre.aroid, PlantGenre.rare},
  variety: 'アルボ',
  acquiredAt: DateTime(2026, 5, 1),
  source: '〇〇植物店',
  locationName: 'リビング',
  potSize: '5号',
  purchasePrice: 12800,
  tags: const {PlantTag.rescue},
);

/// 株のあるホームを開く(縦に長い画面にして、スクロールなしで確かめる)。
Future<InMemoryPlantRepository> pumpHome(WidgetTester tester, List<PlantInput> plants) async {
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
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

/// ホームの株をタップして詳細を開き、「編集」で編集画面を開く。
Future<void> openEdit(WidgetTester tester, String name) async {
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('edit')));
  await tester.pumpAndSettle();
}

/// 保存先の株の一覧。ウィジェットテストの中では、実際の非同期(runAsync)で読まないと止まる。
Future<List<Plant>> plantsOf(WidgetTester tester, PlantRepository repo) async =>
    (await tester.runAsync(() => repo.watchAll().first))!;

Finder field(String key) => find.byKey(Key('field-$key'));
Finder get saveButton => find.byKey(const Key('save'));
Finder get deleteButton => find.byKey(const Key('delete'));

String textOf(WidgetTester tester, String key) => tester.widget<TextField>(field(key)).controller!.text;

void main() {
  group('編集画面を開く', () {
    testWidgets('株の詳細の「編集」で編集画面が開き、今の値が入っている', (tester) async {
      await pumpHome(tester, [_monstera]);
      await openEdit(tester, 'モンステラ');

      expect(find.text('株を編集'), findsOneWidget);
      expect(textOf(tester, 'name'), 'モンステラ');
      expect(textOf(tester, 'variety'), 'アルボ');
      expect(textOf(tester, 'source'), '〇〇植物店');
      expect(textOf(tester, 'location'), 'リビング');
      expect(textOf(tester, 'potSize'), '5号');
      expect(textOf(tester, 'price'), '12800');
      expect(find.text('2026/5/1'), findsOneWidget);
      bool checked(String key) => tester.widget<CheckboxListTile>(find.byKey(Key(key))).value ?? false;
      expect(checked('genre-aroid'), isTrue);
      expect(checked('genre-rare'), isTrue);
      expect(checked('genre-foliage'), isFalse);
      expect(checked('tag-rescue'), isTrue);
      expect(checked('tag-seedling'), isFalse);
    });

    testWidgets('編集画面には「この株を削除」がある。追加の画面にはない', (tester) async {
      await pumpHome(tester, [_monstera]);
      await openEdit(tester, 'モンステラ');
      expect(deleteButton, findsOneWidget);
      await tester.tap(find.byTooltip('戻る')); // 編集 → 詳細
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('戻る')); // 詳細 → ホーム
      await tester.pumpAndSettle();

      await tester.tap(find.text('株を追加'));
      await tester.pumpAndSettle();
      expect(find.text('株を追加'), findsOneWidget); // 画面のタイトル
      expect(deleteButton, findsNothing);
    });

    testWidgets('編集では、追加のときの公開の説明は出ない', (tester) async {
      await pumpHome(tester, [_monstera]);
      await openEdit(tester, 'モンステラ');
      expect(find.textContaining('初期設定では、この株の写真だけが公開されます'), findsNothing);
    });
  });

  group('更新', () {
    testWidgets('直して保存すると、内容が変わり、詳細に戻って「更新しました」と出る。共有設定・作成日時・健康状態は変わらない', (tester) async {
      final repo = await pumpHome(tester, [_monstera]);
      final before = (await plantsOf(tester, repo)).single;

      await openEdit(tester, 'モンステラ');
      await tester.enterText(field('name'), 'モンステラ アルボ');
      await tester.enterText(field('location'), 'ベランダ');
      await tester.enterText(field('price'), '15,000');
      await tester.tap(find.byKey(const Key('genre-rare'))); // ジャンルを外す
      await tester.tap(find.byKey(const Key('tag-seedling'))); // タグを足す
      await tester.pump();
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      final after = (await plantsOf(tester, repo)).single;
      expect(after.id, before.id);
      expect(after.name, 'モンステラ アルボ');
      expect(after.locationName, 'ベランダ');
      expect(after.purchasePrice, 15000);
      expect(after.genres, {PlantGenre.aroid});
      expect(after.tags, {PlantTag.rescue, PlantTag.seedling});
      // 変わらないもの
      expect(after.createdAt, before.createdAt);
      expect(after.visibility.public, before.visibility.public);
      expect(after.visibility.scope, before.visibility.scope);
      expect(after.health, PlantHealth.initial);
      expect(after.variety, 'アルボ');
      expect(after.source, '〇〇植物店');

      // 詳細に戻っている(変えた内容が出る)
      expect(field('name'), findsNothing);
      expect(find.text('更新しました'), findsOneWidget);
      expect(find.text('モンステラ アルボ'), findsOneWidget); // 画面のタイトル
      expect(find.text('ベランダ・5号・入手日 2026/05/01'), findsOneWidget);
    });

    testWidgets('購入価格・入手日・品種などを空にして保存できる(未設定に戻る)', (tester) async {
      final repo = await pumpHome(tester, [_monstera]);
      await openEdit(tester, 'モンステラ');
      await tester.enterText(field('price'), '');
      await tester.enterText(field('variety'), '');
      await tester.enterText(field('source'), '');
      await tester.tap(find.byKey(const Key('clear-date')));
      await tester.pump();
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      final after = (await plantsOf(tester, repo)).single;
      expect(after.purchasePrice, isNull);
      expect(after.variety, isNull);
      expect(after.source, isNull);
      expect(after.acquiredAt, isNull);
    });

    testWidgets('条件を満たさないと保存できず、エラーが出る。元の内容は変わらない', (tester) async {
      final repo = await pumpHome(tester, [_monstera]);
      await openEdit(tester, 'モンステラ');
      await tester.enterText(field('name'), '');
      await tester.enterText(field('price'), '100000000');
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(find.text('名前を入力してください'), findsOneWidget);
      expect(find.text('購入価格は99,999,999円以下で入力してください'), findsOneWidget);
      expect(find.text('株を編集'), findsOneWidget); // 画面に残る
      expect((await plantsOf(tester, repo)).single.name, 'モンステラ');
    });

    testWidgets('編集中に株がなくなっていたら、「株が見つかりません」と出てホームまで戻る', (tester) async {
      final repo = await pumpHome(tester, [_monstera]);
      final plant = (await plantsOf(tester, repo)).single;
      await openEdit(tester, 'モンステラ');
      await tester.runAsync(() => repo.delete(plant.id)); // 別の場所で削除された
      await tester.enterText(field('name'), '改名');
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(find.text('株が見つかりません'), findsOneWidget);
      expect(field('name'), findsNothing);
      expect(find.byKey(const Key('edit')), findsNothing); // 詳細も閉じている
      expect(find.text('まだ株がありません'), findsOneWidget);
    });
  });

  group('戻る', () {
    testWidgets('何も変えていなければ、確認なしで戻る', (tester) async {
      await pumpHome(tester, [_monstera]);
      await openEdit(tester, 'モンステラ');
      await tester.tap(find.byTooltip('戻る'));
      await tester.pumpAndSettle();
      expect(find.text('入力を破棄しますか?'), findsNothing);
      expect(field('name'), findsNothing);
      expect(find.byKey(const Key('edit')), findsOneWidget); // 詳細に戻っている
    });

    testWidgets('変えていると確認が出る。「続ける」で残り、「破棄して戻る」で、元の内容のまま戻る', (tester) async {
      final repo = await pumpHome(tester, [_monstera]);
      await openEdit(tester, 'モンステラ');
      await tester.enterText(field('name'), '書き換え');
      await tester.pump();
      await tester.tap(find.byTooltip('戻る'));
      await tester.pumpAndSettle();
      expect(find.text('入力を破棄しますか?'), findsOneWidget);

      await tester.tap(find.text('続ける'));
      await tester.pumpAndSettle();
      expect(textOf(tester, 'name'), '書き換え');

      await tester.tap(find.byTooltip('戻る'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('破棄して戻る'));
      await tester.pumpAndSettle();
      expect(field('name'), findsNothing);
      expect(find.byKey(const Key('edit')), findsOneWidget); // 詳細に戻っている
      expect((await plantsOf(tester, repo)).single.name, 'モンステラ');
    });

    testWidgets('変えたあと元に戻せば、確認は出ない', (tester) async {
      await pumpHome(tester, [_monstera]);
      await openEdit(tester, 'モンステラ');
      await tester.enterText(field('name'), '書き換え');
      await tester.pump();
      await tester.enterText(field('name'), 'モンステラ');
      await tester.pump();
      await tester.tap(find.byTooltip('戻る'));
      await tester.pumpAndSettle();
      expect(find.text('入力を破棄しますか?'), findsNothing);
    });
  });

  group('削除', () {
    testWidgets('確認が出る(写真・記録もあわせて消えることの説明つき)。「やめる」なら残る', (tester) async {
      final repo = await pumpHome(tester, [_monstera]);
      await openEdit(tester, 'モンステラ');
      await tester.tap(deleteButton);
      await tester.pumpAndSettle();
      expect(find.text('株を削除しますか?'), findsOneWidget);
      expect(find.text('写真・記録もあわせて消えます。元に戻せません。'), findsOneWidget);

      await tester.tap(find.text('やめる'));
      await tester.pumpAndSettle();
      expect(find.text('株を削除しますか?'), findsNothing);
      expect(field('name'), findsOneWidget); // 編集画面に残る
      expect(await plantsOf(tester, repo), hasLength(1));
    });

    testWidgets('「削除する」で株が消え、詳細も閉じてホームに戻り、「削除しました」だけが出る', (tester) async {
      final repo = await pumpHome(tester, [
        _monstera,
        const PlantInput(name: 'パキラ', locationName: '玄関'),
      ]);
      await openEdit(tester, 'モンステラ');
      await tester.tap(deleteButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('削除する'));
      await tester.pumpAndSettle();

      expect((await plantsOf(tester, repo)).map((p) => p.name), ['パキラ']);
      expect(field('name'), findsNothing);
      expect(find.byKey(const Key('edit')), findsNothing); // 詳細も閉じている
      expect(find.text('削除しました'), findsOneWidget);
      expect(find.text('株が見つかりません'), findsNothing);
      expect(find.text('モンステラ'), findsNothing);
      expect(find.text('パキラ'), findsOneWidget);
    });

    testWidgets('最後の1株を削除すると、0件の案内に戻る', (tester) async {
      await pumpHome(tester, [_monstera]);
      await openEdit(tester, 'モンステラ');
      await tester.tap(deleteButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('削除する'));
      await tester.pumpAndSettle();
      expect(find.text('まだ株がありません'), findsOneWidget);
      expect(find.text('最初の株を追加'), findsOneWidget);
    });

    testWidgets('入力を変えたあとでも、削除の確認のあと削除できる(破棄の確認は出ない)', (tester) async {
      final repo = await pumpHome(tester, [_monstera]);
      await openEdit(tester, 'モンステラ');
      await tester.enterText(field('name'), '書き換え');
      await tester.pump();
      await tester.tap(deleteButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('削除する'));
      await tester.pumpAndSettle();
      expect(find.text('入力を破棄しますか?'), findsNothing);
      expect(await plantsOf(tester, repo), isEmpty);
    });
  });
}
