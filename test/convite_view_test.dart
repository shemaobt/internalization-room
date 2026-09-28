import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show byLabel;

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
        byLabel('O facilitador já contou do livro'),
        findsNothing,
        reason:
            'o panorama não tem fim previsto — dizer que o facilitador já '
            'terminou é o próprio convite fingindo que não há mais turno',
      );
      expect(byLabel('Falar com o facilitador'), findsOneWidget);
    },
  );

  testWidgets('the bead stays on the table through a whole panorama exchange, '
      'but answers only once the exchange is over', (tester) async {
    final harness = SalaHarness();
    final container = await pumpSala(tester, harness);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.openConvite();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      tester
          .widget<Semantics>(byLabel('Entrar na passagem'))
          .properties
          .enabled,
      isTrue,
      reason:
          'a conta precisa estar atendendo antes da gravação, senão o surdo '
          'abaixo é só o segundo depois da abertura',
    );
    await tester.tap(byLabel('Falar com o facilitador'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      container.read(salaSessionProvider).voice,
      VoiceState.listening,
      reason:
          'a asserção abaixo só prova algo enquanto a equipe está gravando '
          'a resposta, não parada no convite',
    );
    expect(byLabel('Entrar na passagem'), findsOneWidget);
    expect(
      tester
          .widget<Semantics>(byLabel('Entrar na passagem'))
          .properties
          .enabled,
      isFalse,
      reason:
          'a conta atendia no meio da gravação e jogava a resposta da equipe '
          'fora — a dela só atende fora de turno e de fala',
    );

    await tester.tap(byLabel('Entrar na passagem'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      container.read(salaSessionProvider).voice,
      VoiceState.listening,
      reason: 'o toque na conta interrompia a gravação e abria a roda',
    );

    harness.voice.holdNextLine();
    await tester.tap(byLabel('Falar com o facilitador'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      container.read(salaSessionProvider).voice,
      VoiceState.speaking,
      reason:
          'a asserção abaixo só vale com o Guia respondendo há mais de um segundo',
    );
    expect(
      tester
          .widget<Semantics>(byLabel('Entrar na passagem'))
          .properties
          .enabled,
      isFalse,
      reason: 'a conta atendia por cima da resposta do Guia',
    );

    harness.voice.finishHeldLine();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      container.read(salaSessionProvider).voice,
      VoiceState.invite,
      reason: 'a troca precisa ter acabado para a conta voltar a atender',
    );
    await tester.tap(byLabel('Entrar na passagem'));
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
    await tester.tap(byLabel('Falar com o facilitador'));
    await tester.pump(const Duration(milliseconds: 200));

    for (final voice in [VoiceState.thinking, VoiceState.speaking]) {
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        container.read(salaSessionProvider).voice,
        voice,
        reason:
            'o que vem abaixo só vale com o Guia preparando ou dizendo a abertura',
      );
      expect(
        byLabel('Entrar na passagem'),
        findsOneWidget,
        reason:
            'a conta só nascia no fim da abertura, já acesa, debaixo do dedo '
            'que ia ao círculo',
      );
      expect(
        tester
            .widget<Semantics>(byLabel('Entrar na passagem'))
            .properties
            .enabled,
        isFalse,
        reason: 'com o Guia ocupado, a conta está na mesa mas não atende',
      );

      await tester.tap(byLabel('Entrar na passagem'), warnIfMissed: false);
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

  testWidgets('a touch that reaches the bead as the opening ends goes nowhere, '
      'and the circle still records', (tester) async {
    final harness = SalaHarness();
    final container = await pumpSala(tester, harness);

    await tester.tap(byLabel('Falar com o facilitador'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      container.read(salaSessionProvider).conviteStep,
      ConviteStep.entrada,
      reason: 'o que vem abaixo só vale com a abertura já dita',
    );
    expect(
      tester
          .widget<Semantics>(byLabel('Entrar na passagem'))
          .properties
          .enabled,
      isFalse,
      reason:
          'a conta atendia no mesmo quadro em que a abertura terminava, e o '
          'toque que ia ao círculo abriu a roda no portão',
    );

    await tester.tap(byLabel('Entrar na passagem'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 200));
    expect(container.read(salaSessionProvider).stage, SalaStage.convite);

    await tester.tap(byLabel('Falar com o facilitador'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      container.read(salaSessionProvider).voice,
      VoiceState.listening,
      reason: 'o primeiro toque no círculo depois da abertura grava a equipe',
    );
  });

  testWidgets('a second after the opening, the bead opens the wheel', (
    tester,
  ) async {
    final harness = SalaHarness();
    final container = await pumpSala(tester, harness);

    await tester.tap(byLabel('Falar com o facilitador'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      tester
          .widget<Semantics>(byLabel('Entrar na passagem'))
          .properties
          .enabled,
      isTrue,
      reason: 'passado o segundo, a saída dela volta a estar à mão',
    );
    await tester.tap(byLabel('Entrar na passagem'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(container.read(salaSessionProvider).stage, SalaStage.escolha);
  });

  testWidgets(
    'a panorama that finds no room takes the bead away without a crash',
    (tester) async {
      final harness = SalaHarness(retryBackoff: const [Duration(seconds: 30)]);
      final container = await pumpSala(tester, harness);

      harness.network.holdNextCheck();
      await tester.tap(byLabel('Falar com o facilitador'));
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        byLabel('Entrar na passagem'),
        findsOneWidget,
        reason: 'a conta precisa estar na mesa, surda, para o teste valer',
      );

      harness.network.reachable = false;
      harness.network.finishHeldCheck();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(seconds: 1));

      expect(container.read(salaSessionProvider).offline, isTrue);
      expect(byLabel('Entrar na passagem'), findsNothing);
      expect(
        tester.takeException(),
        isNull,
        reason:
            'a conta que saía da mesa sem nunca ter atendido lia o provider '
            'no dispose, com o widget já desmontado',
      );

      await tester.pumpWidget(const SizedBox());
      container.dispose();
      await tester.pump();
    },
  );

  testWidgets('the second the bead waits is a second even on a tablet that '
      'turned animations off', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final harness = SalaHarness();
    final container = await pumpSala(tester, harness);

    await tester.tap(byLabel('Falar com o facilitador'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      container.read(salaSessionProvider).conviteStep,
      ConviteStep.entrada,
      reason: 'o que vem abaixo só vale com a abertura já dita',
    );
    expect(
      tester
          .widget<Semantics>(byLabel('Entrar na passagem'))
          .properties
          .enabled,
      isFalse,
      reason:
          'com as animações desligadas o segundo encolhia para 50 ms, e a '
          'conta voltava a atender debaixo do dedo',
    );

    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      tester
          .widget<Semantics>(byLabel('Entrar na passagem'))
          .properties
          .enabled,
      isTrue,
    );
  });

  testWidgets('the bead fades onto the table instead of appearing whole', (
    tester,
  ) async {
    final harness = SalaHarness();
    await pumpSala(tester, harness);

    double shown() {
      final above = find.ancestor(
        of: byLabel('Entrar na passagem'),
        matching: find.byWidgetPredicate(
          (widget) => widget is Opacity || widget is FadeTransition,
        ),
      );
      return tester
          .widgetList(above)
          .fold(
            1.0,
            (shown, widget) =>
                shown *
                (widget is Opacity
                    ? widget.opacity
                    : (widget as FadeTransition).opacity.value),
          );
    }

    harness.voice.holdNextLine();
    await tester.tap(byLabel('Falar com o facilitador'));
    await tester.pump();

    expect(byLabel('Entrar na passagem'), findsOneWidget);
    expect(
      shown(),
      lessThan(0.5),
      reason:
          'um alvo que surge inteiro de um quadro para o outro puxa o dedo '
          'que ia ao círculo',
    );

    await tester.pump(const Duration(seconds: 1));

    expect(
      shown(),
      1.0,
      reason: 'o fade chega ao fim, a conta não fica apagada',
    );
    harness.voice.finishHeldLine();
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets(
    'the invitation circle speaks english to an english room, not portuguese',
    (tester) async {
      final container = await pumpSala(tester, SalaHarness(lingua: 'en'));

      await container.read(salaSessionProvider.notifier).openConvite();
      await tester.pump(const Duration(milliseconds: 200));

      expect(container.read(salaSessionProvider).stage, SalaStage.convite);
      expect(byLabel('Talk to the facilitator'), findsOneWidget);
      expect(
        byLabel('Falar com o facilitador'),
        findsNothing,
        reason:
            'o círculo do convite dizia "Falar com o facilitador" a um '
            'aparelho em inglês',
      );
    },
  );

  testWidgets('the way into the passage speaks english to an english room, not '
      'portuguese', (tester) async {
    final container = await pumpSala(tester, SalaHarness(lingua: 'en'));

    await container.read(salaSessionProvider.notifier).openConvite();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(seconds: 1));

    expect(container.read(salaSessionProvider).entradaOffered, isTrue);
    expect(byLabel('Enter the passage'), findsOneWidget);
    expect(
      byLabel('Entrar na passagem'),
      findsNothing,
      reason:
          'a conta da entrada dizia "Entrar na passagem" a um aparelho em '
          'inglês',
    );
  });

  testWidgets(
    'the invitation calling a person says so in english to an english room',
    (tester) async {
      final harness = SalaHarness(lingua: 'en');
      final container = await pumpSala(tester, harness);
      final notifier = container.read(salaSessionProvider.notifier);
      await notifier.openConvite();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(seconds: 1));

      harness.room.failWith = const RoomRefused();
      notifier.conviteTap();
      await tester.pump(const Duration(milliseconds: 200));
      notifier.conviteTap();
      for (var frame = 0; frame < 30; frame++) {
        await tester.pump(const Duration(milliseconds: 200));
        if (container.read(salaSessionProvider).needsPerson) break;
      }

      expect(container.read(salaSessionProvider).stage, SalaStage.convite);
      expect(container.read(salaSessionProvider).needsPerson, isTrue);
      expect(byLabel('A moment for someone'), findsOneWidget);
      expect(
        byLabel('Um momento para uma pessoa'),
        findsNothing,
        reason:
            'o convite chamando uma pessoa dizia "Um momento para uma '
            'pessoa" a um aparelho em inglês',
      );
    },
  );
}
