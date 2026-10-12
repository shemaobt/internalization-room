import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/coverage.dart';
import 'package:internalization_room/features/sala/domain/coverage_event.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';
import 'session_notifier_test.dart' show inConversa;

void main() {
  test(
    'a frame that lands while the voice speaks lights no bead until the line ends',
    () async {
      final harness = SalaHarness(settleDelay: const Duration(seconds: 60))
        ..room.turnIdInResponse = 'turno-1';
      harness.voice.holdNextLine();
      final container = harness.container();
      addTearDown(container.dispose);
      int lit() => container.read(salaSessionProvider).coverage.beadsFilled;

      final opening = container.read(salaSessionProvider.notifier).goConversa();
      await waitFor(
        'a fala do Guia começar',
        () => container.read(salaSessionProvider).voice == VoiceState.speaking,
      );

      harness.room.pushCoverage(
        CoverageEvent(
          turnId: 'turno-1',
          status: CoverageStatus.settled,
          coverage: coverage(engaged: 3, surfaced: 3),
        ),
      );
      await waitFor(
        'o aviso chegar e pedir o estado',
        () =>
            harness.room.calls.where((call) => call == 'fetchState').length ==
            1,
      );
      await settle();

      expect(
        lit(),
        0,
        reason:
            'o aviso acendia as contas no meio da fala — o time via o colar '
            'se mexer enquanto ainda ouvia a voz',
      );

      harness.voice.finishHeldLine();
      await opening;

      expect(
        lit(),
        3,
        reason:
            'terminada a fala, as contas que o aviso trouxe assentam na pausa',
      );
    },
  );

  test(
    'a frame that lands while the next turn is on its way lights no bead before its reply is heard',
    () async {
      final harness = SalaHarness(settleDelay: const Duration(seconds: 60))
        ..room.turnIdInResponse = 'turno-1';
      final container = await inConversa(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      int lit() => container.read(salaSessionProvider).coverage.beadsFilled;

      harness.room
        ..turnIdInResponse = 'turno-2'
        ..holdNextTurn();
      notifier.conversaTap();
      await settle();
      notifier.conversaTap();
      await waitFor(
        'o turno seguir para a sala',
        () => container.read(salaSessionProvider).machine.inFlight != null,
      );

      harness.room.pushCoverage(
        CoverageEvent(
          turnId: 'turno-1',
          status: CoverageStatus.settled,
          coverage: coverage(engaged: 3, surfaced: 3),
        ),
      );
      await settle();

      expect(
        lit(),
        0,
        reason:
            'o aviso do turno anterior acendia as contas com o turno seguinte '
            'ainda a caminho da sala',
      );

      harness.room.finishHeldTurn();
      await waitFor(
        'a resposta ser ouvida',
        () => container.read(salaSessionProvider).voice == VoiceState.invite,
      );

      expect(
        lit(),
        3,
        reason: 'ouvida a resposta, as contas que o aviso trouxe assentam',
      );
    },
  );

  test(
    'a frame that lands while the team is speaking lights no bead before the reply is heard',
    () async {
      final harness = SalaHarness(settleDelay: const Duration(seconds: 60))
        ..room.turnIdInResponse = 'turno-1';
      final container = await inConversa(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      int lit() => container.read(salaSessionProvider).coverage.beadsFilled;

      harness.room.turnIdInResponse = 'turno-2';
      notifier.conversaTap();
      await waitFor(
        'o microfone abrir para o time',
        () => container.read(salaSessionProvider).voice == VoiceState.listening,
      );

      harness.room.pushCoverage(
        CoverageEvent(
          turnId: 'turno-1',
          status: CoverageStatus.settled,
          coverage: coverage(engaged: 3, surfaced: 3),
        ),
      );
      await settle();

      expect(
        lit(),
        0,
        reason: 'o aviso acendia as contas com o time no meio da própria fala',
      );

      notifier.conversaTap();
      await waitFor(
        'a resposta ser ouvida',
        () =>
            harness.room.turnsSent == 1 &&
            container.read(salaSessionProvider).voice == VoiceState.invite,
      );

      expect(
        lit(),
        3,
        reason: 'ouvida a resposta, as contas que o aviso trouxe assentam',
      );
    },
  );

  test(
    'a frame held in a passage the team left never lights a bead in the next one',
    () async {
      final harness = SalaHarness(settleDelay: const Duration(seconds: 60))
        ..room.turnIdInResponse = 'turno-1';
      harness.voice.holdNextLine();
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState shown() => container.read(salaSessionProvider);

      unawaited(notifier.goConversa(pericope: 'P01'));
      await waitFor(
        'a fala do Guia começar na P01',
        () => shown().voice == VoiceState.speaking,
      );
      harness.room.pushCoverage(
        CoverageEvent(
          turnId: 'turno-1',
          status: CoverageStatus.settled,
          coverage: coverage(engaged: 3, surfaced: 3),
        ),
      );
      await waitFor(
        'o aviso da P01 chegar e pedir o estado',
        () =>
            harness.room.calls.where((call) => call == 'fetchState').length ==
            1,
      );

      notifier.leaveThePassage();
      harness.voice.finishHeldLine();
      await waitFor(
        'a escolha abrir',
        () => shown().stage == SalaStage.escolha,
      );

      harness.room.turnIdInResponse = 'turno-2';
      await notifier.goConversa(pericope: 'P02');
      await waitFor(
        'a abertura da P02 ser ouvida',
        () =>
            shown().stage == SalaStage.conversa &&
            shown().voice == VoiceState.invite,
      );

      expect(
        shown().coverage.beadsFilled,
        0,
        reason:
            'as contas guardadas durante a fala da P01 acendiam na P02 assim '
            'que a abertura dela terminava',
      );
    },
  );

  test(
    'a frame held through a reply that carried more beads never takes them back when it lands',
    () async {
      final harness = SalaHarness(settleDelay: const Duration(seconds: 60))
        ..room.turnIdInResponse = 'turno-1';
      final container = await inConversa(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      int lit() => container.read(salaSessionProvider).coverage.beadsFilled;

      harness.room
        ..turnIdInResponse = 'turno-2'
        ..holdNextTurn();
      notifier.conversaTap();
      await settle();
      notifier.conversaTap();
      await waitFor(
        'o turno seguir para a sala',
        () => container.read(salaSessionProvider).machine.inFlight != null,
      );
      harness.room.pushCoverage(
        CoverageEvent(
          turnId: 'turno-1',
          status: CoverageStatus.failed,
          coverage: coverage(engaged: 3, surfaced: 3),
        ),
      );
      await settle();

      harness.room
        ..nextCoverage = const Coverage(
          engaged: 3,
          surfaced: 3,
          total: totalBeads,
          beadsFilled: 5,
          beadsTold: true,
        )
        ..finishHeldTurn();
      await waitFor(
        'a resposta ser ouvida',
        () => container.read(salaSessionProvider).voice == VoiceState.invite,
      );

      expect(
        lit(),
        5,
        reason:
            'o aviso guardado tinha as mesmas contagens com 3 contas e pousava '
            'por cima das 5 que a resposta trouxe — o cordão voltava diante do time',
      );
    },
  );

  test(
    'a reply that carries fewer beads than the necklace shows leaves the lit cord as it was',
    () async {
      final harness = SalaHarness(settleDelay: const Duration(seconds: 60))
        ..room.turnIdInResponse = 'turno-1';
      final container = await inConversa(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      int lit() => container.read(salaSessionProvider).coverage.beadsFilled;

      harness.room.pushCoverage(
        CoverageEvent(
          turnId: 'turno-1',
          status: CoverageStatus.failed,
          coverage: coverage(engaged: 3, surfaced: 3),
        ),
      );
      await waitFor('o aviso acender as contas', () => lit() == 3);

      harness.room.turnIdInResponse = 'turno-2';
      notifier.conversaTap();
      await settle();
      notifier.conversaTap();
      await waitFor(
        'a resposta ser ouvida',
        () =>
            harness.room.turnsSent == 1 &&
            container.read(salaSessionProvider).voice == VoiceState.invite,
      );

      expect(
        lit(),
        3,
        reason:
            'a resposta trazia a cobertura de antes do aviso e apagava as 3 '
            'contas assim que chegava',
      );
    },
  );

  test(
    'a frame held through a reply that would not play lands once the room is back at rest',
    () async {
      final harness = SalaHarness(settleDelay: const Duration(seconds: 60))
        ..room.turnIdInResponse = 'turno-1';
      final container = await inConversa(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState shown() => container.read(salaSessionProvider);

      harness.room
        ..turnIdInResponse = 'turno-2'
        ..holdNextTurn();
      notifier.conversaTap();
      await settle();
      notifier.conversaTap();
      await waitFor(
        'o turno seguir para a sala',
        () => shown().machine.inFlight != null,
      );
      harness.room.pushCoverage(
        CoverageEvent(
          turnId: 'turno-1',
          status: CoverageStatus.failed,
          coverage: coverage(engaged: 3, surfaced: 3),
        ),
      );
      await settle();

      harness.voice.refuses.add(turnoUrl);
      harness.room.finishHeldTurn();
      await waitFor(
        'a resposta que não toca devolver a sala ao descanso',
        () =>
            harness.room.turnsSent == 1 &&
            !shown().awaitingTheGuide &&
            shown().voice == VoiceState.invite,
      );
      await settle();

      expect(
        shown().coverage.beadsFilled,
        3,
        reason:
            'a resposta que não tocou devolvia a sala ao descanso sem soltar o '
            'aviso guardado — as contas esperavam a próxima resposta',
      );
    },
  );

  test(
    'a frame that lands while the voice says her line again lands when that line ends',
    () async {
      final harness = SalaHarness(settleDelay: const Duration(seconds: 60))
        ..room.turnIdInResponse = 'turno-1';
      final container = await inConversa(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      int lit() => container.read(salaSessionProvider).coverage.beadsFilled;

      harness.voice.holdNextLine();
      final again = notifier.hearAgain();
      await waitFor(
        'a voz dizer de novo',
        () => container.read(salaSessionProvider).voice == VoiceState.speaking,
      );
      harness.room.pushCoverage(
        CoverageEvent(
          turnId: 'turno-1',
          status: CoverageStatus.failed,
          coverage: coverage(engaged: 3, surfaced: 3),
        ),
      );
      await settle();
      expect(lit(), 0, reason: 'a voz ainda está dizendo a linha de novo');

      harness.voice.finishHeldLine();
      await again;
      await settle();

      expect(
        lit(),
        3,
        reason:
            'a linha dita de novo terminava sem soltar o aviso guardado — as '
            'contas esperavam a próxima resposta',
      );
    },
  );
}
