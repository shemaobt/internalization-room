import 'package:flutter/material.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../domain/facilitator_script.dart';
import '../../domain/moment.dart';

class MomentLabel extends StatelessWidget {
  final Moment moment;
  final String language;

  const MomentLabel({super.key, required this.moment, required this.language});

  @override
  Widget build(BuildContext context) {
    final label = momentLabelFor(moment, language);
    final cut = label.indexOf(' · ');
    final tint = switch (moment.at) {
      MomentAt.familiarization => ShemaBrand.verdeAzulado,
      MomentAt.internalization => ShemaBrand.roxo,
      MomentAt.articulation => ShemaBrand.vermelhoMic,
      MomentAt.ensaioFinal => ShemaBrand.telha,
    };
    final ink = SalaColors.of(context).ink;
    return Semantics(
      label: '${momentAriaFor(language)}: $label',
      liveRegion: true,
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.1),
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
                label.substring(0, cut),
                style: TextStyle(
                  color: ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                label.substring(cut),
                style: TextStyle(color: ink, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
