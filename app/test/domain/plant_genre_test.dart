import 'package:flutter_test/flutter_test.dart';
import 'package:rootlog/domain/plant_genre.dart';
import 'package:rootlog/domain/plant_tag.dart';

void main() {
  test('ジャンルは9種で、id と日本語の表示名が決め事どおり', () {
    expect({for (final g in PlantGenre.values) g.id: g.label}, {
      'foliage': '観葉植物全般',
      'caudex': '塊根',
      'agave': 'アガベ',
      'succulent_cactus': '多肉/サボテン',
      'platycerium': 'ビカクシダ',
      'aroid': 'アロイド',
      'rare': '珍奇植物',
      'seedling': '実生',
      'other': 'その他',
    });
  });

  test('観葉植物全般とアロイドは例つきで表示する。モンステラ・ポトスはアロイド。初期ジャンルは観葉植物全般', () {
    expect(PlantGenre.foliage.labelWithExamples, '観葉植物全般(パキラ・ゴムの木・ガジュマル・サンスベリア等)');
    expect(PlantGenre.aroid.labelWithExamples, 'アロイド(モンステラ・ポトス・アンスリウム・アロカシア等)');
    expect(PlantGenre.caudex.labelWithExamples, '塊根');
    expect(defaultPlantGenre, PlantGenre.foliage);
  });

  test('株に選べるのは、実生を除く8つ(実生はタグで表す)', () {
    expect(PlantGenre.plantChoices.length, 8);
    expect(PlantGenre.plantChoices, isNot(contains(PlantGenre.seedling)));
    expect(PlantGenre.plantChoices.first, PlantGenre.foliage);
  });

  test('id からジャンルを引ける。知らない id は null', () {
    expect(PlantGenre.fromId('agave'), PlantGenre.agave);
    expect(PlantGenre.fromId('unknown'), isNull);
  });

  test('タグは復活チャレンジと実生', () {
    expect({for (final t in PlantTag.values) t.id: t.label}, {'rescue': '復活チャレンジ', 'seedling': '実生'});
  });
}
