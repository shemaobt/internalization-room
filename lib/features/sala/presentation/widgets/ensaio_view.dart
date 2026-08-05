import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import '../../domain/session_state.dart';
import 'bead_styles.dart';
import 'eq_bars.dart';
import 'motion.dart';

class EnsaioView extends ConsumerWidget {
  const EnsaioView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(salaSessionProvider);
    final notifier = ref.read(salaSessionProvider.notifier);
    final colors = SalaColors.of(context);
    final recording = session.ensaio == EnsaioStatus.recording;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _RecordCircle(
          recording: recording,
          colors: colors,
          onStart: notifier.recStart,
          onStop: notifier.recStop,
        ),
        const SizedBox(height: 38),
        EqBars(active: recording),
        const SizedBox(height: 38),
        SizedBox(
          height: 60,
          child: session.ensaio == EnsaioStatus.recorded
              ? FadeUp(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _TakeActionButton(
                        colors: colors,
                        semanticLabel: 'Ouvir a gravação',
                        pulsing: session.playPing,
                        icon: Icon(
                          LucideIcons.play,
                          size: 24,
                          color: colors.ink,
                        ),
                        onTap: notifier.takePlay,
                      ),
                      const SizedBox(width: 24),
                      _TakeActionButton(
                        colors: colors,
                        semanticLabel: 'Gravar de novo',
                        icon: Icon(
                          LucideIcons.rotateCcw,
                          size: 24,
                          color: colors.mut,
                        ),
                        onTap: notifier.takeRedo,
                      ),
                      const SizedBox(width: 24),
                      RoundActionButton(
                        size: 60,
                        semanticLabel: 'Guardar esta gravação',
                        gradient: BeadStyles.verde,
                        shadows: [
                          BoxShadow(
                            color: ShemaBrand.verdeLo.withValues(alpha: 0.3),
                            offset: const Offset(0, 4),
                            blurRadius: 12,
                          ),
                        ],
                        onTap: notifier.takeKeep,
                        child: const Icon(
                          LucideIcons.check,
                          size: 24,
                          color: ShemaBrand.branco,
                        ),
                      ),
                    ],
                  ),
                )
              : null,
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 26,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < session.takes; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  child: PingIn(
                    child: Opacity(
                      opacity: 0.45,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: BeadStyles.wood,
                          boxShadow: BeadStyles.matte,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 64,
          child: session.ensaioDone
              ? AdvanceButton(
                  gradient: BeadStyles.verde,
                  semanticLabel: 'Ouvir e conferir',
                  onTap: notifier.goCheck,
                  child: const Icon(
                    LucideIcons.helpCircle,
                    size: 26,
                    color: ShemaBrand.branco,
                  ),
                )
              : null,
        ),
      ],
    );
  }
}

class _RecordCircle extends StatelessWidget {
  final bool recording;
  final SalaColors colors;
  final VoidCallback onStart;
  final VoidCallback onStop;

  const _RecordCircle({
    required this.recording,
    required this.colors,
    required this.onStart,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Segurar para gravar o ensaio',
      child: Listener(
        onPointerDown: (_) => onStart(),
        onPointerUp: (_) => onStop(),
        onPointerCancel: (_) => onStop(),
        child: Loop(
          period: const Duration(milliseconds: 4600),
          animate: !recording,
          builder: (context, t) => Transform.scale(
            scale: recording ? 1 : 1 + 0.045 * t,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: BeadStyles.telha(colors),
                boxShadow: recording
                    ? [
                        BoxShadow(color: colors.halo, spreadRadius: 10),
                        BoxShadow(
                          color: colors.telha.withValues(alpha: 0.38),
                          offset: const Offset(0, 12),
                          blurRadius: 38,
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: colors.telha.withValues(alpha: 0.32),
                          offset: const Offset(0, 10),
                          blurRadius: 34,
                        ),
                      ],
              ),
              child: const Icon(
                LucideIcons.mic,
                size: 52,
                color: ShemaBrand.branco,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TakeActionButton extends StatelessWidget {
  final SalaColors colors;
  final String semanticLabel;
  final Widget icon;
  final VoidCallback onTap;
  final bool pulsing;

  const _TakeActionButton({
    required this.colors,
    required this.semanticLabel,
    required this.icon,
    required this.onTap,
    this.pulsing = false,
  });

  @override
  Widget build(BuildContext context) {
    final button = RoundActionButton(
      size: 60,
      semanticLabel: semanticLabel,
      background: colors.elev,
      border: Border.all(color: colors.line, width: 1.5),
      onTap: onTap,
      child: icon,
    );
    if (!pulsing) return button;
    return Loop(
      period: const Duration(milliseconds: 1000),
      builder: (context, t) =>
          Transform.scale(scale: 1 + 0.12 * t, child: button),
    );
  }
}
