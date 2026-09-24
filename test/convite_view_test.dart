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

  testWidgets('the bead stays on the table through a whole panorama exchange, '
      'but answers only once the exchange is over', (tester) async {
    final harness = SalaHarness();
    final container = await pumpSala(tester, harness);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.openConvite();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(bySemanticsLabelWidget('Falar com o facilitador'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      container.read(salaSessionProvider).voice,
      VoiceState.listening,
      reason:
          'a asserção abaixo só prova algo enquanto a equipe está gravando '
          'a resposta, não parada no convite',
    );
    expect(bySemanticsLabelWidget('Entrar na passagem'), findsOneWidget);
    expect(
      tester
          .widget<Semantics>(bySemanticsLabelWidget('Entrar na passagem'))
          .properties
          .enabled,
      isFalse,
      reason:
          'a conta atendia no meio da gravação e jogava a resposta da equipe '
          'fora — a dela só atende fora de turno e de fala',
    );

    await tester.tap(
      bySemanticsLabelWidget('Entrar na passagem'),
      warnIfMissed: false,
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      container.read(salaSessionProvider).voice,
      VoiceState.listening,
      reason: 'o toque na conta interrompia a gravação e abria a roda',
    );

    harness.voice.holdNextLine();
    await tester.tap(bySemanticsLabelWidget('Falar com o facilitador'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      container.read(salaSessionProvider).voice,
      VoiceState.speaking,
      reason: 'a asserção abaixo só vale com o Guia respondendo',
    );
    expect(
      tester
          .widget<Semantics>(bySemanticsLabelWidget('Entrar na passagem'))
          .properties
          .enabled,
      isFalse,
      reason: 'a conta atendia por cima da resposta do Guia',
    );

    harness.voice.finishHeldLine();
    await tester.pump(const Duration(seconds: 2));

    expect(
      container.read(salaSessionProvider).voice,
      VoiceState.invite,
      reason: 'a troca precisa ter acabado para a conta voltar a atender',
    );
    await tester.tap(bySemanticsLabelWidget('Entrar na passagem'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      container.read(salaSessionProvider).stage,
      SalaStage.escolha,
      reason: 'com a troca encerrada, a conta precisa realmente funcionar',
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
