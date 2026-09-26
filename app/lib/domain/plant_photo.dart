/// 撮影元。`id` は `firebase/functions/src/index.ts` の `source` と同じ文字列。
enum PhotoSource {
  camera('camera'),
  gallery('gallery');

  const PhotoSource(this.id);

  final String id;
}

/// サーバーが判定した、来歴にならなかった(または、なった)理由。
/// `id` は `firebase/functions/src/index.ts` の `provenanceReason` と同じ文字列
/// (`test/features/plants/photo_provenance_test.dart` で突き合わせている)。
enum ProvenanceReason {
  /// 来歴つき。アプリ内カメラで撮影し、撮影時刻と受信時刻の差が10分以内で、同じ画像が他にない。
  ok('ok'),

  /// 端末の写真から選んだ(撮影元が gallery)。
  gallery('gallery'),

  /// 撮影時刻が読み取れない。
  noCaptureTime('no_capture_time'),

  /// 撮影時刻と受信時刻が離れている(10分より)。
  captureTimeMismatch('capture_time_mismatch'),

  /// 同じ画像がすでに登録されている。
  duplicate('duplicate');

  const ProvenanceReason(this.id);

  final String id;

  static ProvenanceReason? fromId(String id) {
    for (final r in values) {
      if (r.id == id) return r;
    }
    return null;
  }
}

/// 写真の記録(`users/{uid}/plants/{plantId}/photos/{photoId}`)。**サーバーだけが作る**(アプリからは作れない。
/// 受信時刻を偽れないようにするため)。アプリは読むだけ。
///
/// 撮影時刻(EXIF)は、判定にだけ使って保存しない。確実なのは、サーバーが受信した時刻([receivedAt])だけ。
class PlantPhoto {
  const PlantPhoto({
    required this.id,
    required this.plantId,
    required this.storagePath,
    required this.source,
    required this.receivedAt,
    required this.provenance,
    required this.provenanceReason,
    this.width,
    this.height,
  });

  final String id;
  final String plantId;

  /// 保存先(処理後の画像。位置情報などは削除済み)。
  final String storagePath;
  final PhotoSource source;

  /// サーバーが受信した時刻(後から変えられない)。
  final DateTime receivedAt;

  /// 来歴つきか。`provenanceReason` が `ok` のときだけ true。
  final bool provenance;
  final ProvenanceReason provenanceReason;
  final int? width;
  final int? height;
}
