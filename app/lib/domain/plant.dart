import 'plant_genre.dart';
import 'plant_health.dart';
import 'plant_tag.dart';

/// 公開の範囲(`firebase/firestore.rules` の visibility.scope)。
enum PlantScope {
  photos('photos'),
  history('history'),
  source('source');

  const PlantScope(this.id);
  final String id;
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
  final Set<PlantTag> tags;
  final PlantVisibility visibility;
  final DateTime createdAt;
  final DateTime updatedAt;
}
