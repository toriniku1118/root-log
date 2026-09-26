import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/user_profile.dart';
import '../../providers.dart';
import '../download/download_screen.dart';
import 'delete_account_screen.dart';
import 'legal_screen.dart';

/// 設定(SCR-11)。通知の種類ごとのオン/オフ(保存だけ)、プライバシーポリシー・利用規約、サインアウト、アカウント削除。
///
/// 通知は、撮影通知・水やり通知のどちらも初期オフ(オプトイン)。ほかの種類(イベント・天気・反応・入荷)は、
/// それぞれのステップで足す。実際の通知は、端末の許可と、撮影・水やりの機能ができてから動く(実機。REQ-030〜032)。
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _setNotify(BuildContext context, WidgetRef ref, NotifySettings next) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(userRepositoryProvider).updateNotify(next);
    } on Object {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('保存できませんでした。もう一度試してください')));
    }
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('サインアウトしますか?'),
        content: const Text('登録した内容は残ります。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('やめる')),
          TextButton(
            key: const Key('sign-out-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('サインアウト'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final navigator = Navigator.of(context);
    await ref.read(userRepositoryProvider).signOut();
    // アプリの入口が、ようこそ画面に切り替える。上に重なっている画面をすべて閉じる
    navigator.popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profile = ref.watch(sessionProvider).value?.profile;
    final notify = profile?.notify ?? const NotifySettings();
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('通知', style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
          ),
          SwitchListTile(
            key: const Key('notify-photo'),
            title: const Text('撮影通知'),
            value: notify.photo,
            onChanged: profile == null ? null : (v) => _setNotify(context, ref, notify.copyWith(photo: v)),
          ),
          SwitchListTile(
            key: const Key('notify-water'),
            title: const Text('水やり通知'),
            value: notify.water,
            onChanged: profile == null ? null : (v) => _setNotify(context, ref, notify.copyWith(water: v)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Text(
              '通知は、希望した人だけに届きます(初期はオフ)。全種類あわせて、原則1日1回までです。'
              '実際の通知は、端末の許可と、撮影・水やりの機能ができてから動きます。',
              style: theme.textTheme.bodySmall,
            ),
          ),
          const Divider(),
          ListTile(
            key: const Key('open-download'),
            title: const Text('写真をダウンロード'),
            subtitle: const Text('期間・株・写真を選んで、端末の写真フォルダへ保存'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const DownloadScreen()),
            ),
          ),
          ListTile(
            key: const Key('open-privacy'),
            title: const Text('プライバシーポリシー'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const LegalScreen(document: LegalDocument.privacy)),
            ),
          ),
          ListTile(
            key: const Key('open-terms'),
            title: const Text('利用規約'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const LegalScreen(document: LegalDocument.terms)),
            ),
          ),
          const Divider(),
          ListTile(key: const Key('sign-out'), title: const Text('サインアウト'), onTap: () => _signOut(context, ref)),
          ListTile(
            key: const Key('open-delete-account'),
            title: Text('アカウントを削除', style: TextStyle(color: theme.colorScheme.error)),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const DeleteAccountScreen()),
            ),
          ),
        ],
      ),
    );
  }
}
