import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import '../../domain/facilitator_script.dart';
import '../../domain/passagem.dart';
import '../../domain/session_state.dart';
import 'bead_styles.dart';
import 'facilitator_circle.dart';
import 'motion.dart';
import 'passage_ruler.dart';

class EscolhaView extends ConsumerWidget {
  const EscolhaView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(salaSessionProvider);
    final notifier = ref.read(salaSessionProvider.notifier);
    final colors = SalaColors.of(context);
    final language = ref.watch(roomLanguageProvider);
    final roda = session.naRoda ?? const [];
    final podeEntrar =
        session.oferecida != null &&
        session.voice == VoiceState.invite &&
        !session.needsPerson;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        FacilitatorCircle(
          size: facilitatorCircleSize,
          halt: session.halt,
          voice: session.voice,
          reach: session.reach,
          semanticLabel: switch (session) {
            _ when session.livroInteiroFeito || session.wheelHalted =>
              escolhaLabelFor('allDone', language),
            _ when session.rodaPorLer => escolhaLabelFor(
              'readTheWheel',
              language,
            ),
            _ => escolhaLabelFor('hearAgain', language),
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
              : FadeUp(
                  child: RoundActionButton(
                    size: 78,
                    mood: podeEntrar ? ButtonMood.beckoning : ButtonMood.dimmed,
                    gradient: BeadStyles.wood,
                    shadows: RoundActionButton.dropShadow,
                    halo: ShemaBrand.wood,
                    border: Border.all(color: colors.cord, width: 2),
                    semanticLabel: entrarLabelFor(
                      isPanorama: session.oferecida!.isPanorama,
                      language: language,
                    ),
                    onTap: notifier.entrarNaOferecida,
                  ),
                ),
        ),
        const SizedBox(height: 20),
        PassageRuler(
          total: roda.length,
          at: session.aOferecer,
          approved: {
            for (var index = 0; index < roda.length; index++)
              if (roda[index].approved) index,
          },
          current: _indexOfTheEntryLeft(roda, session.leftEntry),
          hint: podeEntrar,
          onAim: notifier.apontarPassagem,
          onSettle: notifier.dizerAPassagem,
          language: language,
        ),
      ],
    );
  }
}

int? _indexOfTheEntryLeft(List<Passagem> roda, LeftEntry? left) {
  if (left == null) return null;
  final index = roda.indexWhere(
    (passagem) => left.panorama
        ? passagem.isPanorama
        : passagem.pericope == left.pericope,
  );
  return index < 0 ? null : index;
}
