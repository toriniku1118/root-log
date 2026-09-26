import '../../domain/plant_health.dart';
import '../../domain/plant_log.dart';
import '../../domain/plant_photo.dart';

/// 栽培ストーリー(株の詳細の時系列)の組み立て。画面から切り離して、単体でテストできるようにしてある。

/// 時系列の1件。記録([log])か、写真([photo])のどちらか。健康状態の変更のときは、変更前の状態([previousHealth])も持つ。
class StoryEntry {
  const StoryEntry(PlantLog this.log, {this.previousHealth}) : photo = null;

  const StoryEntry.photo(PlantPhoto this.photo)
      : log = null,
        previousHealth = null;

  final PlantLog? log;
  final PlantPhoto? photo;

  /// 種類が健康状態のときだけ。変更前の状態(最初の変更は「初期」)。
  final PlantHealth? previousHealth;

  /// 並びと日付に使う時刻。記録は出来事の日時、写真はサーバーが受信した時刻。
  DateTime get time => photo?.receivedAt ?? log!.occurredAt;

  /// 一意な id(画面のキーに使う)。
  String get id => photo != null ? 'photo-${photo!.id}' : log!.id;

  /// 時系列の1行の見出し。例:「水やり」「段階:新芽」「健康状態:要観察 → 不調」「写真」。
  String get title {
    if (photo != null) return '写真';
    final l = log!;
    return switch (l.type) {
      PlantLogType.stage => '段階:${l.stage?.label ?? ''}',
      PlantLogType.health => '健康状態:${(previousHealth ?? defaultPlantHealth).label} → ${l.health?.label ?? ''}',
      _ => l.type.label,
    };
  }
}

/// 同じ日(出来事の日時の日付)の記録・写真のまとまり。
class StoryDay {
  const StoryDay(this.date, this.entries);

  final DateTime date;
  final List<StoryEntry> entries;
}

/// 記録と写真を、日付ごとにまとめた時系列にする(新しい日が上。同じ日の中も新しいものが上)。
///
/// [logsNewestFirst] は `PlantRepository.watchLogs` の順(新しい順)、[photos] は `watchPhotos` の順(新しい順)。
/// 同じ時刻のときは、記録が写真より上。健康状態の「変更前」は、健康状態の記録を古い順にたどって求める(最初は「初期」)。
List<StoryDay> buildStory(List<PlantLog> logsNewestFirst, {List<PlantPhoto> photos = const []}) {
  final previous = <String, PlantHealth>{};
  var current = defaultPlantHealth;
  for (final log in logsNewestFirst.reversed) {
    if (log.type != PlantLogType.health || log.health == null) continue;
    previous[log.id] = current;
    current = log.health!;
  }

  final all = <StoryEntry>[
    for (final log in logsNewestFirst) StoryEntry(log, previousHealth: previous[log.id]),
    for (final photo in photos) StoryEntry.photo(photo),
  ];
  // 時刻の新しい順(同じ時刻は、渡された順のまま)
  final indexed = [for (var i = 0; i < all.length; i++) (i, all[i])]
    ..sort((a, b) {
      final byTime = b.$2.time.compareTo(a.$2.time);
      return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
    });

  final days = <StoryDay>[];
  for (final (_, entry) in indexed) {
    final t = entry.time;
    final date = DateTime(t.year, t.month, t.day);
    if (days.isNotEmpty && days.last.date == date) {
      days.last.entries.add(entry);
    } else {
      days.add(StoryDay(date, [entry]));
    }
  }
  return days;
}

/// 例:2026/09/20
String formatDate(DateTime d) =>
    '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
