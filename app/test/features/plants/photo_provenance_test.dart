import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rootlog/domain/plant_photo.dart';
import 'package:rootlog/features/plants/photo_text.dart';

PlantPhoto photo(ProvenanceReason reason, {DateTime? at}) => PlantPhoto(
      id: 'p',
      plantId: 'a',
      storagePath: 'photos/x.jpg',
      source: reason == ProvenanceReason.gallery ? PhotoSource.gallery : PhotoSource.camera,
      receivedAt: at ?? DateTime(2026, 9, 20, 10, 3),
      provenance: reason == ProvenanceReason.ok,
      provenanceReason: reason,
    );

void main() {
  group('来歴の表示(外部設計 3.7.1)', () {
    test('来歴つき:「この日時までに撮影された写真」+ 受信時刻', () {
      expect(provenanceLabel(photo(ProvenanceReason.ok)), 'この日時までに撮影された写真 09/20 10:03');
    });

    test('来歴にならなかった理由ごとの文言', () {
      expect(provenanceLabel(photo(ProvenanceReason.gallery)), '端末の写真のため、来歴になりません');
      expect(provenanceLabel(photo(ProvenanceReason.noCaptureTime)), '撮影時刻が読み取れないため、来歴になりません');
      expect(provenanceLabel(photo(ProvenanceReason.captureTimeMismatch)), '撮影時刻と受信時刻が離れているため、来歴になりません');
      expect(provenanceLabel(photo(ProvenanceReason.duplicate)), '同じ写真が登録済みのため、来歴になりません');
    });

    test('来歴にならない写真の文言に、「この日時までに撮影された」とは書かない(過大に書かない)', () {
      for (final r in ProvenanceReason.values.where((r) => r != ProvenanceReason.ok)) {
        expect(provenanceLabel(photo(r)), isNot(contains('撮影された写真')), reason: r.id);
      }
    });

    test('受信時刻の表示は 月/日 時:分(2桁)', () {
      expect(formatReceivedAt(DateTime(2026, 1, 5, 7, 4)), '01/05 07:04');
      expect(formatReceivedAt(DateTime(2026, 12, 25, 23, 59)), '12/25 23:59');
    });
  });

  group('サーバーの値との一致(firebase/functions/src/index.ts・storage.rules)', () {
    late final String server;
    late final String storageRules;
    setUpAll(() {
      server = File('../firebase/functions/src/index.ts').readAsStringSync();
      storageRules = File('../firebase/storage.rules').readAsStringSync();
    });

    test('来歴の理由の id が、サーバーが書く provenanceReason と同じ', () {
      final fromServer = <String>{
        ...RegExp(r"provenanceReason = '([a-z_]+)'").allMatches(server).map((m) => m.group(1)!),
        ...RegExp(r"provenanceReason: duplicateOf \? '([a-z_]+)'").allMatches(server).map((m) => m.group(1)!),
      };
      expect(ProvenanceReason.values.map((r) => r.id).toSet(), fromServer);
    });

    test('撮影元の id が、ルールとサーバーの source と同じ', () {
      final fromRules = RegExp(r"metadata\.source in \[(.*?)\]").firstMatch(storageRules)!.group(1)!;
      final ids = RegExp(r"'([a-z]+)'").allMatches(fromRules).map((m) => m.group(1)!).toList();
      expect(PhotoSource.values.map((s) => s.id).toList(), ids);
      expect(server, contains("(source !== 'camera' && source !== 'gallery')"));
    });

    test('来歴つきになるのは、理由が ok のときだけ(サーバーの判定)', () {
      expect(server, contains("provenance = true;\n          provenanceReason = 'ok';"));
      expect(ProvenanceReason.fromId('ok'), ProvenanceReason.ok);
      expect(ProvenanceReason.fromId('unknown'), isNull);
    });
  });
}
