import 'package:flutter_test/flutter_test.dart';
import 'package:foldtomaton/src/music/angle_mapper.dart';

void main() {
  test('90 to 180 degrees maps exactly to one octave', () {
    final low = AngleMapper.map(90);
    final middle = AngleMapper.map(135);
    final high = AngleMapper.map(180);

    expect(low.frequency, closeTo(261.625565, 0.001));
    expect(middle.frequency, closeTo(369.9944, 0.001));
    expect(high.frequency, closeTo(low.frequency * 2, 0.001));
    expect(low.noteName, 'C4');
    expect(high.noteName, 'C5');
  });

  test('angles outside the playable range are clamped', () {
    expect(AngleMapper.map(20).angle, 90);
    expect(AngleMapper.map(200).angle, 180);
  });
}
