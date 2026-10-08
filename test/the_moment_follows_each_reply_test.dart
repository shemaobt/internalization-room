import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/current_session_ledger.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/moment.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';
import 'session_notifier_test.dart' show inConversa;

const _familiarization = Moment(at: MomentAt.familiarization, parts: 4);

void main() {
  test(
    'a later reply that opens scene two moves the moment the team sees',
    () async {
      final harness = SalaHarness()..room.nextMoment = _familiarization;
      final container = await inConversa(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      expect(
        container.read(salaSessionProvider).moment?.at,
        MomentAt.familiarization,
      );

      harness.room.nextMoment = const Moment(
        at: MomentAt.internalization,
        part: 2,
        parts: 4,
      );
      notifier.conversaTap();
      await settle();
      notifier.conversaTap();
      await waitFor(
        'o momento seguir a resposta',
        () => container.read(salaSessionProvider).moment?.part == 2,
      );

      final moment = container.read(salaSessionProvider).moment;
      expect(
        moment?.at,
        MomentAt.internalization,
        reason: 'a voz abriu a cena 2 e a tela ficou na Familiarização',
      );
      expect(moment?.part, 2);
    },
  );

  test(
    'a reply that carries no moment takes the label away rather than leave a stale one',
    () async {
      final harness = SalaHarness()..room.nextMoment = _familiarization;
      final container = await inConversa(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      harness.room.nextMoment = null;
      notifier.conversaTap();
      await settle();
      notifier.conversaTap();
      await waitFor(
        'o momento sair da tela',
        () => container.read(salaSessionProvider).moment == null,
      );

      expect(
        container.read(salaSessionProvider).moment,
        isNull,
        reason:
            'a sala parou de mandar o momento e a tela continuou mostrando o antigo',
      );
    },
  );

  test(
    'a relaunch mid-conversation lands with the moment the room kept',
    () async {
      final home = Directory.systemTemp.createTempSync('sala-momento');
      addTearDown(() => home.deleteSync(recursive: true));
      final harness =
          SalaHarness(
              currentSession: CurrentSessionLedger(home: () async => home),
            )
            ..room.nextMoment = const Moment(
              at: MomentAt.articulation,
              part: 3,
              parts: 4,
            );
      final container = harness.container();
      addTearDown(container.dispose);
      SalaSessionState read() => container.read(salaSessionProvider);
      await enterThePassage(
        container.read(salaSessionProvider.notifier),
        read,
        'P01',
      );
      await waitFor(
        'a abertura ser dita',
        () =>
            harness.voice.played.contains(turnoUrl) &&
            read().voice == VoiceState.invite,
      );
      await settle();
      final session = read().sessionId!;

      final (_, next) = await relaunch(harness, container);
      await next.read(salaSessionProvider.notifier).openTheRoom();
      await waitFor('a equipe voltar à sessão', () {
        final state = next.read(salaSessionProvider);
        return state.sessionId == session &&
            !state.awaitingTheGuide &&
            state.voice == VoiceState.invite;
      });

      final moment = next.read(salaSessionProvider).moment;
      expect(
        moment?.at,
        MomentAt.articulation,
        reason:
            'o tablet voltou à sessão e a tela perdeu o momento em que a sala estava',
      );
      expect(moment?.part, 3);
    },
  );

  test(
    'a passage the team already opened on another tablet lands with its moment, not without a label',
    () async {
      final harness = SalaHarness()
        ..room.createdOpened = true
        ..room.nextMoment = const Moment(
          at: MomentAt.internalization,
          part: 2,
          parts: 4,
        );
      final container = harness.container();
      addTearDown(container.dispose);
      SalaSessionState read() => container.read(salaSessionProvider);

      await enterThePassage(
        container.read(salaSessionProvider.notifier),
        read,
        'P01',
      );
      await waitFor(
        'a passagem pousar',
        () => read().sessionId != null && read().voice == VoiceState.invite,
      );
      await settle();

      final moment = read().moment;
      expect(
        moment?.at,
        MomentAt.internalization,
        reason:
            'a sessão que outro tablet abriu pousava sem etiqueta, embora a sala soubesse o momento',
      );
      expect(moment?.part, 2);
    },
  );
}
