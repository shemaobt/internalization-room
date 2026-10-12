import 'package:flutter/material.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../domain/moment.dart';

class MomentLabel extends StatelessWidget {
  final MomentAt at;
  final String words;
  final String aria;
  final double size;

  const MomentLabel({
    super.key,
    required this.at,
    required this.words,
    required this.aria,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final [name, ...rest] = words.split(' · ');
    final colors = SalaColors.of(context);
    final tint = switch (at) {
      MomentAt.familiarization => colors.momentoFam,
      MomentAt.internalization => colors.momentoInt,
      MomentAt.articulation => colors.vermelhoMic,
      MomentAt.ensaioFinal => colors.momentoEf,
    };
    final dark = Theme.of(context).brightness == Brightness.dark;
    final wash = dark ? 0.14 : (at == MomentAt.articulation ? 0.1 : 0.12);
    final style = TextStyle(
      color: colors.momentoInk,
      fontSize: size,
      height: 1.25,
      letterSpacing: size * 0.01,
    );
    return Semantics(
      label: '$aria: $words',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.fromLTRB(9.92, 4.48, 12.8, 4.8),
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
                child: const SizedBox(width: 9.6, height: 9.6),
              ),
              const SizedBox(width: 7.2),
              Text(name, style: style.copyWith(fontWeight: FontWeight.w600)),
              Text(rest.map((piece) => ' · $piece').join(), style: style),
            ],
          ),
        ),
      ),
    );
  }
}
