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
  InstrumentValues? _latestValues;
  bool _toneUpdatePending = false;
  bool _toneUpdateDirty = false;
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    _statusTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) ref.invalidate(hingeStatusProvider);
    });
  }

  double _applyTolerance(double raw) {
    final calibrated = (raw + _calibrationOffset).clamp(0, 180).toDouble();
    if (_acceptedAngle == null ||
        (calibrated - _acceptedAngle!).abs() >= _tolerance) {
      _acceptedAngle = calibrated;
    }
    return _acceptedAngle!;
  }

  void _queueToneUpdate() {
    if (!_pinching || _latestValues == null) return;
    _toneUpdateDirty = true;
    if (_toneUpdatePending) return;
    _toneUpdatePending = true;
    unawaited(_flushToneUpdates());
  }

  Future<void> _flushToneUpdates() async {
    while (mounted && _pinching && _toneUpdateDirty) {
      _toneUpdateDirty = false;
      final values = _latestValues!;
      final gain = _pinchGain;
      await ref
          .read(audioServiceProvider)
          .updateTone(
            frequency: values.frequency,
            cutoff: values.filterCutoff,
            gain: gain,
          );
    }
    _toneUpdatePending = false;
    if (mounted && _pinching && _toneUpdateDirty) _queueToneUpdate();
  }

  Future<void> _setPinching(bool active) async {
    if (_pinching == active) return;
    _pinching = active;
    final audio = ref.read(audioServiceProvider);
    if (active) {
      final values = _latestValues;
      if (values == null) return;
      await audio.startTone(
        frequency: values.frequency,
        cutoff: values.filterCutoff,
        gain: _pinchGain,
      );
      _queueToneUpdate();
    } else {
      _toneUpdateDirty = false;
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
    final vibratoCents = ref.watch(tiltVibratoProvider).valueOrNull ?? 0;
    final pitchChanged =
        _latestValues == null ||
        (_latestValues!.frequency - values.frequency).abs() > 0.001 ||
        (_latestValues!.filterCutoff - values.filterCutoff).abs() > 0.001;
    _latestValues = values;
    if (pitchChanged) _queueToneUpdate();

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
                        ? _portraitInstrument(
                            values,
                            rawAngle,
                            hasSensor,
                            vibratoCents,
                          )
                        : _landscapeInstrument(
                            values,
                            rawAngle,
                            hasSensor,
                            vibratoCents,
                          ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    flex: 3,
                    child: _PinchMouth(
                      gain: _pinchGain,
                      sounding: _pinching,
                      onGainChanged: (gain) {
                        setState(() => _pinchGain = gain);
                        _queueToneUpdate();
                      },
                      onInteractionChanged: (active) =>
                          unawaited(_setPinching(active)),
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
    double vibratoCents,
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
                Expanded(child: _readout(values, vibratoCents)),
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
    double vibratoCents,
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
          Expanded(child: _readout(values, vibratoCents)),
          const SizedBox(width: 24),
          SizedBox(width: 250, child: _controls(rawAngle, hasSensor)),
        ],
      ),
    );
  }

  Widget _header(bool hasSensor, {bool compact = false}) {
    final hingeStatus = ref.watch(hingeStatusProvider).valueOrNull;
    final continuous = hingeStatus?.continuous == true;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        if (!compact)
          const Text(
            'FOLDTOMATON',
            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2),
          ),
        ActionChip(
          padding: compact ? EdgeInsets.zero : null,
          avatar: Icon(
            continuous
                ? Icons.graphic_eq
                : hasSensor
                ? Icons.sensors
                : Icons.tune,
            size: 16,
          ),
          label: Text(
            continuous
                ? 'CONTINUOUS'
                : hasSensor
                ? 'HINGE'
                : 'SIM',
          ),
          onPressed: _showHingeSetup,
        ),
      ],
    );
  }

  Future<void> _showHingeSetup() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Consumer(
        builder: (context, dialogRef, _) {
          final asyncStatus = dialogRef.watch(hingeStatusProvider);
          final status = asyncStatus.valueOrNull;
          final service = dialogRef.read(hingeAngleServiceProvider);

          String message;
          Future<bool> Function()? action;
          String actionLabel;
          if (status == null) {
            message = '연속 각도 환경을 확인하고 있습니다.';
            actionLabel = '확인 중';
          } else if (!status.installed) {
            message = '연속 각도에는 Shizuku가 필요합니다. 설치한 뒤 앱에서 실행 상태를 만들어 주세요.';
            action = service.openShizuku;
            actionLabel = 'Shizuku 설치';
          } else if (!status.running) {
            message =
                'Shizuku가 설치되어 있지만 실행 중이 아닙니다. 무선 디버깅 또는 PC로 Shizuku를 시작하세요.';
            action = service.openShizuku;
            actionLabel = 'Shizuku 열기';
          } else if (!status.authorized) {
            message = 'Foldtomaton이 Shizuku user-service를 사용할 수 있도록 권한을 허용하세요.';
            action = service.requestShizukuPermission;
            actionLabel = '권한 허용';
          } else if (!status.wallpaper) {
            message =
                '삼성 Fold Interactive 라이브 배경화면을 홈 배경화면으로 지정해야 실제 각도를 읽을 수 있습니다.';
            action = service.chooseFoldWallpaper;
            actionLabel = '배경화면 선택';
          } else if (!status.continuous) {
            message =
                '연결은 준비됐지만 아직 연속 각도 이벤트가 없습니다. 다시 연결한 뒤 폰을 움직여 보세요.\nReader: ${status.reader}';
            action = service.retryContinuousAngle;
            actionLabel = '다시 연결';
          } else {
            message = '연속 힌지 각도를 받고 있습니다.\n수신 이벤트: ${status.parsed}';
            action = service.retryContinuousAngle;
            actionLabel = '연결 확인';
          }

          return AlertDialog(
            title: const Text('연속 힌지 각도'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('닫기'),
              ),
              FilledButton(
                onPressed: action == null
                    ? null
                    : () async {
                        await action!();
                        await Future<void>.delayed(
                          const Duration(milliseconds: 500),
                        );
                        // Opening Shizuku or the wallpaper picker can dispose
                        // this dialog while the platform call is still pending.
                        if (mounted) ref.invalidate(hingeStatusProvider);
                      },
                child: Text(actionLabel),
              ),
            ],
          );
        },
      ),
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

  Widget _readout(InstrumentValues values, double vibratoCents) {
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
        const SizedBox(height: 3),
        Text(
          'TILT VIBRATO ${vibratoCents >= 0 ? '+' : ''}${vibratoCents.toStringAsFixed(1)} ct',
          style: TextStyle(
            color: vibratoCents.abs() >= 0.4
                ? const Color(0xFFFF8FA3)
                : Colors.white38,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.7,
          ),
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
    _statusTimer?.cancel();
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
    if (!pinching) {
      if (_wasPinching) {
        _wasPinching = false;
        widget.onInteractionChanged(false);
      }
      return;
    }

    final points = _pointers.values.take(2).toList();
    final distance = (points[0] - points[1]).distance;
    final near = 36.0;
    final far = (width * 0.75).clamp(120.0, 520.0);
    final gain = (1 - ((distance - near) / (far - near))).clamp(0.0, 1.0);
    setState(() => _distance = distance);
    // Start playback only after the first valid two-finger gain is available.
    widget.onGainChanged(gain);
    if (!_wasPinching) {
      _wasPinching = true;
      widget.onInteractionChanged(true);
    }
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
