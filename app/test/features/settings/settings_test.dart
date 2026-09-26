import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rootlog/app.dart';
import 'package:rootlog/data/plant_repository.dart';
import 'package:rootlog/data/user_repository.dart';
import 'package:rootlog/domain/plant_input.dart';
import 'package:rootlog/domain/plant_log.dart';
import 'package:rootlog/domain/user_profile.dart';
import 'package:rootlog/features/settings/legal_screen.dart';
import 'package:rootlog/providers.dart';

/// 削除に失敗するユーザー保存先(登録済み。「削除できませんでした」の確認用)。
class _FailingDeleteUsers extends InMemoryUserRepository {
  _FailingDeleteUsers()
      : super(
          signedInWith: SignInProvider.google,
          profile: UserProfile(
            displayName: 'テスト',
            ageBand: AgeBand.adult,
            genres: const {},
            notify: const NotifySettings(),
            publishAckAt: DateTime(2026),
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
          ),
        );

  @override
  Future<void> deleteAccount() async => throw StateError('失敗');
}

const _docs = {
  'assets/legal/privacy.md': '../docs/privacy-policy-draft.md',
  'assets/legal/terms.md': '../docs/terms-draft.md',
};

Future<(InMemoryPlantRepository, InMemoryUserRepository)> pumpSettings(
  WidgetTester tester, {
  InMemoryUserRepository? users,
  List<PlantInput> plants = const [],
}) async {
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final plantRepo = InMemoryPlantRepository();
  for (final p in plants) {
    await plantRepo.add(p);
  }
  final userRepo = users ?? InMemoryUserRepository.registered();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        plantRepositoryProvider.overrideWithValue(plantRepo),
        userRepositoryProvider.overrideWithValue(userRepo),
        // 全文は、草案のファイルから直接読む(テストの中では、アセットの読み込みが止まることがあるため)
        legalTextLoaderProvider.overrideWithValue((path) async => File(_docs[path]!).readAsStringSync()),
      ],
      child: const RootLogApp(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('open-settings')));
  await tester.pumpAndSettle();
  return (plantRepo, userRepo);
}

Future<Session> sessionOf(WidgetTester tester, UserRepository repo) async =>
    (await tester.runAsync(() => repo.watchSession().first))!;

Future<void> tapKey(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

bool switchValue(WidgetTester tester, String key) => tester.widget<SwitchListTile>(find.byKey(Key(key))).value;

void main() {
  test('アプリに同梱した規約・ポリシーは、docs/ の草案と同じ(食い違っていない)', () {
    expect(File('assets/legal/privacy.md').readAsStringSync(), File('../docs/privacy-policy-draft.md').readAsStringSync());
    expect(File('assets/legal/terms.md').readAsStringSync(), File('../docs/terms-draft.md').readAsStringSync());
    expect(LegalDocument.privacy.assetPath, 'assets/legal/privacy.md');
    expect(LegalDocument.terms.assetPath, 'assets/legal/terms.md');
  });

  group('設定の画面(SCR-11)', () {
    testWidgets('ホームの「設定」で開く。通知は撮影・水やりのどちらも初期オフ。注記が出る', (tester) async {
      await pumpSettings(tester);
      expect(find.text('設定'), findsWidgets);
      expect(switchValue(tester, 'notify-photo'), isFalse);
      expect(switchValue(tester, 'notify-water'), isFalse);
      expect(find.textContaining('全種類あわせて、原則1日1回まで'), findsOneWidget);
      expect(find.textContaining('初期はオフ'), findsOneWidget);
      for (final label in ['プライバシーポリシー', '利用規約', 'サインアウト', 'アカウントを削除']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('撮影通知を切り替えると、保存される(ほかの通知・登録内容は変わらない)。開き直しても残る', (tester) async {
      final (_, users) = await pumpSettings(tester);
      final before = (await sessionOf(tester, users)).profile!;
      await tapKey(tester, 'notify-photo');
      expect(switchValue(tester, 'notify-photo'), isTrue);
      expect(switchValue(tester, 'notify-water'), isFalse);

      final after = (await sessionOf(tester, users)).profile!;
      expect(after.notify.photo, isTrue);
      expect(after.notify.water, isFalse);
      expect(after.notify.event, isFalse);
      expect(after.displayName, before.displayName);
      expect(after.ageBand, before.ageBand);
      expect(after.publishAckAt, before.publishAckAt);

      await tester.tap(find.byTooltip('戻る'));
      await tester.pumpAndSettle();
      await tapKey(tester, 'open-settings');
      expect(switchValue(tester, 'notify-photo'), isTrue); // 開き直しても残っている
    });

    testWidgets('水やり通知を入れて、また切ると、オフに戻る', (tester) async {
      final (_, users) = await pumpSettings(tester);
      await tapKey(tester, 'notify-water');
      expect((await sessionOf(tester, users)).profile!.notify.water, isTrue);
      await tapKey(tester, 'notify-water');
      expect((await sessionOf(tester, users)).profile!.notify.water, isFalse);
      expect(switchValue(tester, 'notify-water'), isFalse);
    });
  });

  group('規約・プライバシーポリシー(FN-24)', () {
    testWidgets('プライバシーポリシーの全文を読める(草案と同じ)', (tester) async {
      await pumpSettings(tester);
      await tapKey(tester, 'open-privacy');
      expect(find.text('プライバシーポリシー'), findsOneWidget); // 画面のタイトル
      final shown = tester.widget<SelectableText>(find.byKey(const Key('legal-text'))).data;
      expect(shown, File('../docs/privacy-policy-draft.md').readAsStringSync());
    });

    testWidgets('利用規約の全文を読める(草案と同じ)。戻ると設定に戻る', (tester) async {
      await pumpSettings(tester);
      await tapKey(tester, 'open-terms');
      final shown = tester.widget<SelectableText>(find.byKey(const Key('legal-text'))).data;
      expect(shown, File('../docs/terms-draft.md').readAsStringSync());
      await tester.tap(find.byTooltip('戻る'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('open-terms')), findsOneWidget);
    });
  });

  group('サインアウト', () {
    testWidgets('確認のあとサインアウトして、ようこそ画面になる。「やめる」なら残る', (tester) async {
      await pumpSettings(tester);
      await tapKey(tester, 'sign-out');
      expect(find.text('サインアウトしますか?'), findsOneWidget);
      await tester.tap(find.text('やめる'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('open-privacy')), findsOneWidget); // 設定に残っている

      await tapKey(tester, 'sign-out');
      await tapKey(tester, 'sign-out-confirm');
      expect(find.byKey(const Key('read-check')), findsOneWidget); // ようこそ
      expect(find.byKey(const Key('open-privacy')), findsNothing);
    });

    testWidgets('サインアウトしても登録した内容は残り、サインインし直すとホームに戻る', (tester) async {
      final (_, users) = await pumpSettings(tester, plants: const [PlantInput(name: 'モンステラ')]);
      await tapKey(tester, 'sign-out');
      await tapKey(tester, 'sign-out-confirm');
      expect((await sessionOf(tester, users)).signedIn, isFalse);

      await tapKey(tester, 'read-check');
      await tapKey(tester, 'sign-in-google');
      expect(find.text('モンステラ'), findsOneWidget); // ホーム。株も残っている
    });
  });

  group('アカウント削除(SCR-12)', () {
    testWidgets('設定から開くと、削除される内容の説明が出る', (tester) async {
      await pumpSettings(tester);
      await tapKey(tester, 'open-delete-account');
      expect(find.text('アカウントを削除します'), findsOneWidget);
      expect(find.text('次のものがすべて消え、元に戻せません。'), findsOneWidget);
      expect(find.text('・登録した株、記録、写真'), findsOneWidget);
      expect(find.text('・公開している内容'), findsOneWidget);
      expect(find.text('・ログイン情報'), findsOneWidget);
    });

    testWidgets('「やめる」で設定に戻る。確認の「やめる」なら、削除されない', (tester) async {
      final (plants, users) = await pumpSettings(tester, plants: const [PlantInput(name: 'モンステラ')]);
      await tapKey(tester, 'open-delete-account');
      await tapKey(tester, 'cancel');
      expect(find.byKey(const Key('open-delete-account')), findsOneWidget); // 設定に戻った

      await tapKey(tester, 'open-delete-account');
      await tapKey(tester, 'delete-account');
      expect(find.text('本当に削除しますか?'), findsOneWidget); // もう一度確認
      await tester.tap(find.text('やめる').last);
      await tester.pumpAndSettle();
      expect(find.text('本当に削除しますか?'), findsNothing);
      expect((await sessionOf(tester, users)).registered, isTrue);
      expect(await tester.runAsync(() => plants.watchAll().first), hasLength(1));
    });

    testWidgets('二段階の確認のあと削除され、ようこそ画面に戻る。株・記録も消える', (tester) async {
      final (plants, users) = await pumpSettings(tester, plants: const [PlantInput(name: 'モンステラ')]);
      final plantId = (await tester.runAsync(() => plants.watchAll().first))!.single.id;
      await tester.runAsync(() => plants.addLog(plantId, PlantLogInput(type: PlantLogType.water, occurredAt: DateTime.now())));
      await tapKey(tester, 'open-delete-account');
      await tapKey(tester, 'delete-account');
      await tapKey(tester, 'delete-confirm');

      expect(find.byKey(const Key('read-check')), findsOneWidget); // ようこそ
      expect(find.text('アカウントを削除しました'), findsOneWidget);
      expect(await tester.runAsync(() => plants.watchAll().first), isEmpty);
      expect(await tester.runAsync(() => plants.watchLogs(plantId).first), isEmpty);
      final s = await sessionOf(tester, users);
      expect(s.signedIn, isFalse);
      expect(s.profile, isNull);
    });

    testWidgets('削除したあと、サインインし直すと、初回の設定(年齢)から始まる', (tester) async {
      await pumpSettings(tester);
      await tapKey(tester, 'open-delete-account');
      await tapKey(tester, 'delete-account');
      await tapKey(tester, 'delete-confirm');
      await tapKey(tester, 'read-check');
      await tapKey(tester, 'sign-in-google');
      expect(find.text('年齢を選んでください'), findsOneWidget);
    });

    testWidgets('削除できなかったら「削除できませんでした」と出て、この画面に残る(サインインしたまま)', (tester) async {
      final users = _FailingDeleteUsers();
      await pumpSettings(tester, users: users);
      await tapKey(tester, 'open-delete-account');
      await tapKey(tester, 'delete-account');
      await tapKey(tester, 'delete-confirm');
      expect(find.text('削除できませんでした。もう一度試してください'), findsOneWidget);
      expect(find.byKey(const Key('delete-account')), findsOneWidget); // この画面に残る
      expect((await sessionOf(tester, users)).registered, isTrue);
      // もう一度押せる
      expect(tester.widget<FilledButton>(find.byKey(const Key('delete-account'))).onPressed, isNotNull);
    });
  });
}
