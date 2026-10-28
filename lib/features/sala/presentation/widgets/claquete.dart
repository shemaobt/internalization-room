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
                  builder: (context, t) => ShemaMark(
                    onTap: _show,
                    opacity: MediaQuery.disableAnimationsOf(context)
                        ? (speaking ? 0.85 : 0.72)
                        : 0.66 + 0.14 * t,
                  ),
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
        fontSize: 10.88,
        letterSpacing: 0.66,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}
