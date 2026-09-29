import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class HingeAngleService {
  const HingeAngleService();

  static const _events = EventChannel('foldtomaton/hinge_angle');
  static const _methods = MethodChannel('foldtomaton/hinge');

  Stream<double> get angles => _events.receiveBroadcastStream().map(
    (event) => (event as num).toDouble(),
  );

  Future<bool> get isAvailable async {
    try {
      return await _methods.invokeMethod<bool>('isAvailable') ?? false;
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
