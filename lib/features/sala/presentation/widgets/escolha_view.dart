import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import '../../domain/session_state.dart';
import 'bead_styles.dart';
import 'facilitator_circle.dart';
import 'passage_ruler.dart';

class EscolhaView extends ConsumerWidget {
  const EscolhaView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(salaSessionProvider);
    final notifier = ref.read(salaSessionProvider.notifier);
    final colors = SalaColors.of(context);
    final roda = session.naRoda ?? const [];
    final podeEntrar =
        session.oferecida != null && session.voice == VoiceState.invite;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        FacilitatorCircle(
          size: 196,
          voice: session.voice,
          reach: session.reach,
          semanticLabel: switch (session) {
            _ when session.livroInteiroFeito =>
              'Todas as passagens foram trabalhadas',
            _ when session.rodaPorLer => 'Tocar para procurar as passagens',
            _ => 'Ouvir esta passagem de novo',
          },
          onTap: notifier.escolhaTap,
          onLongPress: session.canResolveWithPerson
              ? notifier.resolveWithPerson
              : null,
        ),
        const SizedBox(height: 52),
        SizedBox(
          height: 78,
          child: session.oferecida == null
              ? null
              : AdvanceButton(
                  size: 78,
                  gradient: BeadStyles.wood,
                  halo: ShemaBrand.wood,
                  border: Border.all(color: colors.cord, width: 2),
                  semanticLabel: 'Entrar nesta passagem',
                  ready: podeEntrar,
                  onTap: notifier.entrarNaOferecida,
                ),
        ),
        const SizedBox(height: 20),
        PassageRuler(
          total: roda.length,
          at: session.aOferecer,
          started: {
            for (var index = 0; index < roda.length; index++)
              if (session.comecadas.contains(roda[index].pericope)) index,
          },
          finished: {
            for (var index = 0; index < roda.length; index++)
              if (session.feitas.contains(roda[index].pericope)) index,
          },
          hint: podeEntrar,
          onAim: notifier.apontarPassagem,
          onSettle: notifier.dizerAPassagem,
        ),
      ],
    );
  }
}
