import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/date_utils.dart';
import '../../shared/widgets/app_nav.dart';
import '../../shared/widgets/gradient_scaffold.dart';
import '../../shared/widgets/soft_card.dart';
import '../../shared/widgets/states.dart';

/// Phases of a 4-4-6 box-style breath. Simple, well-known, and gentle.
enum BreathPhase { inhale, hold, exhale }

class BreathingScreen extends ConsumerStatefulWidget {
  const BreathingScreen({super.key});

  @override
  ConsumerState<BreathingScreen> createState() => _BreathingScreenState();
}

class _BreathingScreenState extends ConsumerState<BreathingScreen>
    with SingleTickerProviderStateMixin {
  static const int inhaleSeconds = 4;
  static const int holdSeconds = 4;
  static const int exhaleSeconds = 6;

  int _sessionMinutes = 2;
  bool _sound = false;

  bool _running = false;
  DateTime? _startedAt;
  int _elapsedSeconds = 0;
  Timer? _ticker;
  Timer? _phaseTimer;
  BreathPhase _phase = BreathPhase.inhale;
  int _phaseRemaining = inhaleSeconds;
  int _cycles = 0;

  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(seconds: inhaleSeconds),
  );

  int get _totalSeconds => _sessionMinutes * 60;

  @override
  void dispose() {
    _ticker?.cancel();
    _phaseTimer?.cancel();
    _breath.dispose();
    super.dispose();
  }

  void _start() {
    setState(() {
      _running = true;
      _startedAt ??= DateTime.now();
      _phase = BreathPhase.inhale;
      _phaseRemaining = inhaleSeconds;
    });
    _runPhase(BreathPhase.inhale);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _elapsedSeconds++;
        _phaseRemaining = math.max(0, _phaseRemaining - 1);
      });
      if (_elapsedSeconds >= _totalSeconds) {
        _complete();
      }
    });
    if (_sound) _vibrate();
  }

  void _runPhase(BreathPhase phase) {
    _phaseTimer?.cancel();
    _breath.duration = Duration(
      seconds: switch (phase) {
        BreathPhase.inhale => inhaleSeconds,
        BreathPhase.hold => holdSeconds,
        BreathPhase.exhale => exhaleSeconds,
      },
    );
    if (phase == BreathPhase.inhale) {
      _breath.forward(from: 0);
    } else if (phase == BreathPhase.exhale) {
      _breath.reverse(from: 1);
    }
    if (phase != BreathPhase.hold) {
      _phaseTimer = Timer(
        Duration(seconds: switch (phase) {
          BreathPhase.inhale => inhaleSeconds,
          BreathPhase.exhale => exhaleSeconds,
          BreathPhase.hold => holdSeconds,
        }),
        () {
          if (!mounted || !_running) return;
          setState(() {
            switch (phase) {
              case BreathPhase.inhale:
                _phase = BreathPhase.hold;
                _phaseRemaining = holdSeconds;
              case BreathPhase.hold:
                _phase = BreathPhase.exhale;
                _phaseRemaining = exhaleSeconds;
              case BreathPhase.exhale:
                _phase = BreathPhase.inhale;
                _phaseRemaining = inhaleSeconds;
                _cycles++;
            }
          });
          if (_sound) _vibrate();
          _runPhase(_phase);
        },
      );
    } else {
      _phaseTimer = Timer(
        const Duration(seconds: holdSeconds),
        () {
          if (!mounted || !_running) return;
          setState(() {
            _phase = BreathPhase.exhale;
            _phaseRemaining = exhaleSeconds;
          });
          if (_sound) _vibrate();
          _runPhase(BreathPhase.exhale);
        },
      );
    }
  }

  void _vibrate() {
    // Haptics are a permission-free, non-audio cue that works in silent mode.
    switch (_phase) {
      case BreathPhase.inhale:
        HapticFeedbackLight.tap();
      case BreathPhase.hold:
        HapticFeedbackLight.tap();
      case BreathPhase.exhale:
        HapticFeedbackLight.tap();
    }
  }

  void _pause() {
    setState(() => _running = false);
    _ticker?.cancel();
    _phaseTimer?.cancel();
    _breath.stop();
  }

  Future<void> _complete() async {
    _ticker?.cancel();
    _phaseTimer?.cancel();
    _breath.stop();
    setState(() => _running = false);
    final profile = await ref.read(profileProvider.future);
    await ref.read(mindRepositoryProvider).saveBreathing(
          userId: profile.id,
          durationSeconds: _elapsedSeconds,
          completed: true,
          pattern: '$inhaleSeconds-$holdSeconds-$exhaleSeconds',
          startedAt: _startedAt,
        );
    ref.invalidate(todayBreathingProvider);
    ref.invalidate(dataRevisionProvider);
    if (!mounted) return;
    showAkashaToast(
      context,
      'You gave yourself $_sessionMinutes minutes of calm ♡',
      icon: Icons.spa_rounded,
      color: AppColors.mint,
    );
    setState(() {
      _elapsedSeconds = 0;
      _cycles = 0;
      _startedAt = null;
      _phase = BreathPhase.inhale;
      _phaseRemaining = inhaleSeconds;
    });
  }

  String get _phaseLabel => switch (_phase) {
        BreathPhase.inhale => 'Breathe in',
        BreathPhase.hold => 'Hold',
        BreathPhase.exhale => 'Breathe out',
      };

  @override
  Widget build(BuildContext context) {
    final progress = _totalSeconds == 0 ? 0.0 : _elapsedSeconds / _totalSeconds;

    return GradientScaffold(
      colors: const [
        AppColors.breathSky,
        AppColors.breathLilac,
        AppColors.breathRose,
      ],
      body: Column(
        children: [
          const AkashaHeader(
            title: 'Breathe',
            subtitle: 'Four in · four hold · six out',
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
              children: [
                const SizedBox(height: 8),
                Center(
                  child: SizedBox(
                    height: 300,
                    width: 300,
                    child: AnimatedBuilder(
                      animation: _breath,
                      builder: (context, _) {
                        final t = Curves.easeInOut.transform(_breath.value);
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            // Outer glow
                            Container(
                              width: 240 + 60 * t,
                              height: 240 + 60 * t,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    AppColors.skyBlue.withValues(alpha: .22 + .12 * t),
                                    AppColors.skyBlue.withValues(alpha: 0),
                                  ],
                                ),
                              ),
                            ),
                            // Ring
                            Container(
                              width: 170 + 70 * t,
                              height: 170 + 70 * t,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color.lerp(AppColors.lavender, AppColors.skyBlue, t)!,
                                    Color.lerp(AppColors.skyBlue, AppColors.primaryPink, t)!,
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.skyBlue.withValues(alpha: .3),
                                    blurRadius: 30,
                                    offset: const Offset(0, 12),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Container(
                                  width: 118 + 30 * t,
                                  height: 118 + 30 * t,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppColors.white.withValues(alpha: .92),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        _running ? '$_phaseRemaining' : 'Ready',
                                        style: TextStyle(
                                          fontSize: _running ? 34 : 20,
                                          height: 1,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: -1,
                                          color: AppColors.darkText,
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        _running ? _phaseLabel : 'when you are',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                          color: AppColors.secondaryText,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    _running
                        ? 'Session ${(progress * 100).round()}% · $_cycles rounds'
                        : 'Let your shoulders drop. You have nothing to prove here.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.secondaryText,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 54,
                        child: ElevatedButton.icon(
                          onPressed: _running ? _pause : _start,
                          icon: Icon(
                            _running ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            size: 20,
                          ),
                          label: Text(_running ? 'Pause' : (_elapsedSeconds > 0 ? 'Resume' : 'Begin')),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.purple,
                            shape: RoundedRectangleBorder(
                              borderRadius: AppRadius.lgR,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: 54,
                      width: 54,
                      child: OutlinedButton(
                        onPressed: () async {
                          _pause();
                          // Capture the values before the await: the user can
                          // leave the screen while the write is in flight.
                          final seconds = _elapsedSeconds;
                          final startedAt = _startedAt;
                          if (seconds > 30 && startedAt != null) {
                            final profile =
                                await ref.read(profileProvider.future);
                            await ref.read(mindRepositoryProvider).saveBreathing(
                                  userId: profile.id,
                                  durationSeconds: seconds,
                                  completed: false,
                                  startedAt: startedAt,
                                );
                            ref.invalidate(todayBreathingProvider);
                            ref.invalidate(dataRevisionProvider);
                          }
                          if (!mounted) return;
                          setState(() {
                            _elapsedSeconds = 0;
                            _cycles = 0;
                            _startedAt = null;
                          });
                        },
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                          minimumSize: const Size(54, 54),
                        ),
                        child: const Icon(Icons.stop_rounded, size: 20),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                SoftCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Session length',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 10),
                      Row(
                        children: [1, 2, 3, 5].map((minutes) {
                          final selected = _sessionMinutes == minutes;
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 7),
                              child: GestureDetector(
                                onTap: _running
                                    ? null
                                    : () => setState(() => _sessionMinutes = minutes),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 11),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? AppColors.softBlue
                                        : AppColors.cardMuted,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: selected
                                          ? AppColors.skyBlue
                                          : AppColors.hairline,
                                    ),
                                  ),
                                  child: Text(
                                    '$minutes min',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: selected
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: selected
                                          ? AppColors.info
                                          : AppColors.darkText,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        value: _sound,
                        activeTrackColor: AppColors.primaryPink,
                        onChanged: (v) => setState(() => _sound = v),
                        title: const Text(
                          'Gentle cues',
                          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                        ),
                        subtitle: const Text(
                          'A soft haptic at each phase change. Works in silent mode '
                          'and needs no sound permission.',
                          style: TextStyle(fontSize: 11, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'If you feel dizzy or uncomfortable, stop and breathe normally. '
                  'This is a relaxation exercise, not medical treatment.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 10.5,
                        height: 1.5,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Thin wrapper so a future release can swap in a custom haptic pattern
/// without touching the breathing screen.
abstract final class HapticFeedbackLight {
  static void tap() => HapticFeedback.selectionClick();
}
