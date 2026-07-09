import 'package:flutter_test/flutter_test.dart';

import 'package:zone_royale/game/config.dart';
import 'package:zone_royale/game/mathx.dart';

void main() {
  test('weapons and zone config are present', () {
    expect(kWeapons.length, 5);
    expect(kZonePhases.isNotEmpty, true);
    expect(kWeapons[WeaponId.pistol]!.mag, greaterThan(0));
    expect(kWeapons[WeaponId.sniper]!.damage, greaterThan(kWeapons[WeaponId.pistol]!.damage));
  });

  test('circle/rect push resolves overlap', () {
    // circle centre sitting on a rect edge should be pushed out
    final push = circleRectPush(10, 10, 8, 12, 0, 20, 20);
    expect(push, isNotNull);
    expect(push!.x < 0, true); // pushed left, away from the rect
  });

  test('weighted picker returns a valid key', () {
    final w = weighted(kLootTable);
    expect(kLootTable.map((e) => e.key).contains(w), true);
  });
}
