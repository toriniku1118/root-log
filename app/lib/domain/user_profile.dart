import 'plant_genre.dart';
import 'prefecture.dart';

/// 年齢区分。`id` は `firebase/firestore.rules` の `ageBand` と同じ文字列。
/// 13歳未満は使えない(区分がない)。売買・交換・手渡しは18歳以上(ステップ5)。後から変更できない。
enum AgeBand {
  teen('13-17', '13〜17歳'),
  adult('18+', '18歳以上');

  const AgeBand(this.id, this.label);

  final String id;
  final String label;

  static AgeBand? fromId(String id) {
    for (final a in values) {
      if (a.id == id) return a;
    }
    return null;
  }
}

/// ユーザー情報の入力条件。`firebase/firestore.rules` の `validUserFields` と同じ値。
abstract final class ProfileLimits {
  /// 表示名の文字数の上限(UTF-16 の単位。絵文字は2文字分)。下限は1。
  static const displayName = 30;

  /// 好きなジャンルの個数の上限(9つすべて)。
  static const genresMax = 9;
}

/// 通知の種類ごとのオン/オフ(`users.notify`)。**すべて初期オフ**(2026-09-26。オプトイン)。
class NotifySettings {
  const NotifySettings({
    this.photo = false,
    this.event = false,
    this.water = false,
    this.weather = false,
    this.reaction = false,
    this.stock = false,
  });

  /// 撮影通知。
  final bool photo;

  /// イベント。
  final bool event;

  /// 水やり通知。
  final bool water;

  /// 季節・天気。
  final bool weather;

  /// 反応(いいね・コメント・回答)。
  final bool reaction;

  /// 入荷(探している株)。
  final bool stock;

  /// 一部だけ変えた通知設定。
  NotifySettings copyWith({bool? photo, bool? event, bool? water, bool? weather, bool? reaction, bool? stock}) =>
      NotifySettings(
        photo: photo ?? this.photo,
        event: event ?? this.event,
        water: water ?? this.water,
        weather: weather ?? this.weather,
        reaction: reaction ?? this.reaction,
        stock: stock ?? this.stock,
      );

  /// 種類の id(ルールの `notify` のキーと同じ)。
  static const keys = ['photo', 'event', 'water', 'weather', 'reaction', 'stock'];

  Map<String, bool> toMap() => {
        'photo': photo,
        'event': event,
        'water': water,
        'weather': weather,
        'reaction': reaction,
        'stock': stock,
      };
}

/// ユーザー情報(`users/{uid}`)。課金状態(`plan`)は、サーバーだけが設定する項目なので持たない。
class UserProfile {
  const UserProfile({
    required this.displayName,
    required this.ageBand,
    required this.genres,
    required this.notify,
    required this.publishAckAt,
    required this.createdAt,
    required this.updatedAt,
    this.prefecture,
  });

  final String displayName;

  /// 年齢区分。後から変更できない。
  final AgeBand ageBand;

  /// 好きなジャンル(「育ててみたい」の傾向。9つまで)。
  final Set<PlantGenre> genres;

  /// 都道府県(コード)。未設定は null。位置情報は取得しない。
  final String? prefecture;
  final NotifySettings notify;

  /// 公開の説明を確認した日時(REQ-049)。保存先の時刻で決まり、後から変えられない。
  /// この日時があるまで、サーバーは公開用データを書き出さない。
  final DateTime publishAckAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// 通知設定だけを変えたユーザー情報(そのほかの項目・年齢区分・確認の日時・作成日時は変わらない)。
  UserProfile withNotify(NotifySettings newNotify, {required DateTime updatedAt}) => UserProfile(
        displayName: displayName,
        ageBand: ageBand,
        genres: genres,
        notify: newNotify,
        publishAckAt: publishAckAt,
        createdAt: createdAt,
        updatedAt: updatedAt,
        prefecture: prefecture,
      );
}

enum UserProfileField { displayName, ageBand, genres, prefecture, publishConfirmed }

/// ユーザー情報の入力(初回の登録)。表示名は前後の空白を取り除く。
class UserProfileInput {
  const UserProfileInput({
    this.displayName = '',
    this.ageBand,
    this.genres = const {},
    this.prefecture,
    this.publishConfirmed = false,
  });

  final String displayName;

  /// 選ばれていなければ null(登録できない)。
  final AgeBand? ageBand;
  final Set<PlantGenre> genres;

  /// 都道府県のコード。未設定は null(または空)。
  final String? prefecture;

  /// 公開の説明を確認したか(初回に、明示的に確認してもらう。REQ-049)。
  final bool publishConfirmed;
}

/// 入力の検証。条件は `firebase/firestore.rules` の `validUserFields` と一致させる
/// (`test/domain/plant_rules_consistency_test.dart` で突き合わせている)。
///
/// - 表示名は前後の空白を除いて1〜30文字(UTF-16 の単位。絵文字は2文字分)。
/// - 年齢区分は必須。好きなジャンルは9つまで(9つのどれか)。都道府県は未設定またはコード '01'〜'47'。
/// - 公開の説明の確認は必須。
Map<UserProfileField, String> validateUserProfile(UserProfileInput input) {
  final errors = <UserProfileField, String>{};
  final name = input.displayName.trim();
  if (name.isEmpty) {
    errors[UserProfileField.displayName] = '表示名を入力してください';
  } else if (name.length > ProfileLimits.displayName) {
    errors[UserProfileField.displayName] = '表示名は${ProfileLimits.displayName}文字以内で入力してください';
  }
  if (input.ageBand == null) {
    errors[UserProfileField.ageBand] = '年齢を選んでください';
  }
  if (input.genres.length > ProfileLimits.genresMax) {
    errors[UserProfileField.genres] = 'ジャンルは${ProfileLimits.genresMax}個までです';
  }
  final code = input.prefecture;
  if (code != null && code.isNotEmpty && prefectureFromCode(code) == null) {
    errors[UserProfileField.prefecture] = '都道府県が正しくありません';
  }
  if (!input.publishConfirmed) {
    errors[UserProfileField.publishConfirmed] = '公開の説明を確認してください';
  }
  return errors;
}

/// 入力が条件を満たさないときに投げる。
class UserProfileValidationException implements Exception {
  const UserProfileValidationException(this.errors);

  final Map<UserProfileField, String> errors;

  @override
  String toString() => 'UserProfileValidationException($errors)';
}
