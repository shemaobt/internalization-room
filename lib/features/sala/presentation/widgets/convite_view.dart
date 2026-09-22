import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import 'bead_styles.dart';
import 'facilitator_circle.dart';

class ConviteView extends ConsumerWidget {
  const ConviteView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(salaSessionProvider);
    final notifier = ref.read(salaSessionProvider.notifier);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        FacilitatorCircle(
          size: 196,
          voice: session.voice,
          reach: session.reach,
          beckon: session.awaitingFirstTouch,
          semanticLabel: switch (session) {
            _ when session.needsPerson => 'Um momento para uma pessoa',
            _ => 'Falar com o facilitador',
          },
          onTap: notifier.conviteTap,
          onLongPress: session.canResolveWithPerson
              ? notifier.resolveWithPerson
              : null,
        ),
        const SizedBox(height: 52),
        SizedBox(
          height: 78,
          child: session.entradaOffered
              ? AdvanceButton(
                  ready: session.entradaOffered,
                  size: 78,
                  gradient: BeadStyles.wood,
                  halo: ShemaBrand.wood,
                  border: Border.all(
                    color: SalaColors.of(context).cord,
                    width: 2,
                  ),
                  semanticLabel: 'Entrar na passagem',
                  onTap: notifier.abrirEscolha,
                )
              : null,
        ),
      ],
    );
  }
}
