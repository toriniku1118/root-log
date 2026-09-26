import 'package:flutter/material.dart';

import '../../domain/plant_health.dart';
import '../../domain/plant_log.dart';
import '../../domain/plant_stage.dart';
import 'story.dart';

/// 記録の入力ダイアログの結果。[delete] が true なら、その記録を削除する(編集のときだけ)。
class LogFormResult {
  const LogFormResult({required this.occurredAt, this.note, this.delete = false});

  const LogFormResult.delete() : this(occurredAt: null, delete: true);

  /// 出来事の日時。削除のときは null。
  final DateTime? occurredAt;
  final String? note;
  final bool delete;
}

/// 記録の入力ダイアログ(日時とメモ)。[existing] を渡すと、その記録の編集(メモと日時。削除もできる)。
///
/// 入力の条件は `validatePlantLog`(権限ルールと同じ)。エラーはダイアログの中に出し、直すまで閉じない。
Future<LogFormResult?> showLogDialog(
  BuildContext context, {
  required String title,
  required PlantLogType type,
  PlantStage? stage,
  PlantHealth? health,
  PlantLog? existing,
}) {
  return showDialog<LogFormResult>(
    context: context,
    builder: (context) => _LogDialog(title: title, type: type, stage: stage, health: health, existing: existing),
  );
}

class _LogDialog extends StatefulWidget {
  const _LogDialog({required this.title, required this.type, this.stage, this.health, this.existing});

  final String title;
  final PlantLogType type;
  final PlantStage? stage;
  final PlantHealth? health;
  final PlantLog? existing;

  @override
  State<_LogDialog> createState() => _LogDialogState();
}

class _LogDialogState extends State<_LogDialog> {
  late final TextEditingController _note = TextEditingController(text: widget.existing?.note ?? '');

  /// 選んだ日付。null なら、追加は「今」、編集は元の日時のまま。
  DateTime? _picked;
  Map<PlantLogField, String> _errors = {};

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final base = _picked ?? widget.existing?.occurredAt ?? today;
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(base.year, base.month, base.day),
      firstDate: DateTime(1900),
      lastDate: today, // 今日より後は選べない
      helpText: '日付',
    );
    if (picked != null && mounted) {
      setState(() {
        _picked = picked;
        _errors = {..._errors}..remove(PlantLogField.occurredAt);
      });
    }
  }

  /// 選んだ日付から日時を決める。今日なら「今」、それ以前の日は昼の12時。
  DateTime _occurredAt(DateTime now) {
    final picked = _picked;
    if (picked == null) return widget.existing?.occurredAt ?? now;
    final today = DateTime(now.year, now.month, now.day);
    return picked == today ? now : DateTime(picked.year, picked.month, picked.day, 12);
  }

  void _submit() {
    final now = DateTime.now();
    final occurredAt = _occurredAt(now);
    final input = PlantLogInput(
      type: widget.type,
      occurredAt: occurredAt,
      note: _note.text,
      stage: widget.stage ?? widget.existing?.stage,
      health: widget.health ?? widget.existing?.health,
    );
    final errors = validatePlantLog(input, now: now);
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      return;
    }
    Navigator.of(context).pop(LogFormResult(occurredAt: occurredAt, note: input.normalized().note));
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('記録を削除しますか?'),
        content: const Text('元に戻せません。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('やめる')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('削除する')),
        ],
      ),
    );
    if (confirmed == true && mounted) Navigator.of(context).pop(const LogFormResult.delete());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final existing = widget.existing;
    final dateLabel = _picked != null
        ? formatDate(_picked!)
        : existing != null
            ? formatDate(existing.occurredAt)
            : '今';
    final isMemo = widget.type == PlantLogType.note;
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('日時:$dateLabel', key: const Key('log-date-label'))),
                TextButton(key: const Key('log-pick-date'), onPressed: _pickDate, child: const Text('日付を選ぶ')),
              ],
            ),
            if (_errors[PlantLogField.occurredAt] case final message?)
              Text(message, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
            const SizedBox(height: 8),
            TextField(
              key: const Key('log-dialog-note'),
              controller: _note,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: isMemo ? 'メモ *' : 'メモ(任意)',
                helperText: '500文字まで',
                errorText: _errors[PlantLogField.note],
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (_errors.containsKey(PlantLogField.note)) {
                  setState(() => _errors = {..._errors}..remove(PlantLogField.note));
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        if (existing != null)
          TextButton(key: const Key('log-delete'), onPressed: _confirmDelete, child: const Text('この記録を削除')),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('キャンセル')),
        FilledButton(key: const Key('log-save'), onPressed: _submit, child: Text(existing == null ? '記録する' : '保存')),
      ],
    );
  }
}
