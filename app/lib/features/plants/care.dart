// 水やりの日数の計算と表示の文言。画面から切り離して、単体でテストできるようにしてある。

/// [last] から [now] まで、暦の日付で何日たったか。同じ日なら0。[last] が未来(通常はない)でも0。
int daysSince(DateTime last, DateTime now) {
  final lastDay = DateTime.utc(last.year, last.month, last.day);
  final today = DateTime.utc(now.year, now.month, now.day);
  final days = today.difference(lastDay).inDays;
  return days < 0 ? 0 : days;
}

/// 日数の表示。例:「今日」「1日前」「3日前」。
String daysAgoLabel(int days) => days == 0 ? '今日' : '$days日前';

/// ホームの各株に出す、前回の水やりの表示。例:「水やり:3日前」。
String waterLine(DateTime last, DateTime now) => '水やり:${daysAgoLabel(daysSince(last, now))}';
