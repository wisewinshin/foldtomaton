import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AudioService {
  const AudioService();

  static const _channel = MethodChannel('foldtomaton/audio');

  Future<void> startTone({
    required double frequency,
    required double cutoff,
    required double gain,
  }) => _call('startTone', frequency, cutoff, gain);

  Future<void> updateTone({
    required double frequency,
    required double cutoff,
    required double gain,
  }) => _call('updateTone', frequency, cutoff, gain);

  Future<void> stopTone() async {
    try {
      await _channel.invokeMethod<void>('stopTone');
    } on PlatformException {
      // The simulator UI also runs on platforms without the Android engine.
    }
  }

  Future<void> _call(
    String method,
    double frequency,
    double cutoff,
    double gain,
  ) async {
    try {
      await _channel.invokeMethod<void>(method, {
        'frequency': frequency,
        'cutoff': cutoff,
        'gain': gain,
      });
    } on PlatformException {
      // Keep the controls usable while previewing on other platforms.
    }
  }
}

final audioServiceProvider = Provider((ref) => const AudioService());
