import 'package:flutter/material.dart';

/// 株を追加する画面(仮)。入力フォームは別の issue(#17)で作る。
class AddPlantScreen extends StatelessWidget {
  const AddPlantScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('株を追加')),
      body: const Center(child: Text('準備中')),
    );
  }
}
