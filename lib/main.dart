import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/hinge/hinge_angle_service.dart';
import 'src/music/angle_mapper.dart';
import 'src/music/audio_service.dart';

void main() => runApp(const ProviderScope(child: FoldtomatonApp()));

class FoldtomatonApp extends StatelessWidget {
  const FoldtomatonApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Foldtomaton',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF5C7A),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0D0E13),
        useMaterial3: true,
      ),
      home: const InstrumentScreen(),
    );
  }
}

class InstrumentScreen extends ConsumerStatefulWidget {
  const InstrumentScreen({super.key});

  @override
  ConsumerState<InstrumentScreen> createState() => _InstrumentScreenState();
}

class _InstrumentScreenState extends ConsumerState<InstrumentScreen> {
  double _simulatedAngle = 135;
  double _calibrationOffset = 0;
  double _tolerance = 0.5;
  double _pinchGain = 0;
  double? _acceptedAngle;
  bool _pinching = false;

  double _applyTolerance(double raw) {
    final calibrated = (raw + _calibrationOffset).clamp(0, 180).toDouble();
    if (_acceptedAngle == null ||
        (calibrated - _acceptedAngle!).abs() >= _tolerance) {
      _acceptedAngle = calibrated;
    }
    return _acceptedAngle!;
  }

  Future<void> _syncTone(InstrumentValues values) async {
    if (!_pinching) return;
    await ref
        .read(audioServiceProvider)
        .updateTone(
          frequency: values.frequency,
          cutoff: values.filterCutoff,
          gain: _pinchGain,
        );
  }

  Future<void> _setPinching(bool active, InstrumentValues values) async {
    if (_pinching == active) return;
    _pinching = active;
    final audio = ref.read(audioServiceProvider);
    if (active) {
      await audio.startTone(
        frequency: values.frequency,
        cutoff: values.filterCutoff,
        gain: _pinchGain,
      );
    } else {
      await audio.stopTone();
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final availability = ref.watch(hingeSensorAvailableProvider);
    final hasSensor = availability.valueOrNull ?? false;
    final sensorAngle = ref.watch(hingeAngleProvider).valueOrNull;
    final rawAngle = hasSensor && sensorAngle != null
        ? sensorAngle
        : _simulatedAngle;
    final values = AngleMapper.map(_applyTolerance(rawAngle));
    unawaited(_syncTone(values));

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isPortrait = constraints.maxHeight >= constraints.maxWidth;
            return Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Expanded(
                    flex: 7,
                    child: isPortrait
                        ? _portraitInstrument(values, rawAngle, hasSensor)
                        : _landscapeInstrument(values, rawAngle, hasSensor),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    flex: 3,
                    child: _PinchMouth(
                      gain: _pinchGain,
                      sounding: _pinching,
                      onGainChanged: (gain) {
                        setState(() => _pinchGain = gain);
                        unawaited(_syncTone(values));
                      },
                      onInteractionChanged: (active) =>
                          unawaited(_setPinching(active, values)),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _portraitInstrument(
    InstrumentValues values,
    double rawAngle,
    bool hasSensor,
  ) {
    return _InstrumentShell(
      child: Column(
        children: [
          _header(hasSensor),
          Expanded(
            child: Row(
              children: [
                _verticalPitchRail(values.normalized),
                const SizedBox(width: 20),
                Expanded(child: _readout(values)),
              ],
            ),
          ),
          _controls(rawAngle, hasSensor),
        ],
      ),
    );
  }

  Widget _landscapeInstrument(
    InstrumentValues values,
    double rawAngle,
    bool hasSensor,
  ) {
    return _InstrumentShell(
      child: Row(
        children: [
          SizedBox(
            width: 122,
            child: Column(
              children: [
                _header(hasSensor, compact: true),
                Expanded(child: _verticalPitchRail(values.normalized)),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Expanded(child: _readout(values)),
          const SizedBox(width: 24),
          SizedBox(width: 250, child: _controls(rawAngle, hasSensor)),
        ],
      ),
    );
  }

  Widget _header(bool hasSensor, {bool compact = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        if (!compact)
          const Text(
            'FOLDTOMATON',
            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2),
          ),
        Chip(
          padding: compact ? EdgeInsets.zero : null,
          avatar: Icon(hasSensor ? Icons.sensors : Icons.tune, size: 16),
          label: Text(hasSensor ? 'HINGE' : 'SIM'),
        ),
      ],
    );
  }

  Widget _verticalPitchRail(double normalized) {
    const notes = [
      'C4',
      'C♯4',
      'D4',
      'D♯4',
      'E4',
      'F4',
      'F♯4',
      'G4',
      'G♯4',
      'A4',
      'A♯4',
      'B4',
      'C5',
    ];
    return SizedBox(
      width: 104,
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            Positioned(
              top: 16,
              bottom: 16,
              right: 13,
              child: Container(
                width: 14,
                decoration: BoxDecoration(
                  color: const Color(0xFF292B35),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
            for (var index = 0; index < notes.length; index++)
              Positioned(
                left: 0,
                right: 8,
                bottom: 16 + (index / 12) * (constraints.maxHeight - 32) - 8,
                child: Row(
                  children: [
                    SizedBox(
                      width: 42,
                      child: Text(
                        notes[index],
                        style: TextStyle(
                          color: index == 0 || index == 12
                              ? Colors.white
                              : Colors.white54,
                          fontSize: 11,
                          fontWeight: index == 0 || index == 12
                              ? FontWeight.w800
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        height: index == 0 || index == 12 ? 2 : 1,
                        color: index == 0 || index == 12
                            ? Colors.white54
                            : Colors.white24,
                      ),
                    ),
                  ],
                ),
              ),
            Positioned(
              right: 0,
              bottom: 6 + normalized * (constraints.maxHeight - 32),
              child: Container(
                width: 38,
                height: 20,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF5C7A),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(color: Color(0x88FF5C7A), blurRadius: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _readout(InstrumentValues values) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          values.noteName,
          style: const TextStyle(
            fontSize: 68,
            height: 0.95,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${values.angle.toStringAsFixed(1)}°',
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
        ),
        Text(
          '${values.frequency.toStringAsFixed(1)} Hz',
          style: const TextStyle(color: Colors.white60, fontSize: 16),
        ),
        const SizedBox(height: 14),
        const Text(
          '90°  C4  →  180°  C5',
          style: TextStyle(color: Colors.white54, letterSpacing: 1),
        ),
      ],
    );
  }

  Widget _controls(double rawAngle, bool hasSensor) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!hasSensor)
          Slider(
            value: _simulatedAngle,
            min: 0,
            max: 180,
            divisions: 180,
            label: '${_simulatedAngle.round()}°',
            onChanged: (value) => setState(() => _simulatedAngle = value),
          ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() {
                  _calibrationOffset = 90 - rawAngle;
                  _acceptedAngle = 90;
                }),
                child: const Text('현재 각도를 90°로 보정'),
              ),
            ),
            IconButton(
              tooltip: '보정 초기화',
              onPressed: () => setState(() {
                _calibrationOffset = 0;
                _acceptedAngle = null;
              }),
              icon: const Icon(Icons.restart_alt),
            ),
          ],
        ),
        Row(
          children: [
            const Text('흔들림 억제'),
            Expanded(
              child: Slider(
                value: _tolerance,
                min: 0,
                max: 3,
                divisions: 12,
                onChanged: (value) => setState(() => _tolerance = value),
              ),
            ),
            Text('${_tolerance.toStringAsFixed(2)}°'),
          ],
        ),
      ],
    );
  }

  @override
  void dispose() {
    unawaited(ref.read(audioServiceProvider).stopTone());
    super.dispose();
  }
}

class _InstrumentShell extends StatelessWidget {
  const _InstrumentShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF171820),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white12),
      ),
      child: Padding(padding: const EdgeInsets.all(18), child: child),
    );
  }
}

class _PinchMouth extends StatefulWidget {
  const _PinchMouth({
    required this.gain,
    required this.sounding,
    required this.onGainChanged,
    required this.onInteractionChanged,
  });

  final double gain;
  final bool sounding;
  final ValueChanged<double> onGainChanged;
  final ValueChanged<bool> onInteractionChanged;

  @override
  State<_PinchMouth> createState() => _PinchMouthState();
}

class _PinchMouthState extends State<_PinchMouth> {
  final Map<int, Offset> _pointers = {};
  double? _distance;
  bool _wasPinching = false;

  void _updatePointer(int pointer, Offset position, double width) {
    _pointers[pointer] = position;
    final pinching = _pointers.length >= 2;
    if (pinching != _wasPinching) {
      _wasPinching = pinching;
      widget.onInteractionChanged(pinching);
    }
    if (!pinching) return;

    final points = _pointers.values.take(2).toList();
    final distance = (points[0] - points[1]).distance;
    final near = 36.0;
    final far = (width * 0.75).clamp(120.0, 520.0);
    final gain = (1 - ((distance - near) / (far - near))).clamp(0.0, 1.0);
    setState(() => _distance = distance);
    widget.onGainChanged(gain);
  }

  void _removePointer(int pointer) {
    _pointers.remove(pointer);
    if (_pointers.length < 2) {
      setState(() => _distance = null);
      if (_wasPinching) {
        _wasPinching = false;
        widget.onInteractionChanged(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mouthOpen = 8 + (1 - widget.gain) * 42;
    return LayoutBuilder(
      builder: (context, constraints) => Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) => _updatePointer(
          event.pointer,
          event.localPosition,
          constraints.maxWidth,
        ),
        onPointerMove: (event) => _updatePointer(
          event.pointer,
          event.localPosition,
          constraints.maxWidth,
        ),
        onPointerUp: (event) => _removePointer(event.pointer),
        onPointerCancel: (event) => _removePointer(event.pointer),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          decoration: BoxDecoration(
            color: Color.lerp(
              const Color(0xFF211720),
              const Color(0xFFFF5C7A),
              widget.gain * 0.45,
            ),
            borderRadius: BorderRadius.circular(34),
            border: Border.all(
              color: widget.sounding ? const Color(0xFFFF8FA3) : Colors.white12,
              width: 2,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 80),
                      width: 118,
                      height: mouthOpen,
                      decoration: BoxDecoration(
                        color: const Color(0xFF09090C),
                        borderRadius: BorderRadius.circular(50),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.sounding
                          ? 'VOLUME ${(widget.gain * 100).round()}%'
                          : '두 손가락으로 집어서 연주',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    if (_distance != null)
                      Text(
                        '간격 ${_distance!.round()} px',
                        style: const TextStyle(color: Colors.white60),
                      ),
                  ],
                ),
              ),
              const Positioned(
                right: 22,
                top: 16,
                child: Icon(Icons.pinch_rounded, color: Colors.white54),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
