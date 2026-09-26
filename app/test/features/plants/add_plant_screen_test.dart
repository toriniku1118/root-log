import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rootlog/app.dart';
import 'package:rootlog/data/plant_repository.dart';
import 'package:rootlog/data/user_repository.dart';
import 'package:rootlog/domain/plant.dart';
import 'package:rootlog/domain/plant_genre.dart';
import 'package:rootlog/domain/plant_input.dart';
import 'package:rootlog/domain/plant_tag.dart';
import 'package:rootlog/providers.dart';

/// 追加を止めておける保存先(二重登録のテスト用)。
class _GatedRepository extends InMemoryPlantRepository {
  final gate = Completer<void>();
  int addCalls = 0;

  @override
  Future<Plant> add(PlantInput input) async {
    addCalls++;
    await gate.future;
    return super.add(input);
  }
}

Future<T> pumpAddScreen<T extends PlantRepository>(
  WidgetTester tester, {
  required T repo,
  List<PlantInput> existing = const [],
}) async {
  // 縦に長い画面を、スクロールなしで確かめられるようにする
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  for (final p in existing) {
    await repo.add(p);
  }
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
  await tester.tap(find.text(existing.isEmpty ? '最初の株を追加' : '株を追加'));
  await tester.pumpAndSettle();
  return repo;
}

/// 保存先の株の一覧を読む。ウィジェットテストの中では、実際の非同期(runAsync)で読まないと止まる。
Future<List<Plant>> plantsOf(WidgetTester tester, PlantRepository repo) async =>
    (await tester.runAsync(() => repo.watchAll().first))!;

Finder field(String key) => find.byKey(Key('field-$key'));
Finder genre(String id) => find.byKey(Key('genre-$id'));
Finder get saveButton => find.byKey(const Key('save'));

Future<void> save(WidgetTester tester) async {
  await tester.tap(saveButton);
  await tester.pumpAndSettle();
}

String chars(int n) => List.filled(n, 'あ').join();

bool isChecked(WidgetTester tester, Finder finder) => tester.widget<CheckboxListTile>(finder).value ?? false;

void main() {
  group('表示', () {
    testWidgets('初期公開(写真のみ)であることと、入手先・置き場所・購入価格は公開されないことを表示する', (tester) async {
      await pumpAddScreen(tester, repo: InMemoryPlantRepository());
      expect(find.textContaining('初期設定では、この株の写真だけが公開されます'), findsOneWidget);
      expect(find.textContaining('入手先・置き場所・購入価格は公開されません'), findsOneWidget);
      expect(find.text('100文字まで。非公開です(自分だけが見られます)'), findsOneWidget);
      expect(find.text('自分だけが見られます。公開されません'), findsOneWidget);
      // 共有設定の入力欄は、この画面には出さない(SCR-09)
      expect(find.byType(Switch), findsNothing);
    });

    testWidgets('ジャンルは8つ(実生は出ない)。初期は観葉植物全般が選択済み。例つきで表示する', (tester) async {
      await pumpAddScreen(tester, repo: InMemoryPlantRepository());
      expect(find.byWidgetPredicate((w) => w is CheckboxListTile && (w.key as ValueKey?)?.value.toString().startsWith('genre-') == true),
          findsNWidgets(8));
      expect(genre('seedling'), findsNothing);
      expect(isChecked(tester, genre('foliage')), isTrue);
      expect(isChecked(tester, genre('caudex')), isFalse);
      expect(find.text('観葉植物全般(パキラ・ゴムの木・ガジュマル・サンスベリア等)'), findsOneWidget);
      expect(find.text('アロイド(モンステラ・ポトス・アンスリウム・アロカシア等)'), findsOneWidget);
    });

    testWidgets('タグは復活チャレンジと実生', (tester) async {
      await pumpAddScreen(tester, repo: InMemoryPlantRepository());
      expect(find.text('復活チャレンジ'), findsOneWidget);
      expect(find.text('実生'), findsOneWidget);
    });
  });

  group('入力の検証', () {
    testWidgets('名前が空だと保存できず、エラーが出る', (tester) async {
      final repo = InMemoryPlantRepository();
      await pumpAddScreen(tester, repo: repo);
      await save(tester);
      expect(find.text('名前を入力してください'), findsOneWidget);
      expect(find.text('株を追加'), findsOneWidget); // 画面に残る
      expect(await plantsOf(tester, repo), isEmpty);
    });

    testWidgets('名前は50文字まで。51文字はエラー、50文字は保存できる', (tester) async {
      final repo = InMemoryPlantRepository();
      await pumpAddScreen(tester, repo: repo);
      await tester.enterText(field('name'), chars(51));
      await save(tester);
      expect(find.text('名前は50文字以内で入力してください'), findsOneWidget);
      expect(await plantsOf(tester, repo), isEmpty);

      await tester.enterText(field('name'), chars(50));
      await save(tester);
      expect((await plantsOf(tester, repo)).single.name, chars(50));
    });

    testWidgets('エラーは、その項目を直すと消える', (tester) async {
      await pumpAddScreen(tester, repo: InMemoryPlantRepository());
      await save(tester);
      expect(find.text('名前を入力してください'), findsOneWidget);
      await tester.enterText(field('name'), 'パキラ');
      await tester.pumpAndSettle(); // エラー文言は、消えるアニメーションのあと見えなくなる
      expect(find.text('名前を入力してください'), findsNothing);
    });

    testWidgets('ジャンルは1〜3個。0個・4個はエラー、3個までは選べる', (tester) async {
      final repo = InMemoryPlantRepository();
      await pumpAddScreen(tester, repo: repo);
      await tester.enterText(field('name'), 'モンステラ');

      await tester.tap(genre('foliage')); // 0個にする
      await tester.pump();
      await save(tester);
      expect(find.text('ジャンルを1つ以上選んでください'), findsOneWidget);

      for (final id in ['caudex', 'agave', 'aroid', 'rare']) {
        await tester.tap(genre(id)); // 4個にする
      }
      await tester.pump();
      await save(tester);
      expect(find.text('ジャンルは3つまで選べます'), findsOneWidget);
      expect(await plantsOf(tester, repo), isEmpty);

      await tester.tap(genre('caudex')); // 3個にする
      await tester.pump();
      await save(tester);
      expect((await plantsOf(tester, repo)).single.genres, {PlantGenre.agave, PlantGenre.aroid, PlantGenre.rare});
    });

    testWidgets('購入価格:空欄は保存できる。整数でない・範囲外はエラー', (tester) async {
      final repo = InMemoryPlantRepository();
      await pumpAddScreen(tester, repo: repo);
      await tester.enterText(field('name'), 'パキラ');

      for (final (text, message) in [
        ('abc', '購入価格は0以上の整数で入力してください'),
        ('1500.5', '購入価格は0以上の整数で入力してください'),
        ('-5', '購入価格は0以上の整数で入力してください'),
        ('100000000', '購入価格は99,999,999円以下で入力してください'),
      ]) {
        await tester.enterText(field('price'), text);
        await save(tester);
        expect(find.text(message), findsOneWidget, reason: '入力: $text');
      }
      expect(await plantsOf(tester, repo), isEmpty);

      await tester.enterText(field('price'), '');
      await save(tester);
      expect((await plantsOf(tester, repo)).single.purchasePrice, isNull);
    });

    testWidgets('購入価格:カンマ・全角の数字も受け付ける。上限ちょうどは保存できる', (tester) async {
      final repo = InMemoryPlantRepository();
      await pumpAddScreen(tester, repo: repo);
      await tester.enterText(field('name'), 'パキラ');
      await tester.enterText(field('price'), '12,800');
      await save(tester);
      expect((await plantsOf(tester, repo)).single.purchasePrice, 12800);
    });

    testWidgets('購入価格:全角の数字は半角として保存される', (tester) async {
      final repo = InMemoryPlantRepository();
      await pumpAddScreen(tester, repo: repo);
      await tester.enterText(field('name'), 'パキラ');
      await tester.enterText(field('price'), '９９９９９９９９');
      await save(tester);
      expect((await plantsOf(tester, repo)).single.purchasePrice, 99999999);
    });
  });

  group('入手日', () {
    testWidgets('日付の選択は今日まで(未来の日付は選べない)。選ぶと表示され、消せる', (tester) async {
      await pumpAddScreen(tester, repo: InMemoryPlantRepository());
      expect(find.text('未設定'), findsOneWidget);

      await tester.tap(find.byKey(const Key('pick-date')));
      await tester.pumpAndSettle();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      expect(tester.widget<CalendarDatePicker>(find.byType(CalendarDatePicker)).lastDate, today);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('${today.year}/${today.month}/${today.day}'), findsOneWidget);

      await tester.tap(find.byKey(const Key('clear-date')));
      await tester.pump();
      expect(find.text('未設定'), findsOneWidget);
    });
  });

  group('保存', () {
    testWidgets('保存すると、初期公開(写真のみ)の株が追加され、ホームに戻って「追加しました」と一覧に出る', (tester) async {
      final repo = InMemoryPlantRepository();
      await pumpAddScreen(tester, repo: repo);
      await tester.enterText(field('name'), 'モンステラ アルボ');
      await tester.tap(genre('aroid'));
      await tester.tap(genre('rare'));
      await tester.enterText(field('variety'), 'アルボ');
      await tester.enterText(field('source'), '〇〇植物店');
      await tester.enterText(field('location'), 'リビング');
      await tester.enterText(field('potSize'), '5号');
      await tester.enterText(field('price'), '12800');
      await tester.tap(find.byKey(const Key('tag-rescue')));
      await tester.pump();
      await save(tester);

      final plant = (await plantsOf(tester, repo)).single;
      expect(plant.name, 'モンステラ アルボ');
      expect(plant.genres, {PlantGenre.foliage, PlantGenre.aroid, PlantGenre.rare});
      expect(plant.variety, 'アルボ');
      expect(plant.source, '〇〇植物店');
      expect(plant.locationName, 'リビング');
      expect(plant.potSize, '5号');
      expect(plant.purchasePrice, 12800);
      expect(plant.tags, {PlantTag.rescue});
      expect(plant.visibility.public, isTrue); // 初期公開(オプトアウト)
      expect(plant.visibility.scope, PlantScope.photos); // 範囲は写真のみ

      // ホームに戻っている
      expect(field('name'), findsNothing);
      expect(find.text('追加しました'), findsOneWidget);
      expect(find.text('リビング'), findsOneWidget); // 置き場所の見出し
      expect(find.text('モンステラ アルボ'), findsOneWidget);
    });

    testWidgets('保存中に何度押しても、1件だけ追加される', (tester) async {
      final repo = _GatedRepository();
      await pumpAddScreen(tester, repo: repo);
      await tester.enterText(field('name'), 'パキラ');
      await tester.tap(saveButton);
      await tester.pump();
      // 保存中はボタンを押せない
      expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);
      await tester.tap(saveButton, warnIfMissed: false);
      await tester.pump();
      expect(repo.addCalls, 1);

      repo.gate.complete();
      await tester.pumpAndSettle();
      expect(repo.addCalls, 1);
      expect(await plantsOf(tester, repo), hasLength(1));
    });
  });

  group('置き場所の候補', () {
    testWidgets('すでに使った置き場所から選べる', (tester) async {
      await pumpAddScreen(
        tester,
        repo: InMemoryPlantRepository(),
        existing: const [
          PlantInput(name: 'a', locationName: 'リビング'),
          PlantInput(name: 'b', locationName: 'ベランダ'),
          PlantInput(name: 'c', locationName: 'リビング'),
        ],
      );
      expect(find.byKey(const Key('location-リビング')), findsOneWidget);
      expect(find.byKey(const Key('location-ベランダ')), findsOneWidget);
      await tester.tap(find.byKey(const Key('location-ベランダ')));
      await tester.pump();
      expect(tester.widget<TextField>(field('location')).controller!.text, 'ベランダ');
    });
  });

  group('戻る', () {
    testWidgets('何も入力していなければ、確認なしで戻る', (tester) async {
      await pumpAddScreen(tester, repo: InMemoryPlantRepository());
      await tester.tap(find.byTooltip('戻る'));
      await tester.pumpAndSettle();
      expect(find.text('まだ株がありません'), findsOneWidget);
    });

    testWidgets('入力があると確認が出る。「続ける」で残り、「破棄して戻る」で戻る', (tester) async {
      final repo = InMemoryPlantRepository();
      await pumpAddScreen(tester, repo: repo);
      await tester.enterText(field('name'), 'パキラ');
      await tester.pump(); // 入力を反映した画面を作り直してから、戻る操作をする(実機では、入力と操作の間に画面が更新される)
      await tester.tap(find.byTooltip('戻る'));
      await tester.pumpAndSettle();
      expect(find.text('入力を破棄しますか?'), findsOneWidget);

      await tester.tap(find.text('続ける'));
      await tester.pumpAndSettle();
      expect(field('name'), findsOneWidget);
      expect(tester.widget<TextField>(field('name')).controller!.text, 'パキラ');

      await tester.tap(find.byTooltip('戻る'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('破棄して戻る'));
      await tester.pumpAndSettle();
      expect(find.text('まだ株がありません'), findsOneWidget);
      expect(await plantsOf(tester, repo), isEmpty);
    });

    testWidgets('ジャンルやタグだけを変えても、入力ありとして確認が出る', (tester) async {
      await pumpAddScreen(tester, repo: InMemoryPlantRepository());
      await tester.tap(find.byKey(const Key('tag-seedling')));
      await tester.pump();
      await tester.tap(find.byTooltip('戻る'));
      await tester.pumpAndSettle();
      expect(find.text('入力を破棄しますか?'), findsOneWidget);
    });
  });
}
