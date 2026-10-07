import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/domain/station.dart';
import 'package:internalization_room/features/sala/presentation/widgets/escolha_view.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart';

const _panorama = Passagem(
  pericope: 'panorama',
  audioUrl: '/voice/panorama',
  kind: PassagemKind.panorama,
);
const _theBook = [
  _panorama,
  Passagem(pericope: 'P01', audioUrl: '/voice/p01'),
  Passagem(pericope: 'P02', audioUrl: '/voice/p02'),
  Passagem(pericope: 'P03', audioUrl: '/voice/p03'),
  Passagem(pericope: 'P04', audioUrl: '/voice/p04'),
  Passagem(pericope: 'P05', audioUrl: '/voice/p05'),
];

void main() {
  test(
    'the first tap on a passage opens that passage, not the Panorama',
    () async {
      final harness = SalaHarness()..room.passages = _theBook;
      final container = harness.container();
      addTearDown(container.dispose);
      SalaSessionState read() => container.read(salaSessionProvider);

      await enterThePassage(
        container.read(salaSessionProvider.notifier),
        read,
        'P02',
      );
      await waitFor('the passage to open', () => read().sessionId != null);

      expect(harness.room.pericopesAsked, ['P02']);
      expect(read().station, isA<Canvas>());
    },
  );

  test(
    'a team midway in one passage that taps another opens the one tapped',
    () async {
      final harness = SalaHarness()..room.passages = _theBook;
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);
      await enterThePassage(notifier, read, 'P03');
      await waitFor('P03 to open', () => read().sessionId != null);
      await waitFor(
        'P03 to keep its place',
        () => harness.emAberto.rows.containsKey('Ruth/P03'),
      );
      final p03Row = harness.emAberto.rows['Ruth/P03'];

      notifier.leaveThePassage();
      await enterThePassage(notifier, read, 'P05');
      await waitFor(
        'P05 to open',
        () => read().sessionId == harness.room.sessionIds.last,
      );

      expect(harness.room.pericopesAsked.last, 'P05');
      expect(read().station, isA<Canvas>());
      expect(read().sessionId, harness.room.sessionIds.last);
      expect(harness.emAberto.rows['Ruth/P03'], p03Row);
    },
  );

  test(
    'a tap on the Panorama opens the Panorama Station and voices the Panorama',
    () async {
      final harness = SalaHarness()..room.passages = _theBook;
      final container = harness.container();
      addTearDown(container.dispose);
      SalaSessionState read() => container.read(salaSessionProvider);

      await enterThePanorama(
        container.read(salaSessionProvider.notifier),
        read,
      );
      await waitFor(
        'the Panorama to be voiced',
        () => harness.voice.played.contains(turnoUrl),
      );

      expect(harness.room.pericopesAsked, [panoramaPericope]);
      expect(harness.room.sessionsSpokenTo, harness.room.sessionIds);
      expect(harness.room.sessionIds, hasLength(1));
      expect(read().station, isA<Panorama>());
      expect(read().stage, SalaStage.panorama);
    },
  );

  test(
    'a Panorama whose opening fell with the network opens again when the room '
    'comes back',
    () async {
      final harness = SalaHarness()..room.passages = _theBook;
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);
      await notifier.abrirEscolha();
      await waitFor(
        'the Wheel to offer the Panorama',
        () =>
            read().oferecida == _panorama && read().voice == VoiceState.invite,
      );
      harness.network.reachable = false;
      harness.room.reachable = false;

      notifier.entrarNaOferecida();
      await waitFor('the room to be out of reach', () => read().offline);
      harness.network.reachable = true;
      harness.room.reachable = true;
      notifier.retryNow();
      await waitFor(
        'the opening to be asked',
        () => harness.room.sessionsSpokenTo.isNotEmpty,
      );

      expect(harness.room.sessionIds, hasLength(1));
      expect(harness.room.sessionsSpokenTo, harness.room.sessionIds);
      expect(read().station, isA<Panorama>());
    },
  );

  test('a fall on the Panorama after its line was said does not voice the '
      'Panorama again when the room comes back', () async {
    final harness = SalaHarness()..room.passages = _theBook;
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);
    await enterThePanorama(notifier, read);
    await waitFor('the Panorama to be said', () => read().panoramaSaid);
    harness.inbox.refuses = true;

    notifier.handTap();
    notifier.panoramaTap();
    notifier.panoramaTap();
    await waitFor('the room to be out of reach', () => read().offline);
    harness.inbox.refuses = false;
    notifier.retryNow();
    await waitFor('the room to come back', () => !read().offline);
    await settle();

    expect(harness.room.sessionsSpokenTo, hasLength(1));
    expect(read().station, isA<Panorama>());
  });

  testWidgets('the team can leave the Panorama for the passage choice', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true, lingua: 'en')
      ..room.passages = _theBook;
    final container = await pumpSala(tester, harness);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    Future<void> enter() async {
      await notifier.abrirEscolha();
      await tester.pump(const Duration(milliseconds: 300));
      expect(read().oferecida, _panorama);
      notifier.entrarNaOferecida();
      await tester.pump(const Duration(milliseconds: 600));
    }

    await enter();
    final leave = byLabel('Leave this passage and choose another');
    expect(leave, findsOneWidget);

    await tester.tap(leave);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(EscolhaView), findsOneWidget);

    await enter();
    expect(harness.room.sessionIds, hasLength(1));
    expect(harness.room.sessionsSpokenTo, hasLength(2));
  });
}
