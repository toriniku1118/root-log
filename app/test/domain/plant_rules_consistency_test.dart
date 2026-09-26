// アプリの株の入力条件が、権限ルール(firebase/firestore.rules)と一致していることの確認。
// どちらか片方だけ変えると、Firestore につないだときに保存が拒否されるため、ここで気づけるようにする。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rootlog/domain/plant.dart';
import 'package:rootlog/domain/plant_genre.dart';
import 'package:rootlog/domain/plant_health.dart';
import 'package:rootlog/domain/plant_input.dart';
import 'package:rootlog/domain/plant_log.dart';
import 'package:rootlog/domain/plant_stage.dart';
import 'package:rootlog/domain/plant_tag.dart';

late final String rules;

List<String> quotedList(RegExp pattern) {
  final m = pattern.firstMatch(rules);
  expect(m, isNotNull, reason: 'ルールの中に見つからない: ${pattern.pattern}');
  return RegExp(r"'([^']*)'").allMatches(m!.group(1)!).map((e) => e.group(1)!).toList();
}

int limit(RegExp pattern) {
  final m = pattern.firstMatch(rules);
  expect(m, isNotNull, reason: 'ルールの中に見つからない: ${pattern.pattern}');
  return int.parse(m!.group(1)!);
}

void main() {
  setUpAll(() {
    final file = File('../firebase/firestore.rules');
    expect(file.existsSync(), isTrue, reason: 'app/ から見て ../firebase/firestore.rules がない');
    rules = file.readAsStringSync();
  });

  test('ジャンルの id がルールの genres() と同じ(順番も含めて)', () {
    final fromRules = quotedList(RegExp(r'function genres\(\)\s*\{\s*return\s*\[(.*?)\];', dotAll: true));
    expect(PlantGenre.values.map((g) => g.id).toList(), fromRules);
  });

  test('株に選べるジャンルの id がルールの plantGenres() と同じ(実生を除く8つ。順番も含めて)', () {
    final fromRules = quotedList(RegExp(r'function plantGenres\(\)\s*\{\s*return\s*\[(.*?)\];', dotAll: true));
    expect(PlantGenre.plantChoices.map((g) => g.id).toList(), fromRules);
  });

  test('株のジャンルの個数(1〜3)がルールと同じ', () {
    expect(PlantLimits.genresMin, limit(RegExp(r'data\(\)\.genres\.size\(\) >= (\d+)')));
    expect(PlantLimits.genresMax, limit(RegExp(r'data\(\)\.genres\.size\(\) >= \d+ && data\(\)\.genres\.size\(\) <= (\d+)')));
  });

  test('タグの id がルールの tags と同じ', () {
    final fromRules = quotedList(RegExp(r'data\(\)\.tags\.hasOnly\(\[(.*?)\]\)'));
    expect(PlantTag.values.map((t) => t.id).toSet(), fromRules.toSet());
  });

  test('健康状態の id がルールの healthStates() と同じ(順番も含めて)', () {
    final fromRules = quotedList(RegExp(r'function healthStates\(\)\s*\{\s*return\s*\[(.*?)\];', dotAll: true));
    expect(PlantHealth.values.map((h) => h.id).toList(), fromRules);
  });

  test('記録の種類の id がルールの type と同じ(順番も含めて)', () {
    final fromRules = quotedList(RegExp(r'data\(\)\.type in \[(.*?)\]'));
    expect(PlantLogType.values.map((t) => t.id).toList(), fromRules);
  });

  test('段階の id がルールの stage と同じ(順番も含めて)', () {
    final fromRules = quotedList(RegExp(r'data\(\)\.stage in\s*\[(.*?)\]', dotAll: true));
    expect(PlantStage.values.map((s) => s.id).toList(), fromRules);
  });

  test('記録のメモの上限がルールと同じ', () {
    expect(PlantLogLimits.note, limit(RegExp(r"optStr\('note', (\d+)\)")));
  });

  test('購入価格の範囲(0〜上限の整数)がルールと同じ', () {
    expect(PlantLimits.purchasePrice, limit(RegExp(r'data\(\)\.purchasePrice <= (\d+)')));
    expect(rules, contains('data().purchasePrice is int'));
    expect(rules, contains('data().purchasePrice >= 0'));
  });

  test('公開範囲(scope)の id がルールと同じ', () {
    final fromRules = quotedList(RegExp(r'visibility\.scope in \[(.*?)\]'));
    expect(PlantScope.values.map((s) => s.id).toSet(), fromRules.toSet());
  });

  test('文字数の上限がルールと同じ', () {
    expect(PlantLimits.name, limit(RegExp(r'isStr\(data\(\)\.name, 1, (\d+)\)')));
    expect(PlantLimits.variety, limit(RegExp(r"optStr\('variety', (\d+)\)")));
    expect(PlantLimits.source, limit(RegExp(r"optStr\('source', (\d+)\)")));
    expect(PlantLimits.locationName, limit(RegExp(r"optStr\('locationName', (\d+)\)")));
    expect(PlantLimits.potSize, limit(RegExp(r"optStr\('potSize', (\d+)\)")));
  });

  test('新規作成は初期公開(写真のみ)。ルールは公開の初期値を強制しない(書き出しは確認日時の後だけ)', () {
    expect(rules, isNot(contains('data().visibility.public == false')));
    const v = PlantVisibility.defaultVisibility();
    expect(v.public, isTrue);
    expect(v.scope, PlantScope.photos);
  });

  test('公開の説明を確認した日時(publishAckAt)は、サーバー時刻でだけ書け、付いたあとは変えられない', () {
    expect(rules, contains("'publishAckAt'"));
    expect(rules, contains('data().publishAckAt == request.time'));
    expect(rules, contains('data().publishAckAt == resource.data.publishAckAt'));
  });

  test('来歴の印(hasProvenance)はアプリからは持たない(ルールはサーバー専用としている)', () {
    expect(rules, contains("!('hasProvenance' in data())"));
  });
}
