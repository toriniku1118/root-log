import 'package:flutter_test/flutter_test.dart';
import 'package:rootlog/domain/plant_genre.dart';
import 'package:rootlog/domain/prefecture.dart';
import 'package:rootlog/domain/user_profile.dart';

String chars(int n, [String c = 'あ']) => List.filled(n, c).join();

UserProfileInput valid({
  String displayName = 'アリス',
  AgeBand? ageBand = AgeBand.adult,
  Set<PlantGenre> genres = const {},
  String? prefecture,
  bool publishConfirmed = true,
}) =>
    UserProfileInput(
      displayName: displayName,
      ageBand: ageBand,
      genres: genres,
      prefecture: prefecture,
      publishConfirmed: publishConfirmed,
    );

Map<UserProfileField, String> validate(UserProfileInput input) => validateUserProfile(input);

void main() {
  test('年齢区分は2つで、id と日本語の表示名が決めたとおり(13歳未満は使えない)', () {
    expect({for (final a in AgeBand.values) a.id: a.label}, {'13-17': '13〜17歳', '18+': '18歳以上'});
    expect(AgeBand.fromId('18+'), AgeBand.adult);
    expect(AgeBand.fromId('under13'), isNull);
  });

  test('通知はすべて初期オフ。種類は6つ', () {
    const n = NotifySettings();
    expect(n.toMap().values.every((v) => v == false), isTrue);
    expect(n.toMap().keys.toList(), NotifySettings.keys);
    expect(NotifySettings.keys, ['photo', 'event', 'water', 'weather', 'reaction', 'stock']);
    expect(const NotifySettings(photo: true).toMap()['photo'], isTrue);
  });

  group('都道府県', () {
    test('47あり、コードは01〜47で重複しない。名前は空でない', () {
      expect(prefectures, hasLength(47));
      expect(prefectures.map((p) => p.code).toList(), [for (var i = 1; i <= 47; i++) i.toString().padLeft(2, '0')]);
      expect(prefectures.map((p) => p.name).toSet(), hasLength(47));
      expect(prefectures.every((p) => p.name.isNotEmpty), isTrue);
    });
    test('コードから引ける。未設定・空・知らないコードは null', () {
      expect(prefectureFromCode('13')?.name, '東京都');
      expect(prefectureFromCode('01')?.name, '北海道');
      expect(prefectureFromCode('47')?.name, '沖縄県');
      expect(prefectureFromCode(null), isNull);
      expect(prefectureFromCode(''), isNull);
      expect(prefectureFromCode('48'), isNull);
      expect(prefectureFromCode('1'), isNull);
    });
  });

  group('表示名(1〜30文字)', () {
    test('1文字と30文字は通る', () {
      expect(validate(valid(displayName: 'a')), isEmpty);
      expect(validate(valid(displayName: chars(30))), isEmpty);
    });
    test('空・空白だけはエラー', () {
      final errors = validate(valid(displayName: ''));
      expect(errors.keys, [UserProfileField.displayName]);
      expect(errors[UserProfileField.displayName], '表示名を入力してください');
      expect(validate(valid(displayName: '  　 ')).keys, [UserProfileField.displayName]);
    });
    test('31文字はエラー。前後の空白は取り除いて数える', () {
      final errors = validate(valid(displayName: chars(31)));
      expect(errors[UserProfileField.displayName], '表示名は30文字以内で入力してください');
      expect(validate(valid(displayName: '  ${chars(30)}  ')), isEmpty);
    });
    test('絵文字は2文字分として数える(ルールの size() に合わせる。15個は通り、16個はエラー)', () {
      expect(validate(valid(displayName: chars(15, '🌱'))), isEmpty);
      expect(validate(valid(displayName: chars(16, '🌱'))).keys, [UserProfileField.displayName]);
    });
  });

  group('年齢区分・ジャンル・都道府県・公開の説明の確認', () {
    test('年齢区分は必須', () {
      final errors = validate(valid(ageBand: null));
      expect(errors.keys, [UserProfileField.ageBand]);
      expect(errors[UserProfileField.ageBand], '年齢を選んでください');
      expect(validate(valid(ageBand: AgeBand.teen)), isEmpty);
    });
    test('好きなジャンルは0個でも、9つすべてでもよい', () {
      expect(validate(valid(genres: const {})), isEmpty);
      expect(validate(valid(genres: {...PlantGenre.values})), isEmpty);
      expect(PlantGenre.values, hasLength(ProfileLimits.genresMax));
    });
    test('都道府県は、未設定(null・空)か、01〜47。それ以外はエラー', () {
      expect(validate(valid(prefecture: null)), isEmpty);
      expect(validate(valid(prefecture: '')), isEmpty);
      expect(validate(valid(prefecture: '13')), isEmpty);
      final errors = validate(valid(prefecture: '99'));
      expect(errors.keys, [UserProfileField.prefecture]);
      expect(errors[UserProfileField.prefecture], '都道府県が正しくありません');
    });
    test('公開の説明の確認は必須', () {
      final errors = validate(valid(publishConfirmed: false));
      expect(errors.keys, [UserProfileField.publishConfirmed]);
      expect(errors[UserProfileField.publishConfirmed], '公開の説明を確認してください');
    });
    test('複数のエラーはまとめて返す', () {
      final errors = validate(const UserProfileInput());
      expect(errors.keys.toSet(), {UserProfileField.displayName, UserProfileField.ageBand, UserProfileField.publishConfirmed});
    });
  });
}
