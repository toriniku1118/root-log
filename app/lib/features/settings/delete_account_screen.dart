import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../download/download_screen.dart';

/// アカウント削除(SCR-12)。削除される内容を説明し、確認してから削除する(二段階)。
///
/// 削除すると、株・記録・写真、公開している内容、ログイン情報がすべて消える。本物では、サーバーの `deleteAccount` が
/// まとめて処理する(何が削除されたか分からない状態にならないため)。削除できたら、ようこそ画面に戻る。
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  bool _deleting = false;

  Future<void> _delete() async {
    if (_deleting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('本当に削除しますか?'),
        content: const Text('アカウントと、すべてのデータが消えます。元に戻せません。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('やめる')),
          TextButton(
            key: const Key('delete-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('削除する'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(plantRepositoryProvider).deleteAll();
      await ref.read(userRepositoryProvider).deleteAccount();
    } on Object {
      if (!mounted) return;
      setState(() => _deleting = false);
      messenger.showSnackBar(const SnackBar(content: Text('削除できませんでした。もう一度試してください')));
      return;
    }
    // アプリの入口が、ようこそ画面に切り替える。上に重なっている画面をすべて閉じる
    navigator.popUntil((route) => route.isFirst);
    messenger.showSnackBar(const SnackBar(content: Text('アカウントを削除しました')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('アカウントを削除')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('アカウントを削除します', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          const Text('次のものがすべて消え、元に戻せません。'),
          const SizedBox(height: 8),
          const Text('・登録した株、記録、写真'),
          const Text('・公開している内容'),
          const Text('・ログイン情報'),
          const SizedBox(height: 8),
          const Text('※ 写真は、削除するとダウンロードできません。'),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('download-first'),
            onPressed: _deleting
                ? null
                : () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const DownloadScreen())),
            child: const Text('先に写真をダウンロード'),
          ),
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('delete-account'),
            style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error, foregroundColor: theme.colorScheme.onError),
            onPressed: _deleting ? null : _delete,
            child: const Text('削除する'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('cancel'),
            onPressed: _deleting ? null : () => Navigator.of(context).pop(),
            child: const Text('やめる'),
          ),
        ],
      ),
    );
  }
}
