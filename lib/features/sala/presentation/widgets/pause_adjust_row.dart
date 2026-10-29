import 'package:flutter/material.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../domain/facilitator_script.dart';

class PauseAdjustRow extends StatelessWidget {
  final bool lit;
  final String language;
  final VoidCallback onEarlier;
  final VoidCallback onHear;
  final VoidCallback onLater;

  const PauseAdjustRow({
    super.key,
    required this.lit,
    required this.language,
    required this.onEarlier,
    required this.onHear,
    required this.onLater,
  });

  @override
  Widget build(BuildContext context) {
    final colors = SalaColors.of(context);
    Widget control(String label, Color tone, Color edge, VoidCallback onTap) =>
        _Pill(
          words: retroLabelFor(label, language),
          tone: tone,
          edge: edge,
          lit: lit,
          onTap: onTap,
        );
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        control('pauseEarlier', colors.verde, colors.areia, onEarlier),
        control('hearThePause', colors.telha, colors.telha, onHear),
        control('pauseLater', colors.verde, colors.areia, onLater),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final String words;
  final Color tone;
  final Color edge;
  final bool lit;
  final VoidCallback onTap;

  const _Pill({
    required this.words,
    required this.tone,
    required this.edge,
    required this.lit,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: lit,
    label: words,
    child: AnimatedOpacity(
      opacity: lit ? 1 : 0.4,
      duration: const Duration(milliseconds: 200),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: lit ? onTap : null,
        child: ExcludeSemantics(
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: edge, width: 1.4),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: Text(
                words,
                textAlign: TextAlign.center,
                style: TextStyle(color: tone, fontSize: 14, height: 1.2),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
