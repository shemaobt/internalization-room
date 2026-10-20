import 'package:flutter/material.dart';

import 'leave_passage_button.dart';

class StageHeading extends StatelessWidget {
  final String text;
  final TextStyle style;

  const StageHeading({super.key, required this.text, required this.style});

  static const _flank = 60.0;

  @override
  Widget build(BuildContext context) {
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
                  padding: const EdgeInsets.fromLTRB(_flank, 24, _flank, 0),
                  child: heading,
                ),
                const LeavePassageButton(carriedAt: 8),
              ],
            ),
          );
        }
        return Column(
          children: [
            const SizedBox(
              width: double.infinity,
              height: 46,
              child: Stack(children: [LeavePassageButton(carriedAt: 0)]),
            ),
            heading,
          ],
        );
      },
    );
  }
}
