import 'package:flutter/material.dart';

import '../../domain/session_state.dart';
import 'way_back_button.dart';

class StageHeading extends StatelessWidget {
  final SalaStage? stage;
  final String text;
  final TextStyle style;
  final double top;
  final double corner;

  const StageHeading({
    super.key,
    this.stage,
    required this.text,
    required this.style,
    this.top = 24,
    this.corner = 46,
  });

  static const _flank = 60.0;

  @override
  Widget build(BuildContext context) {
    final stage = this.stage;
    final heading = Semantics(
      header: true,
      label: text,
      child: ExcludeSemantics(
        child: Text(text, textAlign: TextAlign.center, style: style),
      ),
    );
    return LayoutBuilder(
      builder: (context, box) {
        final painter = TextPainter(
          text: TextSpan(
            text: text,
            style: DefaultTextStyle.of(context).style.merge(style),
          ),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final fitsBeside = painter.width <= box.maxWidth - 2 * _flank;
        painter.dispose();
        if (fitsBeside) {
          return SizedBox(
            width: double.infinity,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(_flank, top, _flank, 0),
                  child: heading,
                ),
                if (stage != null) WayBackButton(stage: stage, top: 8),
              ],
            ),
          );
        }
        return Column(
          children: [
            SizedBox(
              width: double.infinity,
              height: corner,
              child: Stack(
                children: [
                  if (stage != null) WayBackButton(stage: stage, top: 0),
                ],
              ),
            ),
            heading,
          ],
        );
      },
    );
  }
}
