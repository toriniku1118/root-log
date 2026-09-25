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

  test('観葉植物全般は例つきで表示し、初期ジャンルになっている', () {
    expect(PlantGenre.foliage.labelWithExamples, '観葉植物全般(パキラ・モンステラ・ポトス等)');
    expect(PlantGenre.caudex.labelWithExamples, '塊根');
    expect(defaultPlantGenre, PlantGenre.foliage);
  });

  test('id からジャンルを引ける。知らない id は null', () {
    expect(PlantGenre.fromId('agave'), PlantGenre.agave);
    expect(PlantGenre.fromId('unknown'), isNull);
  });

  test('タグは復活チャレンジと実生', () {
    expect({for (final t in PlantTag.values) t.id: t.label}, {'rescue': '復活チャレンジ', 'seedling': '実生'});
  });
}
