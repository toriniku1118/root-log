import 'dart:async';

import '../domain/plant_genre.dart';
import '../domain/user_profile.dart';

/// サインインの方法(Apple・Google のみ。メールアドレスでのログインは用意しない)。
/// Firebase 接続前は、仮のサインイン(区別だけ持つ)。
enum SignInProvider {
  apple('Apple'),
  google('Google');

  const SignInProvider(this.label);

  final String label;
}

/// サインインの状態と、登録済みのユーザー情報。
///
/// - サインインしていない:[provider] が null
/// - サインイン済み・まだ登録していない:[provider] があり、[profile] が null
/// - 登録済み:[profile] がある
class Session {
  const Session({this.provider, this.profile});

  final SignInProvider? provider;
  final UserProfile? profile;

  bool get signedIn => provider != null;
  bool get registered => signedIn && profile != null;
}

/// サインインしていないのに、登録しようとしたときに投げる。
class NotSignedInException implements Exception {
  const NotSignedInException();

  @override
  String toString() => 'NotSignedInException';
}

/// 登録していないのに、登録済みの人だけができる操作をしようとしたときに投げる。
class NotRegisteredException implements Exception {
  const NotRegisteredException();

  @override
  String toString() => 'NotRegisteredException';
}

/// すでに登録済みなのに、もう一度登録しようとしたときに投げる(年齢区分は後から変更できない)。
class AlreadyRegisteredException implements Exception {
  const AlreadyRegisteredException();

  @override
  String toString() => 'AlreadyRegisteredException';
}

/// ユーザー情報の保存先の差し替え口。画面は保存先(メモリ・Firebase)を知らない。
abstract interface class UserRepository {
  /// サインインの状態と登録の状態。購読した時点の内容がすぐ流れ、変わるたびに流れる。
  Stream<Session> watchSession();

  /// サインインする(Firebase 接続前は仮)。登録済みの人は、そのまま登録済みになる。
  Future<void> signIn(SignInProvider provider);

  /// サインアウトする。登録した内容は残る。
  Future<void> signOut();

  /// 初回の登録。サインインしていなければ [NotSignedInException]、すでに登録済みなら
  /// [AlreadyRegisteredException]、条件を満たさなければ [UserProfileValidationException]。
  ///
  /// 通知はすべてオフで作る。公開の説明を確認した日時と作成日時は、保存先の時刻で決まる(後から変えられない)。
  Future<UserProfile> createProfile(UserProfileInput input);

  /// 通知の種類ごとのオン/オフを保存する。変わるのは通知設定と更新日時だけ。
  /// サインインしていなければ [NotSignedInException]、登録していなければ [NotRegisteredException]。
  Future<UserProfile> updateNotify(NotifySettings notify);

  /// アカウントを削除する(ユーザー情報とサインインが消える。株・記録の削除は `PlantRepository.deleteAll`)。
  /// 本物では、サーバーの `deleteAccount` がまとめて処理する。サインインしていなければ [NotSignedInException]。
  Future<void> deleteAccount();
}

/// メモリ上の保存先(1人分だけ)。アプリを閉じると消える。Firebase 接続前と、テストで使う。
class InMemoryUserRepository implements UserRepository {
  InMemoryUserRepository({DateTime Function()? clock, SignInProvider? signedInWith, this._profile})
      : _clock = clock ?? DateTime.now,
        _provider = signedInWith;

  /// 登録済みでサインイン済みの状態(テストで、初回の画面を飛ばして始めるために使う)。
  factory InMemoryUserRepository.registered({DateTime Function()? clock}) {
    final now = (clock ?? DateTime.now)();
    return InMemoryUserRepository(
      clock: clock,
      signedInWith: SignInProvider.google,
      profile: UserProfile(
        displayName: 'テストユーザー',
        ageBand: AgeBand.adult,
        genres: const <PlantGenre>{},
        notify: const NotifySettings(),
        publishAckAt: now,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  final DateTime Function() _clock;
  SignInProvider? _provider;
  UserProfile? _profile;
  final StreamController<Session> _changes = StreamController<Session>.broadcast(sync: true);

  Session _session() => Session(provider: _provider, profile: _provider == null ? null : _profile);

  @override
  Stream<Session> watchSession() {
    late final StreamController<Session> controller;
    StreamSubscription<Session>? subscription;
    controller = StreamController<Session>(
      onListen: () {
        controller.add(_session());
        subscription = _changes.stream.listen(controller.add);
      },
      onCancel: () => subscription?.cancel(),
    );
    return controller.stream;
  }

  @override
  Future<void> signIn(SignInProvider provider) async {
    _provider = provider;
    _changes.add(_session());
  }

  @override
  Future<void> signOut() async {
    _provider = null;
    _changes.add(_session());
  }

  @override
  Future<UserProfile> updateNotify(NotifySettings notify) async {
    if (_provider == null) throw const NotSignedInException();
    final current = _profile;
    if (current == null) throw const NotRegisteredException();
    final updated = current.withNotify(notify, updatedAt: _clock());
    _profile = updated;
    _changes.add(_session());
    return updated;
  }

  @override
  Future<void> deleteAccount() async {
    if (_provider == null) throw const NotSignedInException();
    _profile = null;
    _provider = null;
    _changes.add(_session());
  }

  @override
  Future<UserProfile> createProfile(UserProfileInput input) async {
    if (_provider == null) throw const NotSignedInException();
    if (_profile != null) throw const AlreadyRegisteredException();
    final errors = validateUserProfile(input);
    if (errors.isNotEmpty) throw UserProfileValidationException(errors);
    final now = _clock();
    final code = input.prefecture;
    final profile = UserProfile(
      displayName: input.displayName.trim(),
      ageBand: input.ageBand!,
      genres: Set.unmodifiable(input.genres),
      prefecture: (code == null || code.isEmpty) ? null : code,
      notify: const NotifySettings(), // すべてオフ(オプトイン)
      publishAckAt: now,
      createdAt: now,
      updatedAt: now,
    );
    _profile = profile;
    _changes.add(_session());
    return profile;
  }
}
