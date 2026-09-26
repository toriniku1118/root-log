import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rootlog/app.dart';
import 'package:rootlog/data/plant_repository.dart';
import 'package:rootlog/data/user_repository.dart';
import 'package:rootlog/domain/plant_genre.dart';
import 'package:rootlog/domain/user_profile.dart';
import 'package:rootlog/providers.dart';

Future<InMemoryUserRepository> pumpApp(WidgetTester tester, {InMemoryUserRepository? users}) async {
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final repo = users ?? InMemoryUserRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        plantRepositoryProvider.overrideWithValue(InMemoryPlantRepository()),
        userRepositoryProvider.overrideWithValue(repo),
      ],
      child: const RootLogApp(),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

Future<Session> sessionOf(WidgetTester tester, UserRepository repo) async =>
    (await tester.runAsync(() => repo.watchSession().first))!;

Future<void> tapKey(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

/// ようこそで説明を読んだことを確認して、サインインする。
Future<void> signIn(WidgetTester tester, {String key = 'sign-in-google'}) async {
  await tapKey(tester, 'read-check');
  await tapKey(tester, key);
}

bool enabled(WidgetTester tester, String key) => tester.widget<FilledButton>(find.byKey(Key(key))).onPressed != null;

Future<void> chooseAge(WidgetTester tester, String label) => tapText(tester, label);

void main() {
  group('ようこそ(SCR-01)', () {
    testWidgets('アプリの説明と、公開の説明(誰に何が見えるか)が出る', (tester) async {
      await pumpApp(tester);
      expect(find.text('RootLog'), findsOneWidget);
      expect(find.text('誰に何が見えるか'), findsOneWidget);
      final lines = tester.widgetList<Text>(find.byKey(const Key('explain-line'))).map((t) => t.data!).toList();
      expect(lines, contains('・初期設定では、あなたの株の写真だけが公開されます。'));
      expect(lines, contains('・名前・ジャンル・品種・タグと、写真が、ログインしている人に見えます。'));
      expect(lines, contains('・位置情報は取得しません。写真の位置情報(EXIF)は削除します。'));
      expect(lines.any((l) => l.contains('置き場所・鉢の号数・購入価格・健康状態・メモの中身は、どの範囲でも見えません')), isTrue);
      expect(lines, contains('・株ごとに、いつでも非公開にできます。'));
      // 古い文言(「はじめは、すべて非公開です」)は出ない
      expect(find.textContaining('はじめは、すべて非公開'), findsNothing);
    });

    testWidgets('「上の説明を読みました」にチェックするまで、サインインできない', (tester) async {
      await pumpApp(tester);
      expect(enabled(tester, 'sign-in-apple'), isFalse);
      expect(enabled(tester, 'sign-in-google'), isFalse);
      await tapKey(tester, 'read-check');
      expect(enabled(tester, 'sign-in-apple'), isTrue);
      expect(enabled(tester, 'sign-in-google'), isTrue);
      await tapKey(tester, 'read-check'); // 外すと、また押せない
      expect(enabled(tester, 'sign-in-apple'), isFalse);
    });

    testWidgets('AppleでもGoogleでも、サインインすると年齢の確認に進む', (tester) async {
      for (final (key, provider) in [('sign-in-apple', SignInProvider.apple), ('sign-in-google', SignInProvider.google)]) {
        final repo = await pumpApp(tester);
        await signIn(tester, key: key);
        expect(find.text('年齢を選んでください'), findsOneWidget);
        expect((await sessionOf(tester, repo)).provider, provider);
        await tester.pumpWidget(const SizedBox()); // 次の繰り返しのために作り直す
      }
    });

    testWidgets('登録済みの人は、起動するとホームから始まる(ようこそは出ない)', (tester) async {
      await pumpApp(tester, users: InMemoryUserRepository.registered());
      expect(find.text('まだ株がありません'), findsOneWidget);
      expect(find.byKey(const Key('read-check')), findsNothing);
    });
  });

  group('年齢の確認(SCR-02)', () {
    testWidgets('13歳未満を選ぶと、利用できない旨が出て、先へ進めない', (tester) async {
      await pumpApp(tester);
      await signIn(tester);
      expect(enabled(tester, 'next'), isFalse); // 選ぶまで進めない
      await chooseAge(tester, '13歳未満');
      expect(find.byKey(const Key('under13-notice')), findsOneWidget);
      expect(find.text('13歳未満の方は、このアプリを利用できません。'), findsOneWidget);
      expect(enabled(tester, 'next'), isFalse);
    });

    testWidgets('「後から変更できません。売買・交換は18歳以上」の注意が出る', (tester) async {
      await pumpApp(tester);
      await signIn(tester);
      expect(find.text('※ 後から変更できません。売買・交換は18歳以上の方だけです。'), findsOneWidget);
    });

    testWidgets('13〜17歳・18歳以上を選ぶと、次へ進める', (tester) async {
      await pumpApp(tester);
      await signIn(tester);
      await chooseAge(tester, '13〜17歳');
      expect(enabled(tester, 'next'), isTrue);
      await chooseAge(tester, '13歳未満'); // 選び直すと、また進めない
      expect(enabled(tester, 'next'), isFalse);
      await chooseAge(tester, '18歳以上');
      await tapKey(tester, 'next');
      expect(find.text('はじめの設定'), findsOneWidget);
    });
  });

  group('はじめの設定(SCR-14)', () {
    Future<void> toProfile(WidgetTester tester, [String age = '18歳以上']) async {
      await signIn(tester);
      await chooseAge(tester, age);
      await tapKey(tester, 'next');
    }

    testWidgets('表示名は必須(空だとエラー)。30文字まで(31文字はエラー)', (tester) async {
      await pumpApp(tester);
      await toProfile(tester);
      await tapKey(tester, 'next');
      expect(find.text('表示名を入力してください'), findsOneWidget);
      expect(find.text('はじめの設定'), findsOneWidget); // 進まない

      await tester.enterText(find.byKey(const Key('field-displayName')), List.filled(31, 'あ').join());
      await tapKey(tester, 'next');
      expect(find.text('表示名は30文字以内で入力してください'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('field-displayName')), List.filled(30, 'あ').join());
      await tapKey(tester, 'next');
      expect(find.text('好きなジャンル'), findsOneWidget);
    });

    testWidgets('エラーは、直すと消える', (tester) async {
      await pumpApp(tester);
      await toProfile(tester);
      await tapKey(tester, 'next');
      expect(find.text('表示名を入力してください'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('field-displayName')), 'アリス');
      await tester.pumpAndSettle();
      expect(find.text('表示名を入力してください'), findsNothing);
    });

    testWidgets('都道府県は任意(初期は「選ばない」)。位置情報は取得しない旨が出る', (tester) async {
      await pumpApp(tester);
      await toProfile(tester);
      expect(find.text('選ばない'), findsOneWidget);
      expect(find.text('イベントのお知らせに使います。位置情報は取得しません'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('field-displayName')), 'アリス');
      await tapKey(tester, 'next');
      expect(find.text('好きなジャンル'), findsOneWidget);
    });

    testWidgets('戻ると、年齢の確認に戻る(選んだ年齢は残っている)', (tester) async {
      await pumpApp(tester);
      await toProfile(tester, '13〜17歳');
      await tester.tap(find.byTooltip('戻る'));
      await tester.pumpAndSettle();
      expect(find.text('年齢を選んでください'), findsOneWidget);
      expect(enabled(tester, 'next'), isTrue); // 13〜17歳が選ばれたまま
    });
  });

  group('好きなジャンル(SCR-03)と登録', () {
    Future<void> toGenres(WidgetTester tester, {String age = '18歳以上', String name = 'アリス'}) async {
      await signIn(tester);
      await chooseAge(tester, age);
      await tapKey(tester, 'next');
      await tester.enterText(find.byKey(const Key('field-displayName')), name);
      await tapKey(tester, 'next');
    }

    testWidgets('9つのジャンルが、例つきで並ぶ(0個でも進める)', (tester) async {
      await pumpApp(tester);
      await toGenres(tester);
      for (final g in PlantGenre.values) {
        expect(find.byKey(Key('genre-${g.id}')), findsOneWidget, reason: g.label);
      }
      expect(find.text('観葉植物全般(パキラ・ゴムの木・ガジュマル・サンスベリア等)'), findsOneWidget);
      expect(find.text('アロイド(モンステラ・ポトス・アンスリウム・アロカシア等)'), findsOneWidget);
      expect(enabled(tester, 'next'), isTrue);
    });

    testWidgets('ジャンルを選んで「次へ」で登録され、ホームになる。内容が保存される(通知はすべてオフ・確認の日時つき)', (tester) async {
      final repo = await pumpApp(tester);
      await toGenres(tester, age: '13〜17歳', name: '  アリス  ');
      await tapKey(tester, 'genre-caudex');
      await tapKey(tester, 'genre-agave');
      await tapKey(tester, 'next');

      expect(find.text('まだ株がありません'), findsOneWidget); // ホーム
      final profile = (await sessionOf(tester, repo)).profile!;
      expect(profile.displayName, 'アリス');
      expect(profile.ageBand, AgeBand.teen);
      expect(profile.genres, {PlantGenre.caudex, PlantGenre.agave});
      expect(profile.prefecture, isNull);
      expect(profile.notify.toMap().values.every((v) => !v), isTrue);
      expect(profile.publishAckAt, isNotNull);
    });

    testWidgets('「スキップ」で、ジャンルなしで登録される。都道府県を選ぶと保存される', (tester) async {
      final repo = await pumpApp(tester);
      await signIn(tester);
      await chooseAge(tester, '18歳以上');
      await tapKey(tester, 'next');
      await tester.enterText(find.byKey(const Key('field-displayName')), 'ボブ');
      await tapKey(tester, 'field-prefecture');
      await tester.tap(find.text('東京都').last);
      await tester.pumpAndSettle();
      await tapKey(tester, 'next');
      await tapKey(tester, 'genre-rare'); // 選んでもスキップすると、ジャンルなし
      await tapKey(tester, 'skip');

      expect(find.text('まだ株がありません'), findsOneWidget);
      final profile = (await sessionOf(tester, repo)).profile!;
      expect(profile.genres, isEmpty);
      expect(profile.prefecture, '13');
      expect(profile.ageBand, AgeBand.adult);
    });

    testWidgets('9つすべてを選んで登録できる', (tester) async {
      final repo = await pumpApp(tester);
      await toGenres(tester);
      for (final g in PlantGenre.values) {
        await tapKey(tester, 'genre-${g.id}');
      }
      await tapKey(tester, 'next');
      expect((await sessionOf(tester, repo)).profile!.genres, hasLength(9));
    });

    testWidgets('戻ると、はじめの設定に戻る(入力した表示名は残っている)', (tester) async {
      await pumpApp(tester);
      await toGenres(tester, name: 'アリス');
      await tester.tap(find.byTooltip('戻る'));
      await tester.pumpAndSettle();
      expect(find.text('はじめの設定'), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const Key('field-displayName'))).controller!.text, 'アリス');
    });

    testWidgets('ようこそで説明を確認していない(サインイン済みで始まった)ときは、ここでも確認してから登録する', (tester) async {
      final users = InMemoryUserRepository(signedInWith: SignInProvider.google);
      final repo = await pumpApp(tester, users: users);
      await chooseAge(tester, '18歳以上');
      await tapKey(tester, 'next');
      await tester.enterText(find.byKey(const Key('field-displayName')), 'アリス');
      await tapKey(tester, 'next');

      expect(find.byKey(const Key('read-check')), findsOneWidget);
      expect(enabled(tester, 'next'), isFalse);
      await tapKey(tester, 'read-check');
      expect(enabled(tester, 'next'), isTrue);
      await tapKey(tester, 'next');
      expect((await sessionOf(tester, repo)).registered, isTrue);
    });

    testWidgets('ようこそで確認したときは、ここに確認は出ない', (tester) async {
      await pumpApp(tester);
      await toGenres(tester);
      expect(find.byKey(const Key('read-check')), findsNothing);
    });
  });
}
