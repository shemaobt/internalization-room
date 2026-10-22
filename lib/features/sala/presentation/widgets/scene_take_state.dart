import 'package:flutter/material.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../domain/kept_take.dart';
import '../../domain/machine.dart' show TakeInTheAir;
import '../../domain/session_state.dart';
import 'stop_the_send.dart';

class SceneTakeState extends StatelessWidget {
  final bool recording;
  final SceneKeep? keep;
  final TakeInTheAir? inTheAir;
  final String Function(String control) label;
  final VoidCallback onRetry;
  final void Function(String row) onStop;

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
        _ when recording => [said('takeRecording')],
        Keeping() => [
          said('takeSending'),
          if (inTheAir case final take?)
            StopControl(
              key: ValueKey(take.row),
              since: take.since,
              label: label('stopSending'),
              aria: label('stopSendingAria'),
              color: colors.vermelhoMic,
              onStop: () => onStop(take.row),
            ),
        ],
        NotKept(:final why) => [
          said(switch (why) {
            SendFailure.failed => 'saveFailed',
            SendFailure.tooLarge => 'tooLarge',
            SendFailure.refused => 'refused',
          }),
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
