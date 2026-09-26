import 'package:flutter_test/flutter_test.dart';
import 'package:rootlog/data/photo_saver.dart';
import 'package:rootlog/domain/plant.dart';
import 'package:rootlog/domain/plant_photo.dart';
import 'package:rootlog/features/download/download_plan.dart';

Plant plant(String id, String name) => Plant(
      id: id,
      name: name,
      genres: const {},
      tags: const {},
      visibility: const PlantVisibility.defaultVisibility(),
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

PlantPhoto photo(String id, String plantId, DateTime at, {bool provenance = true}) => PlantPhoto(
      id: id,
      plantId: plantId,
      storagePath: 'photos/$id.jpg',
      source: PhotoSource.camera,
      receivedAt: at,
      provenance: provenance,
      provenanceReason: provenance ? ProvenanceReason.ok : ProvenanceReason.gallery,
    );

void main() {
  final a = plant('a', 'モンステラ');
  final b = plant('b', 'アガベ');

  group('ファイル名の部品', () {
    test('普通の名前はそのまま', () {
      expect(sanitizeFileNamePart('モンステラ'), 'モンステラ');
      expect(sanitizeFileNamePart('Agave titanota'), 'Agave_titanota');
    });

    test('使えない文字・空白・制御文字は「_」に(連続は1つ)', () {
      expect(sanitizeFileNamePart(r'a/b\c:d*e?f"g<h>i|j'), 'a_b_c_d_e_f_g_h_i_j');
      expect(sanitizeFileNamePart('a  \t b'), 'a_b');
      expect(sanitizeFileNamePart('a\nb\u0000c'), 'a_b_c');
    });

    test('前後の「.」「_」は取る(先頭の「.」は隠しファイルになる)', () {
      expect(sanitizeFileNamePart('..hidden.'), 'hidden');
      expect(sanitizeFileNamePart(' 名前 '), '名前');
    });

    test('空(使えない文字だけ)になったら「株」', () {
      expect(sanitizeFileNamePart(''), '株');
      expect(sanitizeFileNamePart('///'), '株');
      expect(sanitizeFileNamePart('...'), '株');
    });

    test('30文字まで。絵文字を途中で切らない', () {
      expect(sanitizeFileNamePart('あ' * 40), 'あ' * 30);
      final s = sanitizeFileNamePart('🌱' * 40);
      expect(s.runes.length, 30);
      expect(s.runes.every((r) => r == 0x1F331), isTrue);
    });

    test('受信時刻の書式は 年月日-時分秒(2桁)', () {
      expect(formatFileTime(DateTime(2026, 1, 5, 7, 4, 9)), '20260105-070409');
      expect(formatFileTime(DateTime(2026, 12, 25, 23, 59, 59)), '20261225-235959');
    });
  });

  group('対象と並び', () {
    test('写真がなければ空', () {
      expect(buildDownloadPlan(plants: [a], photosByPlant: {}), isEmpty);
      expect(buildDownloadPlan(plants: [], photosByPlant: {}), isEmpty);
    });

    test('受信時刻の古い順(株をまたいで)。渡すのは新しい順', () {
      final plan = buildDownloadPlan(plants: [a, b], photosByPlant: {
        'a': [photo('a2', 'a', DateTime(2026, 9, 20)), photo('a1', 'a', DateTime(2026, 9, 1))],
        'b': [photo('b1', 'b', DateTime(2026, 9, 10))],
      });
      expect(plan.map((i) => i.photo.id), ['a1', 'b1', 'a2']);
    });

    test('同じ時刻なら、作った順(新しい順で渡されるので、後ろのほうが先)', () {
      final t = DateTime(2026, 9, 20, 10);
      final plan = buildDownloadPlan(plants: [a], photosByPlant: {
        'a': [photo('second', 'a', t), photo('first', 'a', t)],
      });
      expect(plan.map((i) => i.photo.id), ['first', 'second']);
    });

    test('来歴の有無に関係なく入る(来歴の印は付けない)', () {
      final plan = buildDownloadPlan(plants: [a], photosByPlant: {
        'a': [photo('x', 'a', DateTime(2026, 9, 2), provenance: false), photo('y', 'a', DateTime(2026, 9, 1))],
      });
      expect(plan, hasLength(2));
      for (final i in plan) {
        expect(i.fileName, isNot(contains('来歴')));
      }
    });

    test('株を選ぶと、その株だけ。null は全株。空の集合は0枚', () {
      final photos = {
        'a': [photo('a1', 'a', DateTime(2026, 9, 1))],
        'b': [photo('b1', 'b', DateTime(2026, 9, 2))],
      };
      expect(buildDownloadPlan(plants: [a, b], photosByPlant: photos, plantIds: {'b'}).map((i) => i.photo.id), ['b1']);
      expect(buildDownloadPlan(plants: [a, b], photosByPlant: photos).map((i) => i.photo.id), ['a1', 'b1']);
      expect(buildDownloadPlan(plants: [a, b], photosByPlant: photos, plantIds: {}), isEmpty);
    });

    test('外した写真は入らない', () {
      final plan = buildDownloadPlan(
        plants: [a],
        photosByPlant: {
          'a': [photo('a2', 'a', DateTime(2026, 9, 2)), photo('a1', 'a', DateTime(2026, 9, 1))],
        },
        excludedPhotoIds: {'a1'},
      );
      expect(plan.map((i) => i.photo.id), ['a2']);
    });
  });

  group('期間(受信時刻の日付で数える。両端の日を含む)', () {
    final photos = {
      'a': [
        photo('d3', 'a', DateTime(2026, 9, 3, 23, 59, 59)),
        photo('d2', 'a', DateTime(2026, 9, 2, 12)),
        photo('d1b', 'a', DateTime(2026, 9, 1, 23, 59)),
        photo('d1a', 'a', DateTime(2026, 9, 1, 0, 0)),
        photo('d0', 'a', DateTime(2026, 8, 31, 23, 59, 59)),
      ],
    };
    List<String> ids({DateTime? from, DateTime? to}) =>
        buildDownloadPlan(plants: [a], photosByPlant: photos, from: from, to: to).map((i) => i.photo.id).toList();

    test('期間なしは全部', () {
      expect(ids(), ['d0', 'd1a', 'd1b', 'd2', 'd3']);
    });

    test('開始日の0時ちょうども、終了日の23:59:59も入る。前後の日は入らない', () {
      expect(ids(from: DateTime(2026, 9, 1), to: DateTime(2026, 9, 3)), ['d1a', 'd1b', 'd2', 'd3']);
    });

    test('時刻付きの日時を渡しても、日付で数える', () {
      expect(ids(from: DateTime(2026, 9, 1, 15), to: DateTime(2026, 9, 2, 1)), ['d1a', 'd1b', 'd2']);
    });

    test('片側だけでもよい', () {
      expect(ids(from: DateTime(2026, 9, 3)), ['d3']);
      expect(ids(to: DateTime(2026, 8, 31)), ['d0']);
    });

    test('開始が終了より後なら0枚', () {
      expect(ids(from: DateTime(2026, 9, 3), to: DateTime(2026, 9, 1)), isEmpty);
    });
  });

  group('連番とファイル名', () {
    test('形は 株の名前_連番(3桁)_受信日時.jpg。連番は株ごとに受信時刻の順', () {
      final plan = buildDownloadPlan(plants: [a, b], photosByPlant: {
        'a': [photo('a2', 'a', DateTime(2026, 9, 20, 10, 3, 5)), photo('a1', 'a', DateTime(2026, 9, 1, 8))],
        'b': [photo('b1', 'b', DateTime(2026, 9, 10, 9, 30))],
      });
      expect(plan.map((i) => i.fileName), [
        'モンステラ_001_20260901-080000.jpg',
        'アガベ_001_20260910-093000.jpg',
        'モンステラ_002_20260920-100305.jpg',
      ]);
      expect(plan.map((i) => i.serial), [1, 1, 2]);
    });

    test('ファイル名の順に並べると、受信時刻の順になる(同じ株)', () {
      final photos = [
        for (var i = 12; i >= 1; i--) photo('p$i', 'a', DateTime(2026, 9, i, 10)),
      ];
      final names = buildDownloadPlan(plants: [a], photosByPlant: {'a': photos}).map((i) => i.fileName).toList();
      expect([...names]..sort(), names);
    });

    test('連番は、外した写真・期間の外の写真を数えず、対象の中で1から', () {
      final plan = buildDownloadPlan(
        plants: [a],
        photosByPlant: {
          'a': [photo('a3', 'a', DateTime(2026, 9, 3)), photo('a2', 'a', DateTime(2026, 9, 2)), photo('a1', 'a', DateTime(2026, 9, 1))],
        },
        excludedPhotoIds: {'a1'},
      );
      expect(plan.map((i) => i.serial), [1, 2]);
    });

    test('使えない文字のある名前・空の名前でも、ファイル名は作れる', () {
      final plan = buildDownloadPlan(plants: [plant('x', r'a/b:c'), plant('y', '///')], photosByPlant: {
        'x': [photo('x1', 'x', DateTime(2026, 9, 1))],
        'y': [photo('y1', 'y', DateTime(2026, 9, 2))],
      });
      expect(plan.map((i) => i.fileName), ['a_b_c_001_20260901-000000.jpg', '株_001_20260902-000000.jpg']);
    });

    test('同じ名前の株・同じ連番・同じ秒でも、ファイル名が重ならない', () {
      final t = DateTime(2026, 9, 1, 10);
      final plan = buildDownloadPlan(plants: [plant('x', '同名'), plant('y', '同名')], photosByPlant: {
        'x': [photo('x1', 'x', t)],
        'y': [photo('y1', 'y', t)],
      });
      final names = plan.map((i) => i.fileName).toList();
      expect(names.toSet(), hasLength(2));
      expect(names, ['同名_001_20260901-100000.jpg', '同名_001_20260901-100000_2.jpg']);
    });

    test('拡張子は .jpg で、ファイル名に位置情報・来歴を示す語は入らない', () {
      final plan = buildDownloadPlan(plants: [a], photosByPlant: {'a': [photo('a1', 'a', DateTime(2026, 9, 1))]});
      expect(plan.single.fileName, endsWith('.jpg'));
    });
  });

  group('動作確認用の保存先', () {
    final p = photo('a1', 'a', DateTime(2026, 9, 1));

    test('保存した名前を、順に覚える', () async {
      final saver = InMemoryPhotoSaver();
      expect(saver.isPlaceholder, isTrue);
      await saver.save(p, '1.jpg');
      await saver.save(p, '2.jpg');
      expect(saver.saved, ['1.jpg', '2.jpg']);
    });

    test('指定した枚数のあとで、指定した理由で失敗する(保存済みは残る)', () async {
      final saver = InMemoryPhotoSaver(failure: PhotoSaveFailure.permissionDenied, failAtCount: 1);
      await saver.save(p, '1.jpg');
      await expectLater(
        saver.save(p, '2.jpg'),
        throwsA(isA<PhotoSaveException>().having((e) => e.failure, 'failure', PhotoSaveFailure.permissionDenied)),
      );
      expect(saver.saved, ['1.jpg']);
    });
  });
}
