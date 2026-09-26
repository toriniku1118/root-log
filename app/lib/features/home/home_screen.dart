import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../constants.dart';
import '../../domain/plant.dart';
import '../../domain/plant_health.dart';
import '../../domain/plant_log.dart';
import '../../providers.dart';
import '../plants/care.dart';
import '../plants/plant_detail_screen.dart';
import '../plants/plant_form_screen.dart';
import '../settings/settings_screen.dart';
import 'plant_groups.dart';

/// ホーム(植物リスト)。株を置き場所ごとにまとめて表示する。
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plants = ref.watch(plantsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text(appName),
        actions: [
          TextButton(
            key: const Key('open-settings'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
            child: const Text('設定'),
          ),
        ],
      ),
      body: plants.when(
        data: (list) => list.isEmpty ? const _EmptyState() : _PlantList(groups: groupPlantsByLocation(list)),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('株を読み込めませんでした')),
      ),
      floatingActionButton: plants.hasValue && plants.requireValue.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () => _openAddPlant(context),
              icon: const Icon(Icons.add),
              label: const Text('株を追加'),
            )
          : null,
    );
  }
}

void _openAddPlant(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PlantFormScreen()));
}

void _openPlantDetail(BuildContext context, Plant plant) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlantDetailScreen(plantId: plant.id)));
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.spa_outlined, size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('まだ株がありません', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '育てている観葉植物を登録して、成長を記録しましょう。',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _openAddPlant(context),
              icon: const Icon(Icons.add),
              label: const Text('最初の株を追加'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 見出し(置き場所)と株を1本のリストにして、表示に必要な分だけ描画する。
class _PlantList extends StatelessWidget {
  const _PlantList({required this.groups});

  final List<PlantGroup> groups;

  static const unsetLocationLabel = '置き場所未設定';

  @override
  Widget build(BuildContext context) {
    final rows = <Object>[
      for (final g in groups) ...[g, ...g.plants],
    ];
    return ListView.builder(
      // 右下の「株を追加」ボタンに最後の株が隠れないようにする
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final row = rows[i];
        return switch (row) {
          PlantGroup g => _LocationHeader(g.locationName ?? unsetLocationLabel),
          Plant p => _PlantTile(p),
          _ => const SizedBox.shrink(),
        };
      },
    );
  }
}

class _LocationHeader extends StatelessWidget {
  const _LocationHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(label, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
    );
  }
}

/// 株を長押しして、水やりを記録する(日時は今)。「取り消し」で消せる。
Future<void> _waterFromHome(BuildContext context, WidgetRef ref, Plant plant) async {
  final repo = ref.read(plantRepositoryProvider);
  final messenger = ScaffoldMessenger.of(context);
  void show(SnackBar bar) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(bar);
  try {
    final log = await repo.addLog(plant.id, PlantLogInput(type: PlantLogType.water, occurredAt: DateTime.now()));
    show(SnackBar(
      content: Text('「${plant.name}」に水やりを記録しました'),
      action: SnackBarAction(label: '取り消し', onPressed: () => repo.deleteLog(plant.id, log.id)),
    ));
  } on Object {
    show(const SnackBar(content: Text('記録できませんでした。もう一度試してください')));
  }
}

class _PlantTile extends ConsumerWidget {
  const _PlantTile(this.plant);

  final Plant plant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final variety = plant.variety;
    final genreLabel = plant.genres.map((g) => g.label).join('・');
    final subtitle = variety == null ? genreLabel : '$genreLabel・$variety';
    final tags = plant.tags.toList()..sort((a, b) => a.index.compareTo(b.index));
    final lastWatered = ref.watch(lastWateredProvider(plant.id));
    final showHealth = plant.health != PlantHealth.initial; // 「初期」(まだ決めていない)のときは出さない
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => _openPlantDetail(context, plant), // 株の詳細(SCR-08)を開く。編集は詳細の「編集」から
        onLongPress: () => _waterFromHome(context, ref, plant), // 長押しで水やり(FN-14)
        title: Text(plant.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subtitle),
            if (tags.isNotEmpty || showHealth)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (showHealth)
                      Chip(
                        key: Key('health-chip-${plant.id}'),
                        label: Text('健康状態:${plant.health.label}'),
                        visualDensity: VisualDensity.compact,
                      ),
                    for (final t in tags) Chip(label: Text(t.label), visualDensity: VisualDensity.compact),
                  ],
                ),
              ),
            if (lastWatered != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(waterLine(lastWatered, DateTime.now()), key: Key('water-line-${plant.id}')),
              ),
          ],
        ),
      ),
    );
  }
}
