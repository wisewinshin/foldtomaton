import 'dart:math' as math;

class InstrumentValues {
  const InstrumentValues({
    required this.angle,
    required this.normalized,
    required this.frequency,
    required this.filterCutoff,
  });

  final double angle;
  final double normalized;
  final double frequency;
  final double filterCutoff;

  String get noteName {
    const names = [
      'C',
      'C♯',
      'D',
      'D♯',
      'E',
      'F',
      'F♯',
      'G',
      'G♯',
      'A',
      'A♯',
      'B',
    ];
    final semitone = (normalized * 12).round().clamp(0, 12);
    return '${names[semitone % 12]}${4 + semitone ~/ 12}';
  }
}

class AngleMapper {
  static const minAngle = 90.0;
  static const maxAngle = 180.0;
  static const baseFrequency = 261.625565;

  static InstrumentValues map(double angle) {
    final clamped = angle.clamp(minAngle, maxAngle).toDouble();
    final t = (clamped - minAngle) / (maxAngle - minAngle);

    return InstrumentValues(
      angle: clamped,
      normalized: t,
      frequency: (baseFrequency * math.pow(2, t)).toDouble(),
      filterCutoff: 8000,
    );
  }
}
