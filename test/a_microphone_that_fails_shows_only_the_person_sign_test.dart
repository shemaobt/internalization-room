import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/conversa_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/escolha_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart';
import 'session_notifier_test.dart' show inConversa;

const _hearAgain = 'Ouvir de novo';

typedef _Sala = ({
  WidgetTester tester,
  SalaHarness harness,
  ProviderContainer container,
});

SalaSessionState _read(_Sala sala) => sala.container.read(salaSessionProvider);

SalaSessionNotifier _notifier(_Sala sala) =>
    sala.container.read(salaSessionProvider.notifier);

Future<void> _until(_Sala sala, String what, bool Function() ready) => waitFor(
  what,
  ready,
  step: () => sala.tester.pump(const Duration(milliseconds: 100)),
);

Future<void> _pass(_Sala sala, [int beats = 5]) async {
  for (var beat = 0; beat < beats; beat++) {
    await sala.tester.pump(const Duration(milliseconds: 100));
  }
}

int _said(_Sala sala) =>
    sala.harness.voice.played.length +
    sala.harness.voice.assets.length +
    sala.harness.voice.fixedLines.length;

bool _hitTestable(String label) =>
    byLabel(label).hitTestable().evaluate().isNotEmpty;

SalaHarness _aRoom() => SalaHarness(filaEmMemoria: true)
  ..room.passages = const [Passagem(pericope: 'P01', audioUrl: '/voice/p01')];

Future<_Sala> _theRoomOpens(WidgetTester tester, SalaHarness harness) async {
  final container = await pumpSala(tester, harness);
  final sala = (tester: tester, harness: harness, container: container);
  await _until(sala, 'the Choice to be listed', () => _read(sala).entriesOpen);
  return sala;
}

Future<_Sala> _atRestInTheConversation(
  WidgetTester tester, [
  SalaHarness? given,
]) async {
  final sala = await _theRoomOpens(tester, given ?? _aRoom());
  unawaited(_notifier(sala).goConversa(book: 'Ruth', pericope: 'P01'));
  await _until(
    sala,
    'the opening to be heard and the room to rest',
    () =>
        _read(sala).sessionId != null &&
        _read(sala).voice == VoiceState.invite &&
        !_read(sala).awaitingTheGuide,
  );
  await _pass(sala, 20);
  return sala;
}

Future<void> _tapTheCircle(_Sala sala) async {
  await sala.tester.tap(find.byType(FacilitatorCircle));
  await _pass(sala);
}

/// A take and her reply to it, held while she says it.
Future<void> _aReplySpeaking(_Sala sala) async {
  sala.harness.room.holdNextTurn();
  await _tapTheCircle(sala);
  await _tapTheCircle(sala);
  await _until(
    sala,
    'the turn in the air',
    () => sala.harness.room.turnsSent > 0,
  );
  sala.harness.voice.holdNextLine();
  sala.harness.room.finishHeldTurn();
  await _until(
    sala,
    'the reply to speak',
    () => _read(sala).voice == VoiceState.speaking,
  );
}

/// The team cuts the reply off, and the microphone fails to start.
Future<void> _anInterruptWhoseMicrophoneFails(_Sala sala) async {
  await _aReplySpeaking(sala);
  sala.harness.recorder.startThrows = true;
  await _tapTheCircle(sala);
  await _pass(sala, 10);
}

void main() {
  testWidgets(
    'a refused microphone on the Conversation shows the person sign over the Conversation and says nothing',
    (tester) async {
      final sala = await _atRestInTheConversation(tester);
      sala.harness.recorder.permitted = false;
      final said = _said(sala);

      await _tapTheCircle(sala);
      await _until(sala, 'the person sign', () => _read(sala).needsPerson);
      await _pass(sala, 10);

      expect(thePersonSign, findsOneWidget);
      expect(find.byType(ConversaView), findsOneWidget);
      expect(_said(sala), said);
      closeTheRoom(sala.container);
    },
  );

  testWidgets(
    'a room opened on a tablet whose microphone is refused shows the Choice and says nothing',
    (tester) async {
      final harness = _aRoom()..recorder.permitted = false;
      final sala = await _theRoomOpens(tester, harness);
      await _pass(sala, 10);

      expect(find.byType(EscolhaView), findsOneWidget);
      expect(_read(sala).naRoda, isNotEmpty);
      expect(_said(sala), 0);

      unawaited(_notifier(sala).goConversa(book: 'Ruth', pericope: 'P01'));
      await _until(
        sala,
        'the opening to play',
        () => harness.voice.played.contains(turnoUrl),
      );
      closeTheRoom(sala.container);
    },
  );

  testWidgets(
    'on a tablet whose microphone is refused, a tap over the speaking voice '
    'changes nothing',
    (tester) async {
      final harness = _aRoom()..recorder.permitted = false;
      final sala = await _theRoomOpens(tester, harness);
      harness.voice.holdNextLine();
      unawaited(_notifier(sala).goConversa(book: 'Ruth', pericope: 'P01'));
      await _until(
        sala,
        'the opening to speak',
        () => _read(sala).voice == VoiceState.speaking,
      );
      await _pass(sala, 20);
      final stops = harness.voice.stops;
      final starts = harness.sounds.where((s) => s == 'recorder:start').length;

      await _tapTheCircle(sala);

      expect(_read(sala).voice, VoiceState.speaking);
      expect(harness.voice.stops, stops);
      expect(harness.sounds.where((s) => s == 'recorder:start').length, starts);
      expect(thePersonSign, findsNothing);
      harness.voice.finishHeldLine();
      await _pass(sala);
      closeTheRoom(sala.container);
    },
  );

  testWidgets(
    'on a tablet whose microphone permission is unknown, a tap over the '
    'speaking voice changes nothing',
    (tester) async {
      final harness = _aRoom()..recorder.answersPermission = null;
      final sala = await _theRoomOpens(tester, harness);
      harness.voice.holdNextLine();
      unawaited(_notifier(sala).goConversa(book: 'Ruth', pericope: 'P01'));
      await _until(
        sala,
        'the opening to speak',
        () => _read(sala).voice == VoiceState.speaking,
      );
      await _pass(sala, 20);
      final stops = harness.voice.stops;
      final starts = harness.sounds.where((s) => s == 'recorder:start').length;

      await _tapTheCircle(sala);

      expect(_read(sala).voice, VoiceState.speaking);
      expect(harness.voice.stops, stops);
      expect(harness.sounds.where((s) => s == 'recorder:start').length, starts);
      harness.voice.finishHeldLine();
      await _pass(sala);
      closeTheRoom(sala.container);
    },
  );

  testWidgets(
    'an interrupt whose microphone fails once rests the circle with «Ouvir de '
    'novo» lit, and the reply replays in full',
    (tester) async {
      final sala = await _atRestInTheConversation(tester);
      await _anInterruptWhoseMicrophoneFails(sala);
      final played = sala.harness.voice.played.length;
      await _pass(sala, 10);

      expect(thePersonSign, findsNothing);
      expect(_read(sala).voice, VoiceState.invite);
      expect(_hitTestable(_hearAgain), isTrue);
      expect(
        sala.harness.voice.played,
        hasLength(played),
        reason: 'the cut reply is not resumed',
      );

      sala.harness.recorder.startThrows = false;
      await tester.tap(byLabel(_hearAgain));
      await _until(
        sala,
        'the reply to play again',
        () => sala.harness.voice.played.length == played + 1,
      );
      expect(sala.harness.voice.played.last, turnoUrl);
      closeTheRoom(sala.container);
    },
  );

  testWidgets(
    'one failed start, then a success, leaves nothing visible and the count '
    'starts again',
    (tester) async {
      final sala = await _atRestInTheConversation(tester);
      sala.harness.recorder.startThrows = true;
      await _tapTheCircle(sala);
      expect(thePersonSign, findsNothing);

      sala.harness.recorder.startThrows = false;
      await _tapTheCircle(sala);
      expect(_read(sala).voice, VoiceState.listening);
      await _tapTheCircle(sala);
      await _until(
        sala,
        'the room to rest after the reply',
        () =>
            _read(sala).voice == VoiceState.invite &&
            !_read(sala).awaitingTheGuide,
      );

      sala.harness.recorder.startThrows = true;
      await _tapTheCircle(sala);
      await _pass(sala, 10);

      expect(thePersonSign, findsNothing);
      expect(_read(sala).needsPerson, isFalse);
      closeTheRoom(sala.container);
    },
  );

  testWidgets('two failed starts in a row show the person sign', (
    tester,
  ) async {
    final sala = await _atRestInTheConversation(tester);
    final said = _said(sala);
    sala.harness.recorder.startThrows = true;

    await _tapTheCircle(sala);
    await _tapTheCircle(sala);
    await _until(sala, 'the person sign', () => _read(sala).needsPerson);
    await _pass(sala, 10);

    expect(thePersonSign, findsOneWidget);
    expect(_said(sala), said);
    closeTheRoom(sala.container);
  });

  testWidgets("an interrupt's failure counts with the next one", (
    tester,
  ) async {
    final sala = await _atRestInTheConversation(tester);
    await _anInterruptWhoseMicrophoneFails(sala);
    expect(thePersonSign, findsNothing);

    await _tapTheCircle(sala);
    await _until(sala, 'the person sign', () => _read(sala).needsPerson);
    await _pass(sala, 10);

    expect(thePersonSign, findsOneWidget);
    closeTheRoom(sala.container);
  });

  group('off the session screen a microphone failure is silent', () {
    int saidBy(SalaHarness harness) =>
        harness.voice.played.length +
        harness.voice.assets.length +
        harness.voice.fixedLines.length;

    Future<(SalaHarness, SalaSessionNotifier, SalaSessionState Function())>
    onTheRehearsal() async {
      final harness = SalaHarness();
      final container = await inConversa(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      notifier.goEnsaio();
      await settle();
      return (harness, notifier, () => container.read(salaSessionProvider));
    }

    /// A tablet reopening straight into the telling-back of a kept part.
    Future<(SalaHarness, SalaSessionNotifier, SalaSessionState Function())>
    onTheBackTranslation() async {
      final harness = SalaHarness();
      final gravada = File(
        '${Directory.systemTemp.createTempSync('sala-1356').path}/p1.m4a',
      )..writeAsBytesSync([1, 2, 3]);
      addTearDown(() => gravada.parent.deleteSync(recursive: true));
      harness.emAberto.rows['Ruth/P01/pt'] = ResumePoint(
        sessionId: 'sessao-antiga',
        stage: SalaStage.retro,
        takes: [
          KeptTake(
            scopeId: KeptScope.parte(1),
            path: gravada.path,
            takeId: 'gravacao-1',
          ),
        ],
      );
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      await notifier.abrirEscolha();
      await settle();
      await notifier.goConversa(book: 'Ruth', pericope: 'P01');
      SalaSessionState read() => container.read(salaSessionProvider);
      await waitFor(
        'the telling-back to open',
        () => read().stage == SalaStage.retro,
      );
      await settle();
      harness.playback.at = const Duration(seconds: 2);
      return (harness, notifier, read);
    }

    for (final (how, fails) in [
      ('fails twice', (FakeRecorder recorder) => recorder.startThrows = true),
      ('is refused', (FakeRecorder recorder) => recorder.permitted = false),
    ]) {
      test(
        'a microphone that $how on the Rehearsal shows and says nothing',
        () async {
          final (harness, notifier, read) = await onTheRehearsal();
          final said = saidBy(harness);
          final partes = read().partes;
          fails(harness.recorder);
          final starts = harness.recorder.captures;

          notifier.gravarACena(1);
          await settle();
          notifier.gravarACena(1);
          await settle();

          expect(harness.recorder.captures, greaterThanOrEqualTo(starts + 2));
          expect(read().needsPerson, isFalse);
          expect(read().ensaio, EnsaioStatus.idle);
          expect(read().partes, partes);
          expect(saidBy(harness), said);
        },
      );

      test("a microphone that $how on the Back-translation's circle shows and "
          'says nothing', () async {
        final (harness, notifier, read) = await onTheBackTranslation();
        final said = saidBy(harness);
        fails(harness.recorder);
        final starts = harness.recorder.captures;

        for (var capture = 0; capture < 2; capture++) {
          notifier.retroTap();
          await settle();
          notifier.retroTap();
          await settle();
        }

        expect(harness.recorder.captures, greaterThanOrEqualTo(starts + 2));
        expect(read().needsPerson, isFalse);
        expect(read().btPhase, isNot(BtPhase.capturing));
        expect(saidBy(harness), said);
      });
    }
  });
}
