import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 規約・ポリシーの種類。全文は、アプリに同梱した草案の写し(`app/assets/legal/`)。
/// 草案(`docs/terms-draft.md`・`docs/privacy-policy-draft.md`)と食い違わないよう、テストで突き合わせている。
enum LegalDocument {
  privacy('プライバシーポリシー', 'assets/legal/privacy.md'),
  terms('利用規約', 'assets/legal/terms.md');

  const LegalDocument(this.title, this.assetPath);

  final String title;
  final String assetPath;
}

/// 全文の読み込み。テストで差し替えられるようにしてある。
final legalTextLoaderProvider = Provider<Future<String> Function(String path)>((ref) => rootBundle.loadString);

final legalTextProvider = FutureProvider.family<String, LegalDocument>(
  (ref, doc) => ref.watch(legalTextLoaderProvider)(doc.assetPath),
);

/// プライバシーポリシー・利用規約の全文を読む画面(REQ-040。草案の段階。ストア公開前に専門家が確認する)。
class LegalScreen extends ConsumerWidget {
  const LegalScreen({super.key, required this.document});

  final LegalDocument document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = ref.watch(legalTextProvider(document));
    return Scaffold(
      appBar: AppBar(title: Text(document.title)),
      body: text.when(
        data: (t) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SelectableText(t, key: const Key('legal-text')),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('読み込めませんでした。もう一度試してください')),
      ),
    );
  }
}
