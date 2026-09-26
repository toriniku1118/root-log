import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/photo_saver.dart';
import '../../domain/plant.dart';
import '../../domain/plant_photo.dart';
import '../../providers.dart';
import '../plants/photo_text.dart';
import '../plants/story.dart';
import 'download_plan.dart';

/// 写真をダウンロード(SCR-13。REQ-046、FN-26)。
///
/// 期間・株・写真を選んで、対象の写真を受信時刻の古い順に1枚ずつ、端末の写真フォルダへ保存する。
/// タイムラプスや動画を自分で作るための素材(画像だけ。記録・来歴の印は付けない)。
/// 途中でやめても、保存済みの写真は残る。
class DownloadScreen extends ConsumerStatefulWidget {
  /// [initialPlantId] を渡すと、その株だけを選んだ状態で開く(株の詳細から)。
  const DownloadScreen({super.key, this.initialPlantId});

  final String? initialPlantId;

  @override
  ConsumerState<DownloadScreen> createState() => _DownloadScreenState();
}

class _DownloadScreenState extends ConsumerState<DownloadScreen> {
  DateTime? _from;
  DateTime? _to;

  /// 選んだ株。null なら全株(あとから増えた株も含む)。
  late Set<String>? _plantIds = widget.initialPlantId == null ? null : {widget.initialPlantId!};
  Set<String> _excluded = {};

  bool _saving = false;
  bool _cancelRequested = false;
  int _done = 0;
  int _total = 0;
  String? _message;
  bool _messageIsError = false;

  List<DownloadItem> _plan(List<Plant> plants, {required bool withExclusion}) {
    final photosByPlant = {
      for (final p in plants) p.id: ref.watch(plantPhotosProvider(p.id)).value ?? const <PlantPhoto>[],
    };
    return buildDownloadPlan(
      plants: plants,
      photosByPlant: photosByPlant,
      from: _from,
      to: _to,
      plantIds: _plantIds,
      excludedPhotoIds: withExclusion ? _excluded : const {},
    );
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final now = DateTime.now();
    final initial = (isFrom ? _from : _to) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(now) ? now : initial,
      firstDate: DateTime(2020),
      lastDate: now,
    );
    if (picked == null || !mounted) return;
    setState(() => isFrom ? _from = picked : _to = picked);
  }

  void _toggleAllPlants(bool all, List<Plant> plants) {
    setState(() => _plantIds = all ? null : plants.map((p) => p.id).toSet());
  }

  void _togglePlant(String id, bool on, List<Plant> plants) {
    final current = _plantIds ?? plants.map((p) => p.id).toSet();
    final next = {...current};
    on ? next.add(id) : next.remove(id);
    setState(() => _plantIds = next.length == plants.length ? null : next);
  }

  Future<void> _choosePhotos(List<DownloadItem> candidates) async {
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (context) {
        final excluded = {..._excluded};
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('写真を選ぶ'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final item in candidates)
                    CheckboxListTile(
                      key: Key('dl-photo-${item.photo.id}'),
                      value: !excluded.contains(item.photo.id),
                      onChanged: (v) => setDialogState(() => v == true ? excluded.remove(item.photo.id) : excluded.add(item.photo.id)),
                      title: Text(item.plantName),
                      subtitle: Text('${item.photo.receivedAt.year}/${formatReceivedAt(item.photo.receivedAt)}'),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('やめる')),
              TextButton(
                key: const Key('dl-photos-apply'),
                onPressed: () => Navigator.of(context).pop(excluded),
                child: const Text('決定'),
              ),
            ],
          ),
        );
      },
    );
    if (result == null || !mounted) return;
    setState(() => _excluded = result);
  }

  Future<void> _save(List<DownloadItem> plan) async {
    if (_saving || plan.isEmpty) return;
    final saver = ref.read(photoSaverProvider);
    setState(() {
      _saving = true;
      _cancelRequested = false;
      _done = 0;
      _total = plan.length;
      _message = null;
    });
    String? message;
    var isError = false;
    try {
      for (final item in plan) {
        if (_cancelRequested) break;
        await saver.save(item.photo, item.fileName);
        if (!mounted) return;
        setState(() => _done++);
      }
      message = _cancelRequested ? 'やめました($_done枚は保存済みです)' : '$_done枚を保存しました';
    } on PhotoSaveException catch (e) {
      isError = true;
      message = switch (e.failure) {
        PhotoSaveFailure.readFailed => '写真を読み込めませんでした。もう一度試してください',
        PhotoSaveFailure.permissionDenied => '保存できませんでした。写真フォルダへの保存を許可してください',
      };
      if (_done > 0) message = '$message($_done枚は保存済みです)';
    } on Object {
      isError = true;
      message = '保存できませんでした。もう一度試してください';
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _message = message;
      _messageIsError = isError;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plants = ref.watch(plantsProvider).value ?? const <Plant>[];
    final candidates = _plan(plants, withExclusion: false);
    final plan = _plan(plants, withExclusion: true);
    final allPlants = _plantIds == null;
    return Scaffold(
      appBar: AppBar(title: const Text('写真をダウンロード')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('タイムラプスや動画を自分で作るための素材として、写真を端末の写真フォルダへ保存できます。'),
          const SizedBox(height: 16),
          Text('期間', style: theme.textTheme.titleSmall),
          Row(
            children: [
              OutlinedButton(
                key: const Key('dl-from'),
                onPressed: _saving ? null : () => _pickDate(isFrom: true),
                child: Text(_from == null ? '開始日' : formatDate(_from!)),
              ),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('〜')),
              OutlinedButton(
                key: const Key('dl-to'),
                onPressed: _saving ? null : () => _pickDate(isFrom: false),
                child: Text(_to == null ? '終了日' : formatDate(_to!)),
              ),
              if (_from != null || _to != null)
                TextButton(
                  key: const Key('dl-clear-period'),
                  onPressed: _saving ? null : () => setState(() => _from = _to = null),
                  child: const Text('すべての期間'),
                ),
            ],
          ),
          if (_from == null && _to == null) const Text('初期:すべての期間', key: Key('dl-period-all')),
          const SizedBox(height: 16),
          Text('株', style: theme.textTheme.titleSmall),
          CheckboxListTile(
            key: const Key('dl-plant-all'),
            value: allPlants,
            onChanged: _saving ? null : (v) => _toggleAllPlants(v == true, plants),
            title: const Text('すべて'),
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
          ),
          for (final p in plants)
            CheckboxListTile(
              key: Key('dl-plant-${p.id}'),
              value: allPlants || _plantIds!.contains(p.id),
              onChanged: _saving ? null : (v) => _togglePlant(p.id, v == true, plants),
              title: Text(p.name),
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
            ),
          const SizedBox(height: 16),
          Text('写真', style: theme.textTheme.titleSmall),
          if (candidates.isEmpty)
            const Text('対象の写真がありません', key: Key('dl-count'))
          else
            Row(
              children: [
                Expanded(child: Text('${plan.length}枚が対象です', key: const Key('dl-count'))),
                TextButton(
                  key: const Key('dl-choose-photos'),
                  onPressed: _saving ? null : () => _choosePhotos(candidates),
                  child: const Text('写真を選ぶ'),
                ),
              ],
            ),
          if (candidates.isNotEmpty && plan.isEmpty) const Text('外した写真しかありません。「写真を選ぶ」で選び直してください'),
          const SizedBox(height: 16),
          const Text('保存先:この端末の写真フォルダ'),
          if (ref.watch(photoSaverProvider).isPlaceholder)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'この版は、保存の動作確認用です(実際には保存されません)。端末への保存は、実機の確認のときに動くようにします。',
                key: const Key('dl-placeholder-note'),
                style: theme.textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 16),
          if (_saving) ...[
            LinearProgressIndicator(value: _total == 0 ? null : _done / _total),
            const SizedBox(height: 4),
            Text('$_done / $_total枚', key: const Key('dl-progress')),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('dl-cancel'),
              onPressed: _cancelRequested ? null : () => setState(() => _cancelRequested = true),
              child: Text(_cancelRequested ? 'やめています…' : 'やめる'),
            ),
          ] else
            FilledButton(
              key: const Key('dl-save'),
              onPressed: plan.isEmpty ? null : () => _save(plan),
              child: const Text('写真フォルダに保存する'),
            ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _message!,
                key: const Key('dl-message'),
                style: TextStyle(color: _messageIsError ? theme.colorScheme.error : null),
              ),
            ),
        ],
      ),
    );
  }
}
