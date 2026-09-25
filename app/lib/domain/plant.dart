import 'plant_genre.dart';
import 'plant_tag.dart';

/// 公開の範囲(`firebase/firestore.rules` の visibility.scope)。
enum PlantScope {
  photos('photos'),
  history('history'),
  source('source');

  const PlantScope(this.id);
  final String id;
}

/// 共有設定。新しい株は必ず非公開(公開はステップ3で使えるようになる)。
class PlantVisibility {
  const PlantVisibility({required this.public, required this.scope});

  /// 新規作成時の共有設定:非公開・範囲は写真のみ。
  const PlantVisibility.privateDefault() : this(public: false, scope: PlantScope.photos);

  final bool public;
  final PlantScope scope;
}

/// 株。来歴の印(hasProvenance)は、サーバーだけが設定する項目なので持たない。
class Plant {
  const Plant({
    required this.id,
    required this.name,
    required this.genre,
    required this.tags,
    required this.visibility,
    required this.createdAt,
    required this.updatedAt,
    this.variety,
    this.acquiredAt,
    this.source,
    this.locationName,
    this.potSize,
  });

  final String id;
  final String name;
  final PlantGenre genre;
  final String? variety;
  final DateTime? acquiredAt;

  /// 入手先(非公開)。
  final String? source;

  /// 置き場所の名前だけ。住所・位置情報は持たない。
  final String? locationName;
  final String? potSize;
  final Set<PlantTag> tags;
  final PlantVisibility visibility;
  final DateTime createdAt;
  final DateTime updatedAt;
}
