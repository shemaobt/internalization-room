import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show bySemanticsLabelWidget, pumpSala;

void main() {
  testWidgets(
      'the circle at the entrada never says the facilitator already finished',
      (tester) async {
    final container = await pumpSala(tester, SalaHarness());
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.openConvite();
    await tester.pump(const Duration(milliseconds: 200));

    expect(container.read(salaSessionProvider).showEntrada, isTrue,
        reason: 'os dois checks abaixo só valem alguma coisa com a sala parada '
            'na entrada — sem isto o teste passaria mesmo se openConvite nunca '
            'chegasse lá');
    expect(bySemanticsLabelWidget('O facilitador já contou do livro'),
        findsNothing,
        reason: 'o panorama não tem fim previsto — dizer que o facilitador já '
            'terminou é o próprio convite fingindo que não há mais turno');
    expect(bySemanticsLabelWidget('Falar com o facilitador'), findsOneWidget);
  });

  testWidgets(
      'the bead stays live through a whole panorama exchange, not only '
      'while the invite sits idle', (tester) async {
    final container = await pumpSala(tester, SalaHarness());
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.openConvite();
    await tester.pump(const Duration(milliseconds: 200));
    notifier.conviteTap();
    await tester.pump(const Duration(milliseconds: 200));

    expect(container.read(salaSessionProvider).voice, VoiceState.listening,
        reason: 'a asserção abaixo só prova algo enquanto a sala está no meio '
            'de um turno, não parada no convite');
    final bead = tester.widget<Semantics>(
      bySemanticsLabelWidget('Entrar na passagem'),
    );
    expect(bead.properties.enabled, isTrue,
        reason: 'a conta é a saída a qualquer momento — inclusive com a equipe '
            'gravando a próxima pergunta, não só entre um turno e outro');

    await tester.tap(bySemanticsLabelWidget('Entrar na passagem'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(container.read(salaSessionProvider).stage, SalaStage.escolha,
        reason: 'a conta precisa realmente funcionar nesse instante, não só '
            'parecer acesa');
  });
}
