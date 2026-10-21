import 'package:flutter/material.dart';

import '../../../../core/theme/sala_colors.dart';

class StatusLines extends StatelessWidget {
  const StatusLines({super.key, this.line, this.note});

  final String? line;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final colors = SalaColors.of(context);
    return Column(
      children: [
        if (line case final line?) _StatusLine(line, colors.momentoInk),
        if (note case final note?) _StatusLine(note, colors.mut),
      ],
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine(this.text, this.ink);

  final String text;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: ink, fontSize: 15),
        ),
      ),
    );
  }
}
