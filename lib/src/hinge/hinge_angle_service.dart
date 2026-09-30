import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class HingeConnectionStatus {
  const HingeConnectionStatus({
    required this.installed,
    required this.running,
    required this.authorized,
    required this.connected,
    required this.wallpaper,
    required this.continuous,
    required this.state,
    required this.reader,
    required this.parsed,
  });

  factory HingeConnectionStatus.fromMap(Map<Object?, Object?> map) {
    return HingeConnectionStatus(
      installed: map['installed'] == true,
      running: map['running'] == true,
      authorized: map['authorized'] == true,
      connected: map['connected'] == true,
      wallpaper: map['wallpaper'] == true,
      continuous: map['continuous'] == true,
      state: map['state'] as String? ?? 'UNKNOWN',
      reader: map['reader'] as String? ?? 'inactive',
      parsed: (map['parsed'] as num?)?.toInt() ?? 0,
    );
  }

  final bool installed;
  final bool running;
  final bool authorized;
  final bool connected;
  final bool wallpaper;
  final bool continuous;
  final String state;
  final String reader;
  final int parsed;
}

class HingeAngleService {
  const HingeAngleService();

  static const _events = EventChannel('foldtomaton/hinge_angle');
  static const _vibratoEvents = EventChannel('foldtomaton/tilt_vibrato');
  static const _methods = MethodChannel('foldtomaton/hinge');

  Stream<double> get angles => _events.receiveBroadcastStream().map(
    (event) => (event as num).toDouble(),
  );

  Stream<double> get vibratoCents => _vibratoEvents
      .receiveBroadcastStream()
      .map((event) => (event as num).toDouble());

  Future<bool> get isAvailable async {
    try {
      return await _methods.invokeMethod<bool>('isAvailable') ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<HingeConnectionStatus> get status async {
    final value = await _methods.invokeMapMethod<Object?, Object?>('getStatus');
    return HingeConnectionStatus.fromMap(value ?? const {});
  }

  Future<bool> requestShizukuPermission() =>
      _invokeBool('requestShizukuPermission');

  Future<bool> openShizuku() => _invokeBool('openShizuku');

  Future<bool> chooseFoldWallpaper() => _invokeBool('chooseFoldWallpaper');

  Future<bool> retryContinuousAngle() => _invokeBool('retryContinuousAngle');

  Future<bool> _invokeBool(String method) async {
    try {
      return await _methods.invokeMethod<bool>(method) ?? false;
    } on PlatformException {
      return false;
    }
  }
}

final hingeAngleServiceProvider = Provider((ref) => const HingeAngleService());

final hingeSensorAvailableProvider = FutureProvider<bool>(
  (ref) => ref.watch(hingeAngleServiceProvider).isAvailable,
);

final hingeAngleProvider = StreamProvider<double>(
  (ref) => ref.watch(hingeAngleServiceProvider).angles,
);

final tiltVibratoProvider = StreamProvider<double>(
  (ref) => ref.watch(hingeAngleServiceProvider).vibratoCents,
);

final hingeStatusProvider = FutureProvider<HingeConnectionStatus>(
  (ref) => ref.watch(hingeAngleServiceProvider).status,
);
