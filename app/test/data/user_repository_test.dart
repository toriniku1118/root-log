import 'package:flutter_test/flutter_test.dart';
import 'package:rootlog/data/user_repository.dart';
import 'package:rootlog/domain/plant_genre.dart';
import 'package:rootlog/domain/user_profile.dart';

void main() {
  late DateTime clockNow;
  late InMemoryUserRepository repo;

  setUp(() {
    clockNow = DateTime(2026, 9, 26, 12);
    repo = InMemoryUserRepository(clock: () => clockNow);
  });

  UserProfileInput input({
    String name = 'アリス',
    AgeBand? age = AgeBand.adult,
    Set<PlantGenre> genres = const {PlantGenre.caudex, PlantGenre.agave},
    String? prefecture = '13',
    bool confirmed = true,
  }) =>
      UserProfileInput(displayName: name, ageBand: age, genres: genres, prefecture: prefecture, publishConfirmed: confirmed);

  Future<Session> session() => repo.watchSession().first;

  test('最初は、サインインしていない', () async {
    final s = await session();
    expect(s.signedIn, isFalse);
    expect(s.registered, isFalse);
    expect(s.profile, isNull);
  });

  test('サインインすると、サインイン済み・まだ登録していない', () async {
    await repo.signIn(SignInProvider.apple);
    final s = await session();
    expect(s.signedIn, isTrue);
    expect(s.provider, SignInProvider.apple);
    expect(s.registered, isFalse);
  });

  test('サインインしていないと、登録できない', () async {
    await expectLater(repo.createProfile(input()), throwsA(isA<NotSignedInException>()));
  });

  group('登録', () {
    setUp(() async => repo.signIn(SignInProvider.google));

    test('登録すると、内容が保存され、登録済みになる。通知はすべてオフ。確認の日時と作成日時は保存先の時刻', () async {
      final profile = await repo.createProfile(input(name: '  アリス  '));
      expect(profile.displayName, 'アリス'); // 前後の空白は取り除く
      expect(profile.ageBand, AgeBand.adult);
      expect(profile.genres, {PlantGenre.caudex, PlantGenre.agave});
      expect(profile.prefecture, '13');
      expect(profile.notify.toMap().values.every((v) => !v), isTrue);
      expect(profile.publishAckAt, clockNow);
      expect(profile.createdAt, clockNow);
      expect(profile.updatedAt, clockNow);

      final s = await session();
      expect(s.registered, isTrue);
      expect(s.profile, same(profile));
    });

    test('都道府県は未設定でもよい(null・空は、未設定として保存される)', () async {
      expect((await repo.createProfile(input(prefecture: null))).prefecture, isNull);
      // 別のリポジトリで、空の場合も確かめる
      final other = InMemoryUserRepository(clock: () => clockNow);
      await other.signIn(SignInProvider.apple);
      expect((await other.createProfile(input(prefecture: ''))).prefecture, isNull);
    });

    test('好きなジャンルは0個でもよい', () async {
      expect((await repo.createProfile(input(genres: const {}))).genres, isEmpty);
    });

    test('条件を満たさないと、登録されない(登録済みにならない)', () async {
      for (final bad in [input(name: ''), input(age: null), input(confirmed: false), input(prefecture: '99')]) {
        await expectLater(repo.createProfile(bad), throwsA(isA<UserProfileValidationException>()));
      }
      expect((await session()).registered, isFalse);
    });

    test('公開の説明を確認していないと登録できない(確認は必須)', () async {
      await expectLater(
        repo.createProfile(input(confirmed: false)),
        throwsA(isA<UserProfileValidationException>().having((e) => e.errors.keys, 'keys', [UserProfileField.publishConfirmed])),
      );
    });

    test('二重に登録できない(年齢区分は後から変えられない)', () async {
      await repo.createProfile(input(age: AgeBand.teen));
      await expectLater(repo.createProfile(input(age: AgeBand.adult)), throwsA(isA<AlreadyRegisteredException>()));
      expect((await session()).profile!.ageBand, AgeBand.teen);
    });

    test('確認の日時は、あとの時刻に変わらない(作ったときの時刻のまま)', () async {
      final profile = await repo.createProfile(input());
      clockNow = DateTime(2026, 10, 1);
      expect((await session()).profile!.publishAckAt, profile.publishAckAt);
    });
  });

  group('サインアウト', () {
    test('サインアウトすると、サインインしていない状態に戻る。登録した内容は残り、サインインし直すと登録済み', () async {
      await repo.signIn(SignInProvider.google);
      final profile = await repo.createProfile(input());
      await repo.signOut();
      final out = await session();
      expect(out.signedIn, isFalse);
      expect(out.profile, isNull); // サインインしていない間は、内容を出さない

      await repo.signIn(SignInProvider.google);
      final back = await session();
      expect(back.registered, isTrue);
      expect(back.profile, same(profile));
    });
  });

  test('状態は購読で流れる(サインイン → 登録 → サインアウト)', () async {
    final seen = <String>[];
    final sub = repo.watchSession().listen((s) => seen.add(s.registered ? '登録済み' : s.signedIn ? 'サインイン済み' : 'サインアウト'));
    await Future<void>.delayed(Duration.zero);
    await repo.signIn(SignInProvider.apple);
    await repo.createProfile(input());
    await repo.signOut();
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(seen, ['サインアウト', 'サインイン済み', '登録済み', 'サインアウト']);
  });

  test('テスト用の登録済みの状態(registered)は、サインイン済みで、通知はすべてオフ', () async {
    final r = InMemoryUserRepository.registered(clock: () => clockNow);
    final s = await r.watchSession().first;
    expect(s.registered, isTrue);
    expect(s.profile!.notify.toMap().values.every((v) => !v), isTrue);
    expect(s.profile!.publishAckAt, clockNow);
  });
}
