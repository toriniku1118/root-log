import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/plant_repository.dart';
import '../../domain/plant.dart';
import '../../providers.dart';
import 'visibility_text.dart';

/// 株ごとの共有設定(SCR-09)。公開/非公開と、公開の範囲を選ぶ。選ぶたびに、誰に何が見えるかの説明が変わる。
///
/// 公開に関わる操作なので、必ず「誰に何が見えるか」を出す(REQ-029)。
/// ステップ1では、公開を選んでも他の人が見る画面がない。設定だけ保存する。
class PlantVisibilityScreen extends ConsumerStatefulWidget {
  const PlantVisibilityScreen({super.key, required this.plantId});

  final String plantId;

  @override
  ConsumerState<PlantVisibilityScreen> createState() => _PlantVisibilityScreenState();
}

class _PlantVisibilityScreenState extends ConsumerState<PlantVisibilityScreen> {
  /// 開いたときの設定。株が読み込まれたら決まる。
  PlantVisibility? _initial;
  bool _public = true;
  PlantScope _scope = PlantScope.photos;
  bool _saving = false;
  bool _closing = false;

  bool get _isDirty {
    final initial = _initial;
    if (initial == null) return false;
    // 非公開のときは、範囲は関係ない(保存はするが、変更とは数えない)
    return _public != initial.public || (_public && _scope != initial.scope);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref
          .read(plantRepositoryProvider)
          .setVisibility(widget.plantId, PlantVisibility(public: _public, scope: _scope));
    } on PlantNotFoundException {
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('株が見つかりません')));
      return;
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(const SnackBar(content: Text('保存できませんでした。もう一度試してください')));
      return;
    }
    navigator.pop();
    messenger.showSnackBar(const SnackBar(content: Text('共有設定を保存しました')));
  }

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('入力を破棄しますか?'),
        content: const Text('入力した内容は保存されません。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('続ける')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('破棄して戻る')),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final plants = ref.watch(plantsProvider);
    final theme = Theme.of(context);
    final plant = plants.value?.where((p) => p.id == widget.plantId).firstOrNull;

    if (plants.hasValue && plant == null) {
      // 別の場所で削除された。「株が見つかりません」を出して、閉じる
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
    if (_initial == null) {
      _initial = plant.visibility;
      _public = plant.visibility.public;
      _scope = plant.visibility.scope;
    }

    final current = PlantVisibility(public: _public, scope: _scope);
    return PopScope(
      canPop: !_isDirty || _saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
        appBar: AppBar(title: Text('共有設定  ${plant.name}')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Text('公開する範囲を選びます。', style: theme.textTheme.bodyLarge),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              key: const Key('public-toggle'),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('非公開(自分だけ)')),
                ButtonSegment(value: true, label: Text('公開')),
              ],
              selected: {_public},
              onSelectionChanged: (s) => setState(() => _public = s.first),
            ),
            const SizedBox(height: 12),
            Text('公開の範囲', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<PlantScope>(
              key: const Key('scope-toggle'),
              showSelectedIcon: false,
              segments: [for (final s in PlantScope.values) ButtonSegment(value: s, label: Text(s.label))],
              selected: {_scope},
              // 非公開のときは、範囲は選べない
              onSelectionChanged: _public ? (s) => setState(() => _scope = s.first) : null,
            ),
            const SizedBox(height: 16),
            const Divider(),
            Text('この設定で、誰に何が見えるか', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final line in visibleToOthers(current))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('・$line', key: const Key('visible-line')),
              ),
            if (_public) Text('・$alwaysHiddenNote', key: const Key('always-hidden')),
            const SizedBox(height: 16),
            Text(publishDefaultNote, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            Text(publishBenefitNote, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            Text(publishStep3Note, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 24),
            FilledButton(key: const Key('save'), onPressed: _saving ? null : _save, child: const Text('保存')),
          ],
        ),
      ),
    );
  }
}
