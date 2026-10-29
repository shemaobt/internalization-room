import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../domain/facilitator_script.dart';
import '../../domain/kept_take.dart';
import '../../domain/machine.dart' show TakeInTheAir, TheKeep;
import '../../domain/session_state.dart';
import 'motion.dart';
import 'scene_translate_step.dart' show chOf;
import 'stop_control.dart';

class SceneRecordHint extends StatelessWidget {
  final bool recording;
  final bool keeping;
  final String Function(String control) label;

  const SceneRecordHint({
    super.key,
    required this.recording,
    required this.keeping,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: SalaColors.of(context).claquete,
      fontSize: 0.84 * 16,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    Widget written(String words) =>
        Text(words, textAlign: TextAlign.center, style: style);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 36 * chOf(context, style)),
      child: recording
          ? _TakeClock(
              line: (elapsed) => written(
                '${label('takeRecording')} · ${minutesAndSecondsOf(elapsed)}',
              ),
            )
          : written(label(keeping ? 'saving' : 'recording')),
    );
  }
}

class _TakeClock extends StatefulWidget {
  final Widget Function(Duration elapsed) line;

  const _TakeClock({required this.line});

  @override
  State<_TakeClock> createState() => _TakeClockState();
}

class _TakeClockState extends State<_TakeClock> {
  final _since = clock.now();

  @override
  Widget build(BuildContext context) => Loop(
    period: const Duration(seconds: 1),
    reducible: false,
    builder: (context, _) => widget.line(clock.now().difference(_since)),
  );
}

class SceneTakeState extends StatelessWidget {
  final bool recording;
  final SceneKeep? keep;
  final TakeInTheAir? inTheAir;
  final String Function(String control) label;
  final VoidCallback onRetry;
  final void Function(TheKeep keep) onStop;

  const SceneTakeState({
    super.key,
    required this.recording,
    required this.keep,
    required this.inTheAir,
    required this.label,
    required this.onRetry,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final colors = SalaColors.of(context);
    final style = TextStyle(color: colors.vermelhoMic, fontSize: 15);
    Widget said(String control) =>
        Text(label(control), textAlign: TextAlign.center, style: style);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: switch (keep) {
        _ when recording => const <Widget>[],
        Keeping() => [
          if (inTheAir case final take?)
            StopControl(
              key: ValueKey(take.row),
              since: take.keep.since,
              label: label('stopSending'),
              aria: label('stopSendingAria'),
              color: colors.vermelhoMic,
              onStop: () => onStop(take.keep),
            ),
        ],
        NotKept(:final why) => [
          said(switch (why) {
            SendFailure.failed || SendFailure.gone => 'saveFailed',
            SendFailure.tooLarge => 'tooLarge',
            SendFailure.refused => 'refused',
          }),
          if (why == SendFailure.gone)
            said('lost')
          else
            Semantics(
              button: true,
              label: label('retry'),
              onTap: onRetry,
              excludeSemantics: true,
              child: TextButton(
                onPressed: onRetry,
                child: Text(label('retry'), style: style),
              ),
            ),
        ],
        null => const <Widget>[],
      },
    );
  }
}
