import '../../domain/plant.dart';

// 共有設定の説明文。「誰に何が見えるか」を、サーバーが実際に書き出す項目と合わせて示す。
// 書き出す項目は `firebase/functions/src/publicPlant.ts`(`buildPublicPlantDoc`)で決まっている。
// 食い違わないよう、`test/features/plants/visibility_text_test.dart` で固定してある。

/// 詳細に出す、いまの設定。例:「共有:公開(写真のみ)」「共有:非公開」。
String sharingSummary(PlantVisibility v) => v.public ? '共有:公開(${v.scope.label})' : '共有:非公開';

/// どの範囲でも、他の人には見えないもの(位置情報は取得しない)。
const alwaysHiddenNote = '置き場所・鉢の号数・購入価格・健康状態・メモの中身は、どの範囲でも見えません。';

/// この設定で、他の人(ログインしている人)に見えるもの。1行ずつ。
List<String> visibleToOthers(PlantVisibility v) {
  if (!v.public) return const ['自分だけが見られます。他の人には見えません。'];
  return [
    '名前・ジャンル・品種・タグと、写真が、ログインしている人に見えます。',
    if (v.scope == PlantScope.history || v.scope == PlantScope.source)
      '記録の種類と日付(水やり・植え替え・段階など)も見えます。メモの中身は見えません。',
    if (v.scope == PlantScope.source) '入手先も見えます。',
  ];
}

/// 共有設定の画面の、説明の文(初期の公開・公開のよさ・ステップ3の注記)。
const publishDefaultNote = '初期は、写真だけが公開されます(公開の説明を確認したあとから他の人に見えます)。';
const publishBenefitNote = '公開すると、交換・売買・レスキューのときに、相手があなたの記録を見て安心できます。他の SNS で引用して見せることもできます。';
const publishStep3Note = '※ 公開はステップ3から使えるようになります。今は設定だけ保存されます。';
