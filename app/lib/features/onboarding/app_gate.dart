import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../home/home_screen.dart';
import 'onboarding_screen.dart';
import 'welcome_screen.dart';

/// アプリの入口。サインインの状態を見て、どの画面から始めるかを決める。
///
/// - サインインしていない → ようこそ(SCR-01)
/// - サインイン済み・まだ登録していない → 初回の設定(年齢 → はじめの設定 → 好きなジャンル)
/// - 登録済み → ホーム
class AppGate extends ConsumerWidget {
  const AppGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    return session.when(
      data: (s) {
        if (!s.signedIn) return const WelcomeScreen();
        if (!s.registered) return const OnboardingScreen();
        return const HomeScreen();
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => const Scaffold(body: Center(child: Text('読み込めませんでした'))),
    );
  }
}
