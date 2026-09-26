import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/plant_repository.dart';
import '../../domain/plant.dart';
import '../../domain/plant_health.dart';
import '../../domain/plant_log.dart';
import '../../domain/plant_photo.dart';
import '../../domain/plant_stage.dart';
import '../../providers.dart';
import '../download/download_screen.dart';
import 'care.dart';
import 'log_dialog.dart';
import 'plant_form_screen.dart';
import 'photo_text.dart';
import 'plant_visibility_screen.dart';
import 'visibility_text.dart';
import 'story.dart';

/// 株の詳細(栽培ストーリー。SCR-08)。株の情報・記録ボタン・記録の時系列。
///
/// 記録の追加・編集・削除、健康状態の変更ができる。写真・撮影・共有設定・ダウンロードは、それぞれの機能ができるときに足す。
class PlantDetailScreen extends ConsumerStatefulWidget {
  const PlantDetailScreen({super.key, required this.plantId});

  final String plantId;

  @override
  ConsumerState<PlantDetailScreen> createState() => _PlantDetailScreenState();
}

class _PlantDetailScreenState extends ConsumerState<PlantDetailScreen> {
  bool _closing = false;

  PlantRepository get _repo => ref.read(plantRepositoryProvider);

  /// 記録の保存を実行して、結果を伝える。失敗したときは、エラーを出す。
  Future<void> _run(Future<void> Function() action, {String done = '記録しました'}) async {
    final messenger = ScaffoldMessenger.of(context);
    void show(String message) {
      messenger
        ..hideCurrentSnackBar() // 前のメッセージが残っていたら、新しいものに置き換える
        ..showSnackBar(SnackBar(content: Text(message)));
    }

    try {
      await action();
      show(done);
    } on PlantNotFoundException {
      show('株が見つかりません');
    } on Object {
      show('記録できませんでした。もう一度試してください');
    }
  }

  Future<void> _water() =>
      _run(() => _repo.addLog(widget.plantId, PlantLogInput(type: PlantLogType.water, occurredAt: DateTime.now())),
          done: '水やりを記録しました');

  Future<void> _record(PlantLogType type, {PlantStage? stage}) async {
    final title = stage == null ? '${type.label}を記録' : '段階「${stage.label}」を記録';
    final result = await showLogDialog(context, title: title, type: type, stage: stage);
    if (result == null || result.delete || !mounted) return;
    await _run(() => _repo.addLog(
          widget.plantId,
          PlantLogInput(type: type, occurredAt: result.occurredAt!, note: result.note, stage: stage),
        ));
  }

  Future<void> _changeHealth(PlantHealth health) async {
    final result = await showLogDialog(
      context,
      title: '健康状態を「${health.label}」にする',
      type: PlantLogType.health,
      health: health,
    );
    if (result == null || result.delete || !mounted) return;
    await _run(
      () => _repo.changeHealth(widget.plantId, health, note: result.note, occurredAt: result.occurredAt),
      done: '健康状態を「${health.label}」にしました',
    );
  }

  Future<void> _editLog(PlantLog log) async {
    final result = await showLogDialog(
      context,
      title: '${log.type.label}の記録を直す',
      type: log.type,
      existing: log,
    );
    if (result == null || !mounted) return;
    if (result.delete) {
      await _run(() => _repo.deleteLog(widget.plantId, log.id), done: '記録を削除しました');
    } else {
      await _run(
        () => _repo.updateLog(widget.plantId, log.id, occurredAt: result.occurredAt!, note: result.note),
        done: '記録を直しました',
      );
    }
  }

  Future<void> _openVisibility() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlantVisibilityScreen(plantId: widget.plantId)));
    if (!mounted || _closing) return;
    // 共有設定の画面を開いている間に、株がなくなっていた(画面が「株が見つかりません」を出している)。詳細も閉じる
    final gone = ref.read(plantsProvider).value?.every((p) => p.id != widget.plantId) ?? false;
    if (gone) {
      _closing = true;
      Navigator.of(context).pop();
    }
  }

  /// 写真の拡大(画像は仮の表示)と、削除。削除すると「削除された写真あり」の記録が残る(REQ-019)。
  Future<void> _openPhoto(PlantPhoto photo) async {
    final delete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('写真'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              key: const Key('photo-placeholder'),
              height: 160,
              alignment: Alignment.center,
              decoration: BoxDecoration(border: Border.all()),
              child: const Icon(Icons.image, size: 64),
            ),
            const SizedBox(height: 12),
            Text(provenanceLabel(photo), key: const Key('photo-provenance')),
            const SizedBox(height: 4),
            Text('受信:${formatDate(photo.receivedAt)} ${formatReceivedAt(photo.receivedAt).substring(6)}'),
          ],
        ),
        actions: [
          TextButton(key: const Key('photo-delete'), onPressed: () => Navigator.of(context).pop(true), child: const Text('この写真を削除')),
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('閉じる')),
        ],
      ),
    );
    if (delete != true || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('写真を削除しますか?'),
        content: const Text('元に戻せません。「削除された写真あり」の記録が残り、取引で相手に見せるときに、来歴の欠落が分かります。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('やめる')),
          TextButton(key: const Key('photo-delete-confirm'), onPressed: () => Navigator.of(context).pop(true), child: const Text('削除する')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() => _repo.deletePhoto(widget.plantId, photo.id), done: '写真を削除しました');
  }

  Future<void> _openEdit(Plant plant) async {
    final result = await Navigator.of(context).push<PlantFormResult>(
      MaterialPageRoute(builder: (_) => PlantFormScreen(plant: plant)),
    );
    if (!mounted || _closing) return;
    // 編集画面で削除した、または、編集している間に株がなくなっていた。詳細も閉じて、ホームに戻る
    final gone = ref.read(plantsProvider).value?.every((p) => p.id != widget.plantId) ?? false;
    if (result == PlantFormResult.deleted || gone) {
      _closing = true;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      // 編集画面が「削除しました」などを出しているときは、重ねて出さない
      if (result != PlantFormResult.deleted) {
        messenger.showSnackBar(const SnackBar(content: Text('株が見つかりません')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final plants = ref.watch(plantsProvider);
    final logs = ref.watch(plantLogsProvider(widget.plantId));
    final theme = Theme.of(context);

    final plant = plants.value?.where((p) => p.id == widget.plantId).firstOrNull;
    if (plants.hasValue && plant == null) {
      // 別の場所で削除された。「株が見つかりません」を出して、ホームへ戻る
      // (編集画面が上に開いているときは、編集画面が閉じたあとに [_openEdit] が閉じる)
      if (!_closing && (ModalRoute.of(context)?.isCurrent ?? true)) {
        _closing = true;
        final messenger = ScaffoldMessenger.of(context);
        final navigator = Navigator.of(context);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (navigator.canPop()) navigator.pop();
          messenger.showSnackBar(const SnackBar(content: Text('株が見つかりません')));
        });
      }
      return Scaffold(appBar: AppBar(), body: const SizedBox.shrink());
    }
    if (plant == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }

    final logList = logs.value ?? const <PlantLog>[];
    final photoList = ref.watch(plantPhotosProvider(widget.plantId)).value ?? const <PlantPhoto>[];
    final deletedPhotos = ref.watch(deletedPhotoCountProvider(widget.plantId)).value ?? 0;
    final story = buildStory(logList, photos: photoList);
    final healthSince = plant.health == PlantHealth.initial
        ? null
        : logList.where((l) => l.type == PlantLogType.health).firstOrNull?.occurredAt;

    final genreLabel = plant.genres.map((g) => g.label).join('・');
    final info = [
      if (plant.locationName != null) plant.locationName!,
      if (plant.potSize != null) plant.potSize!,
      if (plant.acquiredAt != null) '入手日 ${formatDate(plant.acquiredAt!)}',
    ].join('・');

    return Scaffold(
      appBar: AppBar(
        title: Text(plant.name),
        actions: [
          TextButton(key: const Key('open-visibility'), onPressed: _openVisibility, child: const Text('共有設定')),
          TextButton(key: const Key('edit'), onPressed: () => _openEdit(plant), child: const Text('編集')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(plant.variety == null ? genreLabel : '$genreLabel・${plant.variety}', style: theme.textTheme.bodyLarge),
          if (info.isNotEmpty) Text(info, style: theme.textTheme.bodyMedium),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(sharingSummary(plant.visibility), key: const Key('visibility-line'), style: theme.textTheme.bodyMedium),
          ),
          if (plant.health != PlantHealth.initial)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                healthSince == null
                    ? '健康状態:${plant.health.label}'
                    : '健康状態:${plant.health.label}(${formatDate(healthSince)}〜)',
                key: const Key('health-line'),
                style: theme.textTheme.bodyMedium,
              ),
            ),
          if (deletedPhotos > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('削除された写真があります($deletedPhotos枚)', key: const Key('deleted-photos-line'), style: theme.textTheme.bodyMedium),
            ),
          if (logList.where((l) => l.type == PlantLogType.water).firstOrNull case final water?)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '前回の水やり:${daysAgoLabel(daysSince(water.occurredAt, DateTime.now()))}(${formatDate(water.occurredAt)})',
                key: const Key('last-water'),
                style: theme.textTheme.bodyMedium,
              ),
            ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.tonal(key: const Key('log-water'), onPressed: _water, child: const Text('水をやった')),
              OutlinedButton(key: const Key('log-repot'), onPressed: () => _record(PlantLogType.repot), child: const Text('植え替え')),
              OutlinedButton(key: const Key('log-fertilize'), onPressed: () => _record(PlantLogType.fertilize), child: const Text('肥料')),
              OutlinedButton(key: const Key('log-prune'), onPressed: () => _record(PlantLogType.prune), child: const Text('剪定')),
              OutlinedButton(key: const Key('log-note'), onPressed: () => _record(PlantLogType.note), child: const Text('メモ')),
              PopupMenuButton<PlantStage>(
                key: const Key('stage-menu'),
                tooltip: '段階を記録',
                onSelected: (s) => _record(PlantLogType.stage, stage: s),
                itemBuilder: (context) => [
                  for (final s in PlantStage.values)
                    PopupMenuItem(key: Key('stage-${s.id}'), value: s, child: Text(s.label)),
                ],
                child: const _MenuLabel('段階 ▼'),
              ),
              PopupMenuButton<PlantHealth>(
                key: const Key('health-menu'),
                tooltip: '健康状態を変える',
                onSelected: _changeHealth,
                itemBuilder: (context) => [
                  for (final h in PlantHealth.values)
                    PopupMenuItem(
                      key: Key('health-${h.id}'),
                      value: h,
                      enabled: h != plant.health, // いまの状態には変えられない
                      child: Text(h == plant.health ? '${h.label}(いま)' : h.label),
                    ),
                ],
                child: const _MenuLabel('健康状態 ▼'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
          if (logs.hasError)
            const Padding(padding: EdgeInsets.all(16), child: Text('記録を読み込めませんでした'))
          else if (story.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text('まだ記録がありません。上のボタンから記録できます。', style: theme.textTheme.bodyMedium),
            )
          else
            for (final day in story) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
                child: Text('── ${formatDate(day.date)} ──', style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
              ),
              for (final entry in day.entries)
                if (entry.photo case final photo?)
                  ListTile(
                    key: Key('entry-${entry.id}'),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    // 来歴つきの写真だけに印を付ける
                    leading: photo.provenance ? const Icon(Icons.verified, key: Key('provenance-mark')) : const Icon(Icons.image_outlined),
                    title: Text(entry.title),
                    subtitle: Text(provenanceLabel(photo)),
                    onTap: () => _openPhoto(photo),
                  )
                else
                  ListTile(
                    key: Key('entry-${entry.id}'),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    title: Text(entry.title),
                    subtitle: entry.log!.note == null ? null : Text(entry.log!.note!),
                    onTap: () => _editLog(entry.log!),
                  ),
            ],
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const Key('open-download'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => DownloadScreen(initialPlantId: widget.plantId)),
              ),
              child: const Text('写真をダウンロード'),
            ),
          ),
        ],
      ),
    );
  }
}

/// メニューを開くボタンの見た目(標準の部品だけの仮のもの)。
class _MenuLabel extends StatelessWidget {
  const _MenuLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outline),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
    );
  }
}
