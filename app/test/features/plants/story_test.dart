import 'package:flutter_test/flutter_test.dart';
import 'package:rootlog/domain/plant_health.dart';
import 'package:rootlog/domain/plant_log.dart';
import 'package:rootlog/domain/plant_stage.dart';
import 'package:rootlog/features/plants/story.dart';

int _n = 0;

PlantLog log(
  PlantLogType type,
  DateTime occurredAt, {
  String? note,
  PlantStage? stage,
  PlantHealth? health,
  DateTime? recordedAt,
}) =>
    PlantLog(
      id: 'l${++_n}',
      plantId: 'p',
      type: type,
      occurredAt: occurredAt,
      recordedAt: recordedAt ?? occurredAt,
      note: note,
      stage: stage,
      health: health,
    );

void main() {
  setUp(() => _n = 0);

  test('記録がなければ、時系列も空', () {
    expect(buildStory(const []), isEmpty);
  });

  test('日付ごとにまとまり、新しい日が上。同じ日の中は、渡された順(新しいものが上)のまま', () {
    final a = log(PlantLogType.water, DateTime(2026, 9, 20, 10));
    final b = log(PlantLogType.note, DateTime(2026, 9, 20, 8), note: 'つぼみ');
    final c = log(PlantLogType.water, DateTime(2026, 9, 13, 9));
    final story = buildStory([a, b, c]); // 新しい順
    expect(story.map((d) => d.date), [DateTime(2026, 9, 20), DateTime(2026, 9, 13)]);
    expect(story[0].entries.map((e) => e.log), [a, b]);
    expect(story[1].entries.map((e) => e.log), [c]);
  });

  test('見出し:水やり・メモ・段階・健康状態', () {
    final water = StoryEntry(log(PlantLogType.water, DateTime(2026, 9, 1)));
    final memo = StoryEntry(log(PlantLogType.note, DateTime(2026, 9, 1), note: 'x'));
    final stage = StoryEntry(log(PlantLogType.stage, DateTime(2026, 9, 1), stage: PlantStage.newLeaf));
    final repot = StoryEntry(log(PlantLogType.repot, DateTime(2026, 9, 1)));
    expect(water.title, '水やり');
    expect(memo.title, 'メモ');
    expect(stage.title, '段階:新芽');
    expect(repot.title, '植え替え');
  });

  test('健康状態は「前 → 後」で出る。最初の変更の前は「初期」。記録の並びから、前の状態を求める', () {
    final h1 = log(PlantLogType.health, DateTime(2026, 9, 13), health: PlantHealth.watch);
    final h2 = log(PlantLogType.health, DateTime(2026, 9, 20), health: PlantHealth.bad, note: '葉がしおれてきた');
    final h3 = log(PlantLogType.health, DateTime(2026, 9, 25), health: PlantHealth.recovering);
    final water = log(PlantLogType.water, DateTime(2026, 9, 22));
    final story = buildStory([h3, water, h2, h1]); // 新しい順
    final titles = {for (final d in story) for (final e in d.entries) e.log.id: e.title};
    expect(titles[h1.id], '健康状態:初期 → 要観察');
    expect(titles[h2.id], '健康状態:要観察 → 不調');
    expect(titles[h3.id], '健康状態:不調 → 復活中');
    expect(titles[water.id], '水やり');
  });

  test('日付は、出来事の日時のもの(記録した時刻ではない)。日付の境目は、その日の0時', () {
    final l = log(
      PlantLogType.water,
      DateTime(2026, 9, 1, 23, 59),
      recordedAt: DateTime(2026, 9, 30, 8),
    );
    expect(buildStory([l]).single.date, DateTime(2026, 9, 1));
    final next = log(PlantLogType.water, DateTime(2026, 9, 2, 0, 0));
    expect(buildStory([next, l]).map((d) => d.date), [DateTime(2026, 9, 2), DateTime(2026, 9, 1)]);
  });

  test('日付の表示は yyyy/MM/dd(月・日は2桁)', () {
    expect(formatDate(DateTime(2026, 9, 5)), '2026/09/05');
    expect(formatDate(DateTime(2026, 12, 25)), '2026/12/25');
  });
}
