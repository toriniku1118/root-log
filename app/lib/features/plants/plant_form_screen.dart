import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/plant_repository.dart';
import '../../domain/plant.dart';
import '../../domain/plant_genre.dart';
import '../../domain/plant_input.dart';
import '../../domain/plant_tag.dart';
import '../../providers.dart';

/// 株を追加・編集する画面(SCR-05)。[plant] を渡すと編集(削除もここから)、なければ追加。
///
/// 追加した株は、初期公開・写真のみ(2026-09-26。オプトアウト)。編集では、共有設定・作成日時・健康状態は変えない。
/// 共有設定はここでは出さない(SCR-09)。入力の条件は `validatePlantInput`(権限ルールと同じ)。
/// エラーは項目の下に日本語で出す。
class PlantFormScreen extends ConsumerStatefulWidget {
  const PlantFormScreen({super.key, this.plant});

  /// 編集する株。null なら追加。
  final Plant? plant;

  @override
  ConsumerState<PlantFormScreen> createState() => _PlantFormScreenState();
}

class _PlantFormScreenState extends ConsumerState<PlantFormScreen> {
  final _name = TextEditingController();
  final _variety = TextEditingController();
  final _source = TextEditingController();
  final _location = TextEditingController();
  final _potSize = TextEditingController();
  final _price = TextEditingController();

  Set<PlantGenre> _genres = {defaultPlantGenre};
  Set<PlantTag> _tags = {};
  DateTime? _acquiredAt;

  Map<PlantField, String> _errors = {};
  bool _saving = false;

  /// 開いたときの入力の状態。これと違えば「変更あり」(戻るときの確認に使う)。
  late final List<Object?> _initialSnapshot;

  List<TextEditingController> get _controllers => [_name, _variety, _source, _location, _potSize, _price];

  @override
  void initState() {
    super.initState();
    final p = widget.plant;
    if (p != null) {
      _name.text = p.name;
      _variety.text = p.variety ?? '';
      _source.text = p.source ?? '';
      _location.text = p.locationName ?? '';
      _potSize.text = p.potSize ?? '';
      _price.text = p.purchasePrice?.toString() ?? '';
      _genres = {...p.genres};
      _tags = {...p.tags};
      _acquiredAt = p.acquiredAt;
    }
    _initialSnapshot = _snapshot();
    // 入力のたびに画面を作り直す(戻るときの確認が、最新の入力の有無で決まるようにする)
    for (final c in _controllers) {
      c.addListener(_onTextChanged);
    }
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  List<Object?> _snapshot() => [
        for (final c in _controllers) c.text.trim(),
        _acquiredAt,
        ([..._genres.map((g) => g.id)]..sort()).join(','),
        ([..._tags.map((t) => t.id)]..sort()).join(','),
      ];

  /// 開いたときから変えたか(戻るときの確認に使う)。
  bool get _isDirty => !listEquals(_snapshot(), _initialSnapshot);

  void _clearError(PlantField field) {
    if (_errors.containsKey(field)) setState(() => _errors = {..._errors}..remove(field));
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _acquiredAt ?? today,
      firstDate: DateTime(1900),
      lastDate: today, // 今日より後は選べない
      helpText: '入手日',
    );
    if (picked != null) {
      setState(() => _acquiredAt = picked);
      _clearError(PlantField.acquiredAt);
    }
  }

  Future<void> _save() async {
    if (_saving) return; // 二重登録の防止
    final now = DateTime.now();
    final (price, priceError) = _parsePrice(_price.text);
    final input = PlantInput(
      name: _name.text,
      genres: _genres,
      variety: _variety.text,
      acquiredAt: _acquiredAt,
      source: _source.text,
      locationName: _location.text,
      potSize: _potSize.text,
      purchasePrice: price,
      tags: _tags,
    );
    final errors = {...validatePlantInput(input, now: now)};
    if (priceError != null) errors[PlantField.purchasePrice] = priceError;
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      return;
    }

    setState(() {
      _saving = true;
      _errors = {};
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final repo = ref.read(plantRepositoryProvider);
    final editing = widget.plant;
    try {
      if (editing == null) {
        await repo.add(input);
      } else {
        await repo.update(editing.id, input);
      }
    } on PlantNotFoundException {
      // 編集中に、株がなくなっていた
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('株が見つかりません')));
      return;
    } on PlantValidationException catch (e) {
      if (!mounted) return;
      setState(() {
        _errors = e.errors;
        _saving = false;
      });
      return;
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(const SnackBar(content: Text('保存できませんでした。もう一度試してください')));
      return;
    }
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text(editing == null ? '追加しました' : '更新しました')));
  }

  Future<void> _delete() async {
    final plant = widget.plant;
    if (plant == null || _saving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('株を削除しますか?'),
        content: const Text('写真・記録もあわせて消えます。元に戻せません。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('やめる')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('削除する')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(plantRepositoryProvider).delete(plant.id);
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(const SnackBar(content: Text('削除できませんでした。もう一度試してください')));
      return;
    }
    navigator.pop();
    messenger.showSnackBar(const SnackBar(content: Text('削除しました')));
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
    final theme = Theme.of(context);
    final plants = ref.watch(plantsProvider).value ?? const [];
    final locations = ({for (final p in plants) ?p.locationName}.toList())..sort();

    return PopScope(
      canPop: !_isDirty || _saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(widget.plant == null ? '株を追加' : '株を編集')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (widget.plant == null) ...[
              Text(
                '初期設定では、この株の写真だけが公開されます(公開の説明を確認したあとから、他の人に見えます)。'
                '株ごとに、いつでも非公開にできます。入手先・置き場所・購入価格は公開されません。',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              key: const Key('field-name'),
              controller: _name,
              decoration: InputDecoration(
                labelText: '名前 *',
                helperText: '50文字まで',
                errorText: _errors[PlantField.name],
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => _clearError(PlantField.name),
            ),
            const SizedBox(height: 16),
            Text('ジャンル *(1〜3個)', style: theme.textTheme.titleSmall),
            for (final g in PlantGenre.plantChoices)
              CheckboxListTile(
                key: Key('genre-${g.id}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(g.labelWithExamples),
                value: _genres.contains(g),
                onChanged: (checked) {
                  setState(() => _genres = checked == true ? {..._genres, g} : ({..._genres}..remove(g)));
                  _clearError(PlantField.genres);
                },
              ),
            if (_errors[PlantField.genres] case final message?)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 4),
                child: Text(message, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
              ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('field-variety'),
              controller: _variety,
              decoration: InputDecoration(
                labelText: '品種',
                helperText: '80文字まで',
                errorText: _errors[PlantField.variety],
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => _clearError(PlantField.variety),
            ),
            const SizedBox(height: 16),
            _AcquiredAtField(
              value: _acquiredAt,
              error: _errors[PlantField.acquiredAt],
              onPick: _pickDate,
              onClear: () => setState(() => _acquiredAt = null),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('field-source'),
              controller: _source,
              decoration: InputDecoration(
                labelText: '入手先',
                helperText: '100文字まで。非公開です(自分だけが見られます)',
                errorText: _errors[PlantField.source],
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => _clearError(PlantField.source),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('field-location'),
              controller: _location,
              decoration: InputDecoration(
                labelText: '置き場所',
                helperText: '30文字まで。名前だけ。住所は入れないでください',
                errorText: _errors[PlantField.locationName],
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => _clearError(PlantField.locationName),
            ),
            if (locations.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final l in locations)
                      ActionChip(
                        key: Key('location-$l'),
                        label: Text(l),
                        onPressed: () {
                          _location.text = l; // 入力欄の変更で画面が作り直される
                          _clearError(PlantField.locationName);
                        },
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('field-potSize'),
              controller: _potSize,
              decoration: InputDecoration(
                labelText: '鉢の号数',
                helperText: '10文字まで(例:5号)',
                errorText: _errors[PlantField.potSize],
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => _clearError(PlantField.potSize),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('field-price'),
              controller: _price,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: '購入価格(任意)',
                suffixText: '円',
                helperText: '自分だけが見られます。公開されません',
                errorText: _errors[PlantField.purchasePrice],
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => _clearError(PlantField.purchasePrice),
            ),
            const SizedBox(height: 16),
            Text('タグ', style: theme.textTheme.titleSmall),
            for (final t in PlantTag.values)
              CheckboxListTile(
                key: Key('tag-${t.id}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(t.label),
                value: _tags.contains(t),
                onChanged: (checked) => setState(() => _tags = checked == true ? {..._tags, t} : ({..._tags}..remove(t))),
              ),
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('save'),
              onPressed: _saving ? null : _save,
              child: const Text('保存'),
            ),
            if (widget.plant != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                key: const Key('delete'),
                onPressed: _saving ? null : _delete,
                child: const Text('この株を削除'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AcquiredAtField extends StatelessWidget {
  const _AcquiredAtField({required this.value, required this.error, required this.onPick, required this.onClear});

  final DateTime? value;
  final String? error;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InputDecorator(
          decoration: InputDecoration(
            labelText: '入手日',
            helperText: '今日以前の日付',
            errorText: error,
            border: const OutlineInputBorder(),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  d == null ? '未設定' : '${d.year}/${d.month}/${d.day}',
                  style: theme.textTheme.bodyLarge,
                ),
              ),
              if (d != null) IconButton(key: const Key('clear-date'), tooltip: '入手日を消す', onPressed: onClear, icon: const Icon(Icons.clear)),
              TextButton(key: const Key('pick-date'), onPressed: onPick, child: const Text('日付を選ぶ')),
            ],
          ),
        ),
      ],
    );
  }
}

/// 購入価格の入力(文字)を、整数に直す。空欄は未設定(null)。全角の数字とカンマは受け付ける。
/// 整数でなければエラーの文言を返す。範囲(0〜上限)は `validatePlantInput` が見る。
(int?, String?) _parsePrice(String text) {
  final t = _toHalfWidthDigits(text.trim()).replaceAll(',', '').replaceAll('、', '');
  if (t.isEmpty) return (null, null);
  final n = int.tryParse(t);
  if (n == null) return (null, '購入価格は0以上の整数で入力してください');
  return (n, null);
}

String _toHalfWidthDigits(String s) => String.fromCharCodes(
      s.runes.map((r) => (r >= 0xFF10 && r <= 0xFF19) ? r - 0xFF10 + 0x30 : r),
    );
