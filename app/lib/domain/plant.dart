import 'plant_genre.dart';
import 'plant_health.dart';
import 'plant_tag.dart';

/// 公開の範囲(`firebase/firestore.rules` の visibility.scope)。
enum PlantScope {
  photos('photos', '写真のみ'),
  history('history', '履歴まで'),
  source('source', '入手先まで');

  const PlantScope(this.id, this.label);
  final String id;
  final String label;
}

/// 共有設定。新しい株は初期公開・写真のみ(2026-09-26。オプトアウト)。公開はステップ3で使えるようになる。
/// 他の人に見えるのは、本人が公開の説明を確認した後だけ(サーバーが書き出す。REQ-049)。
class PlantVisibility {
  const PlantVisibility({required this.public, required this.scope});

  /// 新規作成時の共有設定:公開・範囲は写真のみ。
  const PlantVisibility.defaultVisibility() : this(public: true, scope: PlantScope.photos);

  final bool public;
  final PlantScope scope;
}

/// 株。来歴の印(hasProvenance)は、サーバーだけが設定する項目なので持たない。
class Plant {
  const Plant({
    required this.id,
    required this.name,
    required this.genres,
    required this.tags,
    required this.visibility,
    required this.createdAt,
    required this.updatedAt,
    this.variety,
    this.acquiredAt,
    this.source,
    this.locationName,
    this.potSize,
    this.purchasePrice,
    this.health = defaultPlantHealth,
    this.hasProvenance = false,
  });

  final String id;
  final String name;

  /// ジャンル(1〜3個。傾向の整理に使う)。実生はジャンルではなくタグで表す。
  final Set<PlantGenre> genres;
  final String? variety;
  final DateTime? acquiredAt;

  /// 入手先(非公開)。
  final String? source;

  /// 置き場所の名前だけ。住所・位置情報は持たない。
  final String? locationName;
  final String? potSize;

  /// 購入価格(円)。自分だけが見られる。公開用データには出さない(盗難対策)。
  final int? purchasePrice;

  /// いまの健康状態。変更は記録としても残す(株の履歴でたどれる)。
  final PlantHealth health;

  /// 来歴つきの写真がある印。**サーバーだけが設定する**(アプリは読むだけ。書き戻さない)。
  final bool hasProvenance;
  final Set<PlantTag> tags;
  final PlantVisibility visibility;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// 共有設定だけを変えた株(そのほかの項目・作成日時・健康状態は変わらない)。
  Plant withVisibility(PlantVisibility newVisibility, {required DateTime updatedAt}) => Plant(
        id: id,
        name: name,
        genres: genres,
        tags: tags,
        visibility: newVisibility,
        createdAt: createdAt,
        updatedAt: updatedAt,
        variety: variety,
        acquiredAt: acquiredAt,
        source: source,
        locationName: locationName,
        potSize: potSize,
        purchasePrice: purchasePrice,
        health: health,
        hasProvenance: hasProvenance,
      );

  /// 来歴の印だけを変えた株(サーバーの処理を真似るメモリ版が使う。アプリの画面は呼ばない)。
  Plant withHasProvenance(bool value) => Plant(
        id: id,
        name: name,
        genres: genres,
        tags: tags,
        visibility: visibility,
        createdAt: createdAt,
        updatedAt: updatedAt,
        variety: variety,
        acquiredAt: acquiredAt,
        source: source,
        locationName: locationName,
        potSize: potSize,
        purchasePrice: purchasePrice,
        health: health,
        hasProvenance: value,
      );

  /// 健康状態だけを変えた株(そのほかの項目・作成日時・共有設定は変わらない)。
  Plant withHealth(PlantHealth newHealth, {required DateTime updatedAt}) => Plant(
        id: id,
        name: name,
        genres: genres,
        tags: tags,
        visibility: visibility,
        createdAt: createdAt,
        updatedAt: updatedAt,
        variety: variety,
        acquiredAt: acquiredAt,
        source: source,
        locationName: locationName,
        potSize: potSize,
        purchasePrice: purchasePrice,
        health: newHealth,
        hasProvenance: hasProvenance,
      );
}
