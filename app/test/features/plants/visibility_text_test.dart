import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rootlog/domain/plant.dart';
import 'package:rootlog/features/plants/visibility_text.dart';

PlantVisibility v(bool public, PlantScope scope) => PlantVisibility(public: public, scope: scope);

void main() {
  test('詳細に出す、いまの設定', () {
    expect(sharingSummary(v(true, PlantScope.photos)), '共有:公開(写真のみ)');
    expect(sharingSummary(v(true, PlantScope.history)), '共有:公開(履歴まで)');
    expect(sharingSummary(v(true, PlantScope.source)), '共有:公開(入手先まで)');
    expect(sharingSummary(v(false, PlantScope.photos)), '共有:非公開');
    expect(sharingSummary(v(false, PlantScope.source)), '共有:非公開'); // 非公開のときは、範囲は出ない
  });

  test('公開の範囲の表示名', () {
    expect({for (final s in PlantScope.values) s.id: s.label}, {
      'photos': '写真のみ',
      'history': '履歴まで',
      'source': '入手先まで',
    });
  });

  group('誰に何が見えるか', () {
    test('非公開:自分だけ。他の人には見えない', () {
      for (final s in PlantScope.values) {
        expect(visibleToOthers(v(false, s)), ['自分だけが見られます。他の人には見えません。']);
      }
    });

    test('写真のみ:名前・ジャンル・品種・タグと写真。記録の日付や入手先は出さない', () {
      expect(visibleToOthers(v(true, PlantScope.photos)), ['名前・ジャンル・品種・タグと、写真が、ログインしている人に見えます。']);
    });

    test('履歴まで:記録の種類と日付も。メモの中身は見えない。入手先は出さない', () {
      final lines = visibleToOthers(v(true, PlantScope.history));
      expect(lines, hasLength(2));
      expect(lines[1], contains('記録の種類と日付'));
      expect(lines[1], contains('メモの中身は見えません'));
      expect(lines.join(), isNot(contains('入手先')));
    });

    test('入手先まで:入手先も見える', () {
      final lines = visibleToOthers(v(true, PlantScope.source));
      expect(lines, hasLength(3));
      expect(lines[2], '入手先も見えます。');
    });

    test('どの範囲でも見えないもの(置き場所・鉢の号数・購入価格・健康状態・メモの中身)を示す', () {
      for (final word in ['置き場所', '鉢の号数', '購入価格', '健康状態', 'メモの中身']) {
        expect(alwaysHiddenNote, contains(word));
      }
    });
  });

  // 説明が、サーバーが実際に書き出す項目と食い違わないことの見張り。
  // 書き出す項目は firebase/functions/src/publicPlant.ts の buildPublicPlantDoc で決まる。
  group('サーバーの書き出し(publicPlant.ts)との一致', () {
    late final String source;
    setUpAll(() {
      final file = File('../firebase/functions/src/publicPlant.ts');
      expect(file.existsSync(), isTrue, reason: 'app/ から見て ../firebase/functions/src/publicPlant.ts がない');
      source = file.readAsStringSync();
    });

    test('写真のみで出す項目:名前・ジャンル・品種・タグ・写真(と来歴の印)だけ', () {
      final block = RegExp(r'const doc: Record<string, unknown> = \{(.*?)\};', dotAll: true).firstMatch(source)!.group(1)!;
      final keys = RegExp(r'^\s*(\w+):', multiLine: true).allMatches(block).map((m) => m.group(1)).toSet();
      expect(keys, {'ownerUid', 'plantId', 'name', 'genres', 'variety', 'tags', 'hasProvenance', 'photos'});
    });

    test('履歴まで:記録の種類・日付・段階。メモ(note)は書き出さない。健康状態の記録は除く', () {
      expect(source, contains("doc.logs = input.logs"));
      expect(source, contains('type: l.type, occurredAt: l.occurredAt, stage: l.stage'));
      expect(source, isNot(contains('note: l.note')));
      expect(source, contains("new Set(['health'])"));
    });

    test('入手先まで:入手先だけを足す。置き場所・鉢の号数・購入価格は書き出さない', () {
      expect(source, contains("if (scope === 'source') doc.source"));
      final code = source.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
      for (final key in ['locationName', 'potSize', 'purchasePrice']) {
        expect(code, isNot(contains('plant.$key')), reason: '$key を書き出している');
      }
    });
  });
}
