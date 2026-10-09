import 'package:flutter/material.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../domain/facilitator_script.dart';
import '../../domain/moment.dart';

class MomentLabel extends StatelessWidget {
  final Moment moment;
  final String words;
  final String language;

  const MomentLabel({
    super.key,
    required this.moment,
    required this.words,
    required this.language,
  });

  @override
  Widget build(BuildContext context) {
    final [name, ...rest] = words.split(' · ');
    final colors = SalaColors.of(context);
    final tint = switch (moment.at) {
      MomentAt.familiarization => colors.momentoFam,
      MomentAt.internalization => colors.momentoInt,
      MomentAt.articulation => colors.vermelhoMic,
      MomentAt.ensaioFinal => colors.telha,
    };
    final dark = Theme.of(context).brightness == Brightness.dark;
    final wash = dark
        ? 0.14
        : (moment.at == MomentAt.articulation ? 0.1 : 0.12);
    final ink = colors.ink;
    return Semantics(
      label: '${momentAriaFor(language)}: $words',
      liveRegion: true,
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: tint.withValues(alpha: wash),
            border: Border.all(color: tint, width: 1.5),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
                child: SizedBox(width: 9, height: 9),
              ),
              const SizedBox(width: 7),
              Text(
                name,
                style: TextStyle(
                  color: ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                rest.map((piece) => ' · $piece').join(),
                style: TextStyle(color: ink, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
