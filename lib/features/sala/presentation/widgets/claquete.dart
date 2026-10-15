import 'dart:async';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import '../../domain/session_state.dart';
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
    ref.listenManual(salaSessionProvider.select((state) => state.sessionId), (
      was,
      now,
    ) {
      if (now == null) {
        _hide();
      } else if (now != was) {
        _show();
      }
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _show() {
    final state = ref.read(salaSessionProvider);
    final sessionId = state.sessionId;
    final pericope = state.pericope;
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
    final inConversa = ref.watch(
      salaSessionProvider.select((state) => state.stage == SalaStage.conversa),
    );
    final words = _words;
    return Positioned.fill(
      child: Stack(
        children: [
          if (inConversa)
            Positioned(
              top: MediaQuery.sizeOf(context).height * 0.08,
              left: 0,
              right: 0,
              child: Center(child: ShemaMark(onTap: _show)),
            ),
          if (words != null)
            Positioned(
              right: 14 + 76 + 8,
              bottom: 18 + MediaQuery.viewPaddingOf(context).bottom,
              child: IgnorePointer(
                child: ExcludeSemantics(child: Claquete(words: words)),
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
  Widget build(BuildContext context) => Text(
    words,
    maxLines: 1,
    style: TextStyle(
      color: ShemaBrand.verdeClaro.withValues(alpha: 0.7),
      fontSize: 11,
      letterSpacing: 0.66,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );
}
