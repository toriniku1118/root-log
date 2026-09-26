import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/plant_genre.dart';
import '../../domain/prefecture.dart';
import '../../domain/user_profile.dart';
import '../../providers.dart';
import 'welcome_screen.dart';

/// 年齢の選択肢(13歳未満は、利用できない案内を出すための選択肢。登録はできない)。
enum _AgeChoice { under13, teen, adult }

/// 初回の設定(サインイン後、登録するまで)。年齢の確認(SCR-02)→ はじめの設定(SCR-14)→ 好きなジャンル(SCR-03)。
///
/// 登録は、最後に1回だけ行う(権限ルールが必須項目をまとめて要求するため)。登録すると、アプリの入口(`AppGate`)が
/// ホームに切り替える。
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _step = 0;

  _AgeChoice? _age;
  final _name = TextEditingController();
  String _prefecture = ''; // '' は選ばない(未設定)
  Set<PlantGenre> _genres = {};
  bool _readExplanation = false; // 説明を読んだか(ようこそで確認していない場合だけ、ここで確認する)
  String? _nameError;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _confirmed => ref.read(publishConfirmedProvider) || _readExplanation;

  void _next() {
    if (_step == 1) {
      final errors = validateUserProfile(
        UserProfileInput(displayName: _name.text, ageBand: AgeBand.adult, publishConfirmed: true),
      );
      final error = errors[UserProfileField.displayName];
      if (error != null) {
        setState(() => _nameError = error);
        return;
      }
    }
    setState(() {
      _nameError = null;
      _step++;
    });
  }

  Future<void> _register() async {
    if (_saving) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final age = switch (_age) {
      _AgeChoice.teen => AgeBand.teen,
      _AgeChoice.adult => AgeBand.adult,
      _ => null,
    };
    try {
      await ref.read(userRepositoryProvider).createProfile(UserProfileInput(
            displayName: _name.text,
            ageBand: age,
            genres: _genres,
            prefecture: _prefecture,
            publishConfirmed: _confirmed,
          ));
      // 登録できた。アプリの入口が、ホームに切り替える
    } on UserProfileValidationException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        if (e.errors.containsKey(UserProfileField.displayName)) {
          _nameError = e.errors[UserProfileField.displayName];
          _step = 1;
        } else if (e.errors.containsKey(UserProfileField.ageBand)) {
          _step = 0;
        }
      });
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(const SnackBar(content: Text('登録できませんでした。もう一度試してください')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (_step) {
      0 => '年齢の確認',
      1 => 'はじめの設定',
      _ => '好きなジャンル',
    };
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _step > 0) setState(() => _step--);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          automaticallyImplyLeading: false,
          leading: _step == 0
              ? null
              : IconButton(
                  tooltip: '戻る',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => setState(() => _step--),
                ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: switch (_step) {
            0 => _ageStep(context),
            1 => _profileStep(context),
            _ => _genreStep(context),
          },
        ),
      ),
    );
  }

  // ---------- SCR-02 年齢の確認 ----------
  List<Widget> _ageStep(BuildContext context) {
    final theme = Theme.of(context);
    final under13 = _age == _AgeChoice.under13;
    return [
      Text('年齢を選んでください', style: theme.textTheme.titleMedium),
      const SizedBox(height: 12),
      SegmentedButton<_AgeChoice>(
        key: const Key('age-toggle'),
        showSelectedIcon: false,
        emptySelectionAllowed: true,
        segments: const [
          ButtonSegment(value: _AgeChoice.under13, label: Text('13歳未満')),
          ButtonSegment(value: _AgeChoice.teen, label: Text('13〜17歳')),
          ButtonSegment(value: _AgeChoice.adult, label: Text('18歳以上')),
        ],
        selected: {?_age},
        onSelectionChanged: (s) => setState(() => _age = s.isEmpty ? null : s.first),
      ),
      const SizedBox(height: 12),
      Text('※ 後から変更できません。売買・交換は18歳以上の方だけです。', style: theme.textTheme.bodyMedium),
      const SizedBox(height: 4),
      Text('13歳未満の方は利用できません。', style: theme.textTheme.bodyMedium),
      if (under13)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            '13歳未満の方は、このアプリを利用できません。',
            key: const Key('under13-notice'),
            style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.error),
          ),
        ),
      const SizedBox(height: 24),
      FilledButton(
        key: const Key('next'),
        onPressed: (_age == null || under13) ? null : _next,
        child: const Text('次へ'),
      ),
    ];
  }

  // ---------- SCR-14 はじめの設定 ----------
  List<Widget> _profileStep(BuildContext context) {
    final theme = Theme.of(context);
    return [
      Text('表示名と、お住まいの都道府県を入力してください。', style: theme.textTheme.bodyLarge),
      const SizedBox(height: 16),
      TextField(
        key: const Key('field-displayName'),
        controller: _name,
        decoration: InputDecoration(
          labelText: '表示名 *',
          helperText: '${ProfileLimits.displayName}文字まで。他の人に見える名前です',
          errorText: _nameError,
          border: const OutlineInputBorder(),
        ),
        onChanged: (_) {
          if (_nameError != null) setState(() => _nameError = null);
        },
      ),
      const SizedBox(height: 16),
      InputDecorator(
        decoration: const InputDecoration(
          labelText: '都道府県(任意)',
          helperText: 'イベントのお知らせに使います。位置情報は取得しません',
          border: OutlineInputBorder(),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            key: const Key('field-prefecture'),
            isExpanded: true,
            value: _prefecture,
            items: [
              const DropdownMenuItem(value: '', child: Text('選ばない')),
              for (final p in prefectures) DropdownMenuItem(value: p.code, child: Text(p.name)),
            ],
            onChanged: (v) => setState(() => _prefecture = v ?? ''),
          ),
        ),
      ),
      const SizedBox(height: 24),
      FilledButton(key: const Key('next'), onPressed: _next, child: const Text('次へ')),
    ];
  }

  // ---------- SCR-03 好きなジャンル ----------
  List<Widget> _genreStep(BuildContext context) {
    final theme = Theme.of(context);
    final needConfirm = !ref.read(publishConfirmedProvider);
    final canRegister = !_saving && (!needConfirm || _readExplanation);
    return [
      Text('好きなジャンルを選んでください(複数可)', style: theme.textTheme.titleMedium),
      const SizedBox(height: 4),
      Text('育ててみたい傾向の整理に使います。あとから変えられます。', style: theme.textTheme.bodyMedium),
      for (final g in PlantGenre.values)
        CheckboxListTile(
          key: Key('genre-${g.id}'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(g.labelWithExamples),
          value: _genres.contains(g),
          onChanged: (checked) => setState(() => _genres = checked == true ? {..._genres, g} : ({..._genres}..remove(g))),
        ),
      if (needConfirm) ...[
        const Divider(),
        Text('誰に何が見えるか', style: theme.textTheme.titleSmall),
        for (final line in publishExplanation())
          Padding(padding: const EdgeInsets.only(top: 4), child: Text('・$line')),
        CheckboxListTile(
          key: const Key('read-check'),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: const Text('上の説明を読みました'),
          value: _readExplanation,
          onChanged: (v) => setState(() => _readExplanation = v == true),
        ),
      ],
      const SizedBox(height: 16),
      FilledButton(key: const Key('next'), onPressed: canRegister ? _register : null, child: const Text('次へ')),
      const SizedBox(height: 8),
      TextButton(
        key: const Key('skip'),
        onPressed: canRegister
            ? () {
                setState(() => _genres = {});
                _register();
              }
            : null,
        child: const Text('スキップ'),
      ),
    ];
  }
}
