import 'package:flutter_test/flutter_test.dart';
import 'package:rootlog/features/plants/care.dart';

void main() {
  group('daysSince(暦の日付の差)', () {
    test('同じ日なら、時刻が違っても0', () {
      expect(daysSince(DateTime(2026, 9, 26, 0, 0), DateTime(2026, 9, 26, 23, 59)), 0);
      expect(daysSince(DateTime(2026, 9, 26, 23, 59), DateTime(2026, 9, 26, 23, 59)), 0);
    });

    test('日付が変われば、時間が短くても1日(23:59 → 翌日0:01)', () {
      expect(daysSince(DateTime(2026, 9, 25, 23, 59), DateTime(2026, 9, 26, 0, 1)), 1);
    });

    test('24時間たっていなくても日付が2日違えば2、24時間以上でも日付が同じなら0にはならない(前日の朝 → 今日の夜は1)', () {
      expect(daysSince(DateTime(2026, 9, 24, 23, 0), DateTime(2026, 9, 26, 1, 0)), 2);
      expect(daysSince(DateTime(2026, 9, 25, 6, 0), DateTime(2026, 9, 26, 22, 0)), 1);
    });

    test('月またぎ・年またぎ・うるう日', () {
      expect(daysSince(DateTime(2026, 8, 30), DateTime(2026, 9, 2)), 3);
      expect(daysSince(DateTime(2025, 12, 31), DateTime(2026, 1, 1)), 1);
      expect(daysSince(DateTime(2028, 2, 28), DateTime(2028, 3, 1)), 2); // 2028年は2月29日がある
      expect(daysSince(DateTime(2026, 1, 1), DateTime(2026, 9, 26)), 268);
    });

    test('未来の日時は0(通常は起きない)', () {
      expect(daysSince(DateTime(2026, 9, 27), DateTime(2026, 9, 26)), 0);
    });
  });

  group('表示の文言', () {
    test('今日・1日前・3日前', () {
      expect(daysAgoLabel(0), '今日');
      expect(daysAgoLabel(1), '1日前');
      expect(daysAgoLabel(3), '3日前');
      expect(daysAgoLabel(30), '30日前');
    });

    test('ホームの水やりの行', () {
      final now = DateTime(2026, 9, 26, 12);
      expect(waterLine(DateTime(2026, 9, 26, 8), now), '水やり:今日');
      expect(waterLine(DateTime(2026, 9, 25, 8), now), '水やり:1日前');
      expect(waterLine(DateTime(2026, 9, 23, 20), now), '水やり:3日前');
    });
  });
}
