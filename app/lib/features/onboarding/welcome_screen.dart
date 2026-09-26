import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../constants.dart';
import '../../data/user_repository.dart';
import '../../domain/plant.dart';
import '../../providers.dart';
import '../plants/visibility_text.dart';

/// 公開の説明を、初回に確認したか(REQ-049)。ようこそ画面のチェックで true になる。
/// 登録(`createProfile`)のとき、確認の日時を保存するために使う。
class PublishConfirmedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void confirm() => state = true;
}

final publishConfirmedProvider = NotifierProvider<PublishConfirmedNotifier, bool>(PublishConfirmedNotifier.new);

/// 初回に見せる、公開の説明(誰に何が見えるか)。初期の共有設定(公開・写真のみ)のとおりに書く。
List<String> publishExplanation() => [
      '初期設定では、あなたの株の写真だけが公開されます。',
      ...visibleToOthers(const PlantVisibility.defaultVisibility()),
      '位置情報は取得しません。写真の位置情報(EXIF)は削除します。',
      alwaysHiddenNote,
      '株ごとに、いつでも非公開にできます。',
    ];

/// ようこそ(SCR-01)。アプリの説明と、公開の説明。説明を読んだことを確認してから、サインインする(REQ-049)。
///
/// サインインは、Firebase 接続前は仮(Apple・Google の区別だけ)。
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  bool _read = false;
  bool _busy = false;

  Future<void> _signIn(SignInProvider provider) async {
    if (!_read || _busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      ref.read(publishConfirmedProvider.notifier).confirm();
      await ref.read(userRepositoryProvider).signIn(provider);
    } on Object {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(const SnackBar(content: Text('サインインできませんでした。もう一度試してください')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSignIn = _read && !_busy;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 24),
            Text(appName, style: theme.textTheme.headlineMedium, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              '育てた記録を残して、見せ合い、交換や相談につなげるアプリです。',
              style: theme.textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Text('誰に何が見えるか', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final line in publishExplanation())
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('・$line', key: const Key('explain-line')),
              ),
            const SizedBox(height: 8),
            CheckboxListTile(
              key: const Key('read-check'),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: const Text('上の説明を読みました'),
              value: _read,
              onChanged: (v) => setState(() => _read = v == true),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('sign-in-apple'),
              onPressed: canSignIn ? () => _signIn(SignInProvider.apple) : null,
              child: const Text('Apple でサインイン'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              key: const Key('sign-in-google'),
              onPressed: canSignIn ? () => _signIn(SignInProvider.google) : null,
              child: const Text('Google でサインイン'),
            ),
            const SizedBox(height: 16),
            Text(
              '※ 開発中の仮のサインインです(Firebase につなぐと、本物のサインインになります)。',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
