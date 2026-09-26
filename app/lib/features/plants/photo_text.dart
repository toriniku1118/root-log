import '../../domain/plant_photo.dart';

// 写真の来歴の表示文言(外部設計 3.7.1。SCR-04・SCR-08 で同じ文言)。
//
// 「この日時までに」と書くのは、撮影元と撮影時刻は端末側の情報で、改造したアプリなら偽装できるため。
// 確実に保証できるのは、サーバーが受信した時刻だけ(設計0 1.4 の限界)。過大に書かない。

/// 来歴にならなかった理由の文言。来歴つき(`ok`)は [provenanceLabel] が別に返す。
String notProvenanceText(ProvenanceReason reason) => switch (reason) {
      ProvenanceReason.ok => '',
      ProvenanceReason.gallery => '端末の写真のため、来歴になりません',
      ProvenanceReason.noCaptureTime => '撮影時刻が読み取れないため、来歴になりません',
      ProvenanceReason.captureTimeMismatch => '撮影時刻と受信時刻が離れているため、来歴になりません',
      ProvenanceReason.duplicate => '同じ写真が登録済みのため、来歴になりません',
    };

/// 例:09/20 10:03(月/日 時:分)。
String formatReceivedAt(DateTime t) =>
    '${t.month.toString().padLeft(2, '0')}/${t.day.toString().padLeft(2, '0')} '
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// 写真の来歴の表示。来歴つきは「この日時までに撮影された写真 09/20 10:03」(受信時刻)、
/// そうでなければ理由。
String provenanceLabel(PlantPhoto photo) => photo.provenance
    ? 'この日時までに撮影された写真 ${formatReceivedAt(photo.receivedAt)}'
    : notProvenanceText(photo.provenanceReason);
