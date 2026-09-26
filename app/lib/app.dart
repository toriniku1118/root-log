import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'constants.dart';
import 'features/onboarding/app_gate.dart';

class RootLogApp extends StatelessWidget {
  const RootLogApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Colors.green;
    return MaterialApp(
      title: appName,
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark, useMaterial3: true),
      themeMode: ThemeMode.system,
      locale: const Locale('ja'),
      supportedLocales: const [Locale('ja')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const AppGate(), // サインイン → 初回の設定 → ホーム
    );
  }
}
