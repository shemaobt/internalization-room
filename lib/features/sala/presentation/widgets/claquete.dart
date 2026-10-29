import 'dart:async';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import '../../domain/session_state.dart';
import '../../domain/station.dart';
import 'motion.dart';
import 'shema_mark.dart';

const _shownFor = Duration(seconds: 20);
const _size = 10.88;

class ClaqueteLayer extends ConsumerStatefulWidget {
  const ClaqueteLayer({super.key});

  @override
  ConsumerState<ClaqueteLayer> createState() => _ClaqueteLayerState();
}

class _ClaqueteLayerState extends ConsumerState<ClaqueteLayer> {
  String? _words;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    ref.listenManual(
      salaSessionProvider.select((state) => state.stationSessionId),
      (was, now) {
        if (now == null) {
          _hide();
        } else if (now != was) {
          _show();
        }
      },
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _show() {
    final state = ref.read(salaSessionProvider);
    final station = state.station;
    final sessionId = state.stationSessionId;
    final pericope = station is Panorama ? station.id : state.pericope;
    if (sessionId == null || pericope == null) return;
    final now = clock.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final day = '${now.year}-${two(now.month)}-${two(now.day)}';
    final time = '${two(now.hour)}:${two(now.minute)}';
    final characters = sessionId.substring(0, min(8, sessionId.length));
    _timer?.cancel();
    _timer = Timer(_shownFor, _hide);
    setState(() => _words = '$pericope · $day $time · $characters');
  }

  void _hide() {
    _timer?.cancel();
    if (_words != null) setState(() => _words = null);
  }

  @override
  Widget build(BuildContext context) {
    final onHerCanvas = ref.watch(
      salaSessionProvider.select(
        (state) =>
            state.stage == SalaStage.conversa ||
            state.stage == SalaStage.panorama,
      ),
    );
    final speaking = ref.watch(
      salaSessionProvider.select((state) => state.voice == VoiceState.speaking),
    );
    final words = _words;
    return Positioned.fill(
      child: Stack(
        children: [
          if (onHerCanvas)
            Positioned(
              top: MediaQuery.sizeOf(context).height * 0.08,
              left: 0,
              right: 0,
              child: Center(
                child: Loop(
                  period: const Duration(seconds: 9),
                  builder: (context, t) =>
                      MediaQuery.disableAnimationsOf(context)
                      ? _StillMark(
                          onTap: _show,
                          opacity: speaking ? 0.85 : 0.72,
                        )
                      : ShemaMark(onTap: _show, opacity: 0.66 + 0.14 * t),
                ),
              ),
            ),
          if (onHerCanvas && words != null)
            Positioned(
              left: 14 + 76 + 8,
              right: MediaQuery.sizeOf(context).width * 0.024,
              bottom:
                  MediaQuery.viewPaddingOf(context).bottom +
                  MediaQuery.sizeOf(context).height * 0.026,
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: Align(
                    alignment: Alignment.centerRight,
                    heightFactor: 1,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Claquete(words: words),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StillMark extends StatefulWidget {
  final VoidCallback onTap;
  final double opacity;

  const _StillMark({required this.onTap, required this.opacity});

  @override
  State<_StillMark> createState() => _StillMarkState();
}

class _StillMarkState extends State<_StillMark>
    with SingleTickerProviderStateMixin {
  late final _ease = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
    animationBehavior: AnimationBehavior.preserve,
  );
  late Animation<double> _opacity = AlwaysStoppedAnimation(widget.opacity);

  @override
  void didUpdateWidget(_StillMark oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.opacity == oldWidget.opacity) return;
    _opacity = Tween(
      begin: _opacity.value,
      end: widget.opacity,
    ).chain(CurveTween(curve: Curves.ease)).animate(_ease);
    _ease.forward(from: 0);
  }

  @override
  void dispose() {
    _ease.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ease,
      builder: (context, _) =>
          ShemaMark(onTap: widget.onTap, opacity: _opacity.value),
    );
  }
}

class Claquete extends StatelessWidget {
  final String words;

  const Claquete({super.key, required this.words});

  @override
  Widget build(BuildContext context) {
    return Text(
      words,
      maxLines: 1,
      style: TextStyle(
        color: SalaColors.of(context).claquete.withValues(alpha: 0.7),
        fontSize: _size,
        letterSpacing: _size * 0.06,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}
