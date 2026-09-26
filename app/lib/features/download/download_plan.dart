import '../../domain/plant.dart';
import '../../domain/plant_photo.dart';

// 写真のダウンロード(SCR-13。REQ-046、FN-26)の計画。どの写真を、どの順で、どんな名前で保存するかを決める。
// 画面から切り離した関数にして、単体テストできるようにしている。
//
// 渡すのは、処理後の画像(位置情報を削除済み)だけ。来歴の印はファイル名にもファイルにも付けない。

/// 保存する1枚。
class DownloadItem {
  const DownloadItem({required this.photo, required this.plantName, required this.serial, required this.fileName});

  final PlantPhoto photo;
  final String plantName;

  /// 株ごとの連番(1から。受信時刻の順)。
  final int serial;
  final String fileName;
}

/// ファイル名に使えない文字を置き換える。空になったら「株」にする。
///
/// 置き換えるのは、`\ / : * ? " < > |`・制御文字・空白(連続は1つの `_` に)。前後の `.` `_` は取る
/// (先頭の `.` は隠しファイルになるため)。長さは30文字まで(絵文字などを途中で切らないよう、文字単位で数える)。
String sanitizeFileNamePart(String name) {
  var s = name.replaceAll(RegExp(r'[\\/:*?"<>|\u0000-\u001f\u007f\s]+'), '_');
  s = s.replaceAll(RegExp(r'^[._]+|[._]+$'), '');
  if (s.isEmpty) return '株';
  final runes = s.runes.toList();
  if (runes.length > 30) {
    s = String.fromCharCodes(runes.take(30)).replaceAll(RegExp(r'[._]+$'), '');
  }
  return s;
}

/// 例:20260920-100305(受信時刻。年月日-時分秒)。
String formatFileTime(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year.toString().padLeft(4, '0')}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}${two(t.second)}';
}

DateTime _dateOnly(DateTime t) => DateTime(t.year, t.month, t.day);

/// 保存の対象と順序・名前を決める。
///
/// - [photosByPlant]:株の id → 写真の記録(`watchPhotos` の順。新しいものが先)。削除した写真・処理中の写真は、
///   写真の記録がない(または完了していない)ので、入らない。
/// - [from]・[to]:受信時刻の**日付**で数える(両端の日を含む)。null なら、その側は制限なし。
/// - [plantIds]:対象の株。null なら全株。
/// - [excludedPhotoIds]:一覧から外した写真。
///
/// 返す順は、受信時刻の古い順(同じ時刻なら、作った順)。連番は株ごとに、対象になった写真の中での順。
/// 名前が重なったら(同じ名前の株・同じ連番・同じ秒)、`_2` `_3` を付けて区別する。
List<DownloadItem> buildDownloadPlan({
  required List<Plant> plants,
  required Map<String, List<PlantPhoto>> photosByPlant,
  DateTime? from,
  DateTime? to,
  Set<String>? plantIds,
  Set<String> excludedPhotoIds = const {},
}) {
  final fromDay = from == null ? null : _dateOnly(from);
  final toDay = to == null ? null : _dateOnly(to);

  final candidates = <({Plant plant, PlantPhoto photo, int order})>[];
  var order = 0;
  for (final plant in plants) {
    if (plantIds != null && !plantIds.contains(plant.id)) continue;
    final photos = photosByPlant[plant.id] ?? const <PlantPhoto>[];
    // 新しい順で渡されるので、逆にすると、作った順(古い順)になる
    for (final photo in photos.reversed) {
      order++;
      if (excludedPhotoIds.contains(photo.id)) continue;
      final day = _dateOnly(photo.receivedAt);
      if (fromDay != null && day.isBefore(fromDay)) continue;
      if (toDay != null && day.isAfter(toDay)) continue;
      candidates.add((plant: plant, photo: photo, order: order));
    }
  }
  candidates.sort((a, b) {
    final c = a.photo.receivedAt.compareTo(b.photo.receivedAt);
    return c != 0 ? c : a.order.compareTo(b.order);
  });

  final serials = <String, int>{};
  final used = <String>{};
  final items = <DownloadItem>[];
  for (final c in candidates) {
    final serial = (serials[c.plant.id] ?? 0) + 1;
    serials[c.plant.id] = serial;
    final base = '${sanitizeFileNamePart(c.plant.name)}_${serial.toString().padLeft(3, '0')}_${formatFileTime(c.photo.receivedAt)}';
    var name = '$base.jpg';
    for (var n = 2; used.contains(name); n++) {
      name = '${base}_$n.jpg';
    }
    used.add(name);
    items.add(DownloadItem(photo: c.photo, plantName: c.plant.name, serial: serial, fileName: name));
  }
  return items;
}
