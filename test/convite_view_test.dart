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

      expect(
        container.read(salaSessionProvider).showEntrada,
        isTrue,
        reason:
            'os dois checks abaixo só valem alguma coisa com a sala parada '
            'na entrada — sem isto o teste passaria mesmo se openConvite nunca '
            'chegasse lá',
      );
      expect(
        bySemanticsLabelWidget('O facilitador já contou do livro'),
        findsNothing,
        reason:
            'o panorama não tem fim previsto — dizer que o facilitador já '
            'terminou é o próprio convite fingindo que não há mais turno',
      );
      expect(bySemanticsLabelWidget('Falar com o facilitador'), findsOneWidget);
    },
  );

  testWidgets('the bead stays live through a whole panorama exchange, not only '
      'while the invite sits idle', (tester) async {
    final container = await pumpSala(tester, SalaHarness());
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.openConvite();
    await tester.pump(const Duration(milliseconds: 200));
    notifier.conviteTap();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      container.read(salaSessionProvider).voice,
      VoiceState.listening,
      reason:
          'a asserção abaixo só prova algo enquanto a sala está no meio '
          'de um turno, não parada no convite',
    );
    final bead = tester.widget<Semantics>(
      bySemanticsLabelWidget('Entrar na passagem'),
    );
    expect(
      bead.properties.enabled,
      isTrue,
      reason:
          'a conta é a saída a qualquer momento — inclusive com a equipe '
          'gravando a próxima pergunta, não só entre um turno e outro',
    );

    await tester.tap(bySemanticsLabelWidget('Entrar na passagem'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      container.read(salaSessionProvider).stage,
      SalaStage.escolha,
      reason:
          'a conta precisa realmente funcionar nesse instante, não só '
          'parecer acesa',
    );
  });

  testWidgets('the way in is on the table while the panorama is asked for and '
      'told, and a touch on it cuts nothing off', (tester) async {
    final harness = SalaHarness();
    final container = await pumpSala(tester, harness);

    harness.voice
      ..holdNextFetch()
      ..holdNextLine();
    await tester.tap(bySemanticsLabelWidget('Falar com o facilitador'));
    await tester.pump(const Duration(milliseconds: 200));

    for (final voice in [VoiceState.thinking, VoiceState.speaking]) {
      expect(
        container.read(salaSessionProvider).voice,
        voice,
        reason:
            'o que vem abaixo só vale com o Guia preparando ou dizendo a abertura',
      );
      expect(
        bySemanticsLabelWidget('Entrar na passagem'),
        findsOneWidget,
        reason:
            'a conta só nascia no fim da abertura, já acesa, debaixo do dedo '
            'que ia ao círculo',
      );
      expect(
        tester
            .widget<Semantics>(bySemanticsLabelWidget('Entrar na passagem'))
            .properties
            .enabled,
        isFalse,
        reason: 'com o Guia ocupado, a conta está na mesa mas não atende',
      );

      await tester.tap(
        bySemanticsLabelWidget('Entrar na passagem'),
        warnIfMissed: false,
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        container.read(salaSessionProvider).stage,
        SalaStage.convite,
        reason: 'um toque na conta cortava o panorama antes de ele ser dito',
      );
      harness.voice.finishHeldFetch();
      await tester.pump(const Duration(milliseconds: 200));
    }
    harness.voice.finishHeldLine();
    await tester.pump(const Duration(milliseconds: 200));
  });
}
