import 'package:flutter_test/flutter_test.dart';
import 'package:rootlog/domain/plant_health.dart';

void main() {
  test('健康状態は5つで、id と日本語の表示名が決めたとおり', () {
    expect({for (final h in PlantHealth.values) h.id: h.label}, {
      'initial': '初期',
      'good': '元気',
      'watch': '要観察',
      'bad': '不調',
      'recovering': '復活中',
    });
  });

  test('新しい株の初期値は「初期」', () {
    expect(defaultPlantHealth, PlantHealth.initial);
  });

  test('id から引ける。知らない id は null', () {
    expect(PlantHealth.fromId('bad'), PlantHealth.bad);
    expect(PlantHealth.fromId('unknown'), isNull);
  });
}
