import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import '../../data/take_upload_queue.dart';
import '../../domain/session_state.dart';
import 'bead.dart';
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
    final ghosting = session.ensaio == EnsaioStatus.ghostPlaying;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          height: 52,
          child: session.canGhostPlay || ghosting
              ? _GhostButton(
                  playing: ghosting,
                  colors: colors,
                  onTap: notifier.ghostPlay,
                )
              : null,
        ),
        const SizedBox(height: 26),
        _RecordCircle(
          recording: recording,
          dimmed: ghosting,
          colors: colors,
          onTap: notifier.ensaioTap,
          onLongPress: session.canResolveWithPerson
              ? notifier.resolveWithPerson
              : null,
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
              for (final take in session.keptTakes)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  child: PingIn(
                    child: Bead(
                      size: 24,
                      opacity: 0.45,
                      filled: !session.unsentTakeScopes.contains(take.scopeId) &&
                          !session.unsentTakeScopes.contains(unknownScope),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 64,
          child: session.ensaioHasATake
              ? AdvanceButton(
                  ready: session.ensaioDone,
                  gradient: BeadStyles.verde,
                  semanticLabel: 'Ir para a retrotradução',
                  onTap: notifier.startRetro,
                  child: const Icon(
                    LucideIcons.checkCheck,
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

class _GhostButton extends StatelessWidget {
  final bool playing;
  final SalaColors colors;
  final VoidCallback onTap;

  const _GhostButton({
    required this.playing,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final button = Opacity(
      opacity: 0.55,
      child: RoundActionButton(
        size: 52,
        semanticLabel: playing
            ? 'Parar de ouvir o ensaio guardado'
            : 'Ouvir o ensaio guardado antes de gravar',
        gradient: BeadStyles.wood,
        onTap: onTap,
        child: Icon(
          playing ? LucideIcons.pause : LucideIcons.play,
          size: 22,
          color: ShemaBrand.branco,
        ),
      ),
    );
    if (!playing) return FadeUp(child: button);
    return Pulse(
      amount: 0.08,
      period: const Duration(milliseconds: 1200),
      child: button,
    );
  }
}

class _RecordCircle extends StatelessWidget {
  final bool recording;
  final bool dimmed;
  final SalaColors colors;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _RecordCircle({
    required this.recording,
    required this.dimmed,
    required this.colors,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: switch ((recording, dimmed)) {
        (true, _) => 'Tocar ao terminar',
        (false, true) => 'O ensaio guardado está tocando',
        _ => 'Tocar para gravar o ensaio',
      },
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        behavior: HitTestBehavior.opaque,
        child: AnimatedOpacity(
          opacity: dimmed ? 0.3 : 1,
          duration: const Duration(milliseconds: 400),
          child: Loop(
            period: const Duration(milliseconds: 4600),
            animate: true,
            builder: (context, t) => Transform.scale(
              scale: 1 + (recording ? 0.06 : 0.045) * t,
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
    return Pulse(animate: pulsing, child: button);
  }
}
