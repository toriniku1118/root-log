import 'package:flutter_test/flutter_test.dart';
import 'package:rootlog/data/plant_repository.dart';
import 'package:rootlog/domain/plant.dart';
import 'package:rootlog/domain/plant_health.dart';
import 'package:rootlog/domain/plant_input.dart';
import 'package:rootlog/domain/plant_photo.dart';

void main() {
  late DateTime clockNow;
  late InMemoryPlantRepository repo;
  late String plantId;

  setUp(() async {
    clockNow = DateTime(2026, 9, 26, 12);
    var n = 0;
    repo = InMemoryPlantRepository(
      clock: () => clockNow,
      idGenerator: () => 'plant1',
      logIdGenerator: () => 'id${++n}',
    );
    plantId = (await repo.add(const PlantInput(name: 'モンステラ'))).id;
  });

  Future<bool> hasProvenance() async => (await repo.watchAll().first).single.hasProvenance;

  group('写真の記録の一覧', () {
    test('最初は空。サーバーが作った写真が、新しい順(受信時刻)に並ぶ', () async {
      expect(await repo.watchPhotos(plantId).first, isEmpty);
      final a = repo.simulateProcessedPhoto(plantId, receivedAt: DateTime(2026, 9, 10));
      final b = repo.simulateProcessedPhoto(plantId, receivedAt: DateTime(2026, 9, 20));
      final c = repo.simulateProcessedPhoto(plantId, receivedAt: DateTime(2026, 9, 20)); // 同じ時刻なら、あとのものが上
      expect((await repo.watchPhotos(plantId).first).map((p) => p.id), [c.id, b.id, a.id]);
    });

    test('来歴の理由ごとに、来歴つき・撮影元が決まる(ok だけが来歴つき)', () async {
      for (final r in ProvenanceReason.values) {
        final p = repo.simulateProcessedPhoto(plantId, reason: r);
        expect(p.provenance, r == ProvenanceReason.ok, reason: r.id);
        expect(p.provenanceReason, r);
        expect(p.source, r == ProvenanceReason.gallery ? PhotoSource.gallery : PhotoSource.camera);
      }
    });

    test('株ごとに分かれる。株がなければ空。存在しない株には作れない', () async {
      repo.simulateProcessedPhoto(plantId);
      expect(await repo.watchPhotos('nothing').first, isEmpty);
      expect(() => repo.simulateProcessedPhoto('nothing'), throwsA(isA<PlantNotFoundException>()));
    });

    test('一覧は購読した時点の内容がすぐ流れ、変更のたびに流れる', () async {
      final seen = <int>[];
      final sub = repo.watchPhotos(plantId).listen((l) => seen.add(l.length));
      await Future<void>.delayed(Duration.zero);
      repo.simulateProcessedPhoto(plantId);
      repo.simulateProcessedPhoto(plantId);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(seen, [0, 1, 2]);
    });
  });

  group('来歴の印(サーバーだけが設定。写真から数え直す)', () {
    test('来歴つきの写真があると付く。なければ付かない', () async {
      expect(await hasProvenance(), isFalse);
      repo.simulateProcessedPhoto(plantId, reason: ProvenanceReason.gallery);
      expect(await hasProvenance(), isFalse); // 来歴にならない写真だけでは付かない
      repo.simulateProcessedPhoto(plantId);
      expect(await hasProvenance(), isTrue);
    });

    test('編集(update)しても、来歴の印は消えない', () async {
      repo.simulateProcessedPhoto(plantId);
      await repo.update(plantId, const PlantInput(name: '改名'));
      expect(await hasProvenance(), isTrue);
    });

    test('共有設定・健康状態を変えても、来歴の印は変わらない', () async {
      repo.simulateProcessedPhoto(plantId);
      await repo.changeHealth(plantId, PlantHealth.bad);
      await repo.setVisibility(plantId, const PlantVisibility(public: false, scope: PlantScope.photos));
      expect(await hasProvenance(), isTrue);
    });
  });

  group('写真の削除', () {
    test('削除すると、写真が消え、「削除された写真あり」の数が増える', () async {
      final a = repo.simulateProcessedPhoto(plantId);
      final b = repo.simulateProcessedPhoto(plantId, reason: ProvenanceReason.gallery);
      expect(await repo.watchDeletedPhotoCount(plantId).first, 0);
      await repo.deletePhoto(plantId, a.id);
      expect((await repo.watchPhotos(plantId).first).map((p) => p.id), [b.id]);
      expect(await repo.watchDeletedPhotoCount(plantId).first, 1);
      await repo.deletePhoto(plantId, b.id);
      expect(await repo.watchDeletedPhotoCount(plantId).first, 2);
    });

    test('来歴つきの写真を削除すると、残りから来歴の印を数え直す', () async {
      final ok1 = repo.simulateProcessedPhoto(plantId);
      final ok2 = repo.simulateProcessedPhoto(plantId);
      await repo.deletePhoto(plantId, ok1.id);
      expect(await hasProvenance(), isTrue); // まだ来歴つきが残っている
      await repo.deletePhoto(plantId, ok2.id);
      expect(await hasProvenance(), isFalse);
    });

    test('存在しない写真は削除できない(数も増えない)', () async {
      await expectLater(repo.deletePhoto(plantId, 'nothing'), throwsA(isA<PlantPhotoNotFoundException>()));
      await expectLater(repo.deletePhoto('nothing', 'x'), throwsA(isA<PlantPhotoNotFoundException>()));
      expect(await repo.watchDeletedPhotoCount(plantId).first, 0);
    });

    test('削除の数は、購読で流れる', () async {
      final p = repo.simulateProcessedPhoto(plantId);
      final seen = <int>[];
      final sub = repo.watchDeletedPhotoCount(plantId).listen(seen.add);
      await Future<void>.delayed(Duration.zero);
      await repo.deletePhoto(plantId, p.id);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(seen, [0, 1]);
    });

    test('株を削除すると、その株の写真も、削除の記録も消える。全部削除でも同じ', () async {
      final p = repo.simulateProcessedPhoto(plantId);
      repo.simulateProcessedPhoto(plantId);
      await repo.deletePhoto(plantId, p.id);
      await repo.delete(plantId);
      expect(await repo.watchPhotos(plantId).first, isEmpty);
      expect(await repo.watchDeletedPhotoCount(plantId).first, 0);

      final again = (await repo.add(const PlantInput(name: 'b'))).id;
      repo.simulateProcessedPhoto(again);
      await repo.deleteAll();
      expect(await repo.watchPhotos(again).first, isEmpty);
    });
  });
}
