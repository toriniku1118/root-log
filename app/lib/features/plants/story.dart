import '../../domain/plant_health.dart';
import '../../domain/plant_log.dart';

/// 栽培ストーリー(株の詳細の時系列)の組み立て。画面から切り離して、単体でテストできるようにしてある。

/// 時系列の1件。健康状態の変更のときは、変更前の状態([previousHealth])も持つ。
class StoryEntry {
  const StoryEntry(this.log, {this.previousHealth});

  final PlantLog log;

  /// 種類が健康状態のときだけ。変更前の状態(最初の変更は「初期」)。
  final PlantHealth? previousHealth;

  /// 時系列の1行の見出し。例:「水やり」「段階:新芽」「健康状態:要観察 → 不調」。
  String get title => switch (log.type) {
        PlantLogType.stage => '段階:${log.stage?.label ?? ''}',
        PlantLogType.health => '健康状態:${(previousHealth ?? defaultPlantHealth).label} → ${log.health?.label ?? ''}',
        _ => log.type.label,
      };
}

/// 同じ日(出来事の日時の日付)の記録のまとまり。
class StoryDay {
  const StoryDay(this.date, this.entries);

  final DateTime date;
  final List<StoryEntry> entries;
}

/// 記録を、日付ごとにまとめた時系列にする(新しい日が上。同じ日の中も新しいものが上)。
///
/// [logsNewestFirst] は `PlantRepository.watchLogs` の順(新しい順)。
/// 健康状態の「変更前」は、健康状態の記録を古い順にたどって求める(最初は「初期」)。
List<StoryDay> buildStory(List<PlantLog> logsNewestFirst) {
  final previous = <String, PlantHealth>{};
  var current = defaultPlantHealth;
  for (final log in logsNewestFirst.reversed) {
    if (log.type != PlantLogType.health || log.health == null) continue;
    previous[log.id] = current;
    current = log.health!;
  }

  final days = <StoryDay>[];
  for (final log in logsNewestFirst) {
    final date = DateTime(log.occurredAt.year, log.occurredAt.month, log.occurredAt.day);
    final entry = StoryEntry(log, previousHealth: previous[log.id]);
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
