import '../domain/plant_photo.dart';

/// 保存できなかった理由。
enum PhotoSaveFailure {
  /// 写真を読み込めなかった(通信・保存先の問題)。
  readFailed,

  /// 写真フォルダへの保存が許可されていない。
  permissionDenied,
}

class PhotoSaveException implements Exception {
  const PhotoSaveException(this.failure);

  final PhotoSaveFailure failure;

  @override
  String toString() => 'PhotoSaveException(${failure.name})';
}

/// 写真を端末の写真フォルダに保存する差し替え口(REQ-046)。画面は、実際の保存の仕方を知らない。
///
/// 本物の実装は、自分の写真(`photos/{uid}/{photoId}.jpg`。本人だけが読める既存の権限)を読み込み、
/// 端末の写真フォルダに書く。端末ごとに許可・保存の仕方が違うため、実機で確かめる段階(順13)で、
/// ライブラリを選んで作る。
abstract class PhotoSaver {
  /// 実際には保存しない動作確認用か。true のとき、画面がその旨を表示する。
  bool get isPlaceholder;

  /// 1枚を [fileName] で保存する。失敗したら [PhotoSaveException]。
  Future<void> save(PlantPhoto photo, String fileName);
}

/// 動作確認用。実際には保存せず、名前を覚えるだけ(ステップ1のワイヤーフレームと、テストで使う)。
class InMemoryPhotoSaver implements PhotoSaver {
  InMemoryPhotoSaver({this.failure, this.failAtCount, this.beforeSave});

  /// 保存済みのファイル名(保存した順)。
  final List<String> saved = [];

  /// 指定すると、[failAtCount] 枚保存したあとの次の1枚で、その理由で失敗する(null なら失敗しない)。
  final PhotoSaveFailure? failure;
  final int? failAtCount;

  /// 1枚保存する前に呼ぶ(テストで、途中でやめる操作などを差し込む)。
  final Future<void> Function(String fileName)? beforeSave;

  @override
  bool get isPlaceholder => true;

  @override
  Future<void> save(PlantPhoto photo, String fileName) async {
    await beforeSave?.call(fileName);
    if (failure != null && saved.length >= (failAtCount ?? 0)) {
      throw PhotoSaveException(failure!);
    }
    saved.add(fileName);
  }
}
