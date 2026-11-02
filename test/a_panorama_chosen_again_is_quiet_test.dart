import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';

const _theBook = [
  Passagem(
    pericope: 'OV-Ruth',
    audioUrl: '/voice/panorama',
    kind: PassagemKind.panorama,
    book: 'Ruth',
  ),
  Passagem(pericope: 'P01', audioUrl: '/voice/p01', book: 'Ruth'),
];

int _opensAsked(SalaHarness harness) =>
    harness.room.calls.where((call) => call == 'openSession').length;

Future<void> _theSaidPanoramaLeftForAPassage(
  SalaSessionNotifier notifier,
  SalaSessionState Function() read,
) async {
  await enterThePanorama(notifier, read);
  await waitFor(
    'the Panorama to be said',
    () => read().panoramaSaid && read().voice == VoiceState.invite,
  );
  notifier.leaveThePassage();
  await enterThePassage(notifier, read, 'P01');
  await waitFor('P01 to open', () => read().sessionId != null);
  await waitFor('P01 to be said', () => read().voice == VoiceState.invite);
  notifier.leaveThePassage();
}

Future<void> _theTeamChoosesItAgain(
  SalaSessionNotifier notifier,
  SalaSessionState Function() read,
) async {
  await enterThePanorama(notifier, read);
  await waitFor(
    'the Panorama to land',
    () => read().station is Panorama && read().panoramaSaid,
  );
  await settle();
}

void main() {
  test('a Panorama chosen again from the Choice after its line was said plays '
      'nothing and rests with «ouvir de novo»', () async {
    final harness = SalaHarness()
      ..room.passages = _theBook
      ..room.resumesTheLatest = true;
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);
    await _theSaidPanoramaLeftForAPassage(notifier, read);
    final panorama = read().panoramaSessionId;
    final opensBefore = _opensAsked(harness);
    final playedBefore = harness.voice.played.length;

    await _theTeamChoosesItAgain(notifier, read);

    expect(
      _opensAsked(harness),
      opensBefore,
      reason: 'o Panorama já aberto pedia a abertura de novo',
    );
    expect(
      harness.voice.played.skip(playedBefore),
      isEmpty,
      reason: 'a sala repetia a última fala do Panorama sem ninguém pedir',
    );
    expect(read().panoramaSessionId, panorama);
    expect(read().panoramaSaid, isTrue);
    expect(read().voice, VoiceState.invite);
    expect(read().awaitingTheGuide, isFalse);
    expect(read().canHearAgain, isTrue);
  });

  test('«ouvir de novo» on a Panorama chosen again plays the Panorama\'s held '
      'clip, not the passage left, asking the room nothing', () async {
    final harness = SalaHarness()
      ..room.passages = _theBook
      ..room.resumesTheLatest = true;
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);
    await _theSaidPanoramaLeftForAPassage(notifier, read);
    await _theTeamChoosesItAgain(notifier, read);
    final playedBefore = harness.voice.played.length;

    await notifier.hearAgain();
    await waitFor(
      'the line to be said again',
      () => harness.voice.played.length > playedBefore,
    );

    expect(
      harness.room.sessionsSaidAgain,
      isEmpty,
      reason:
          'o ouvir de novo do Panorama pedia à sala o clipe que o tablet tem',
    );
    expect(harness.voice.played.skip(playedBefore), [turnoUrl]);
  });

  test('a Panorama chosen again whose session the room says was never opened '
      'still asks its opening', () async {
    final harness = SalaHarness()
      ..room.passages = _theBook
      ..room.resumesTheLatest = true;
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);
    await _theSaidPanoramaLeftForAPassage(notifier, read);
    final panorama = read().panoramaSessionId!;
    harness.room.openedSessions.remove(panorama);
    final playedBefore = harness.voice.played.length;

    await enterThePanorama(notifier, read);
    await waitFor(
      'the opening to be said',
      () => harness.voice.played.length > playedBefore && read().panoramaSaid,
    );

    expect(harness.room.sessionsSpokenTo.last, panorama);
    expect(harness.voice.played.skip(playedBefore), [turnoUrl]);
  });

  test('the first Panorama of a launch, already opened in the room, plays '
      'nothing and rests with «ouvir de novo»', () async {
    final harness = SalaHarness()
      ..room.passages = _theBook
      ..room.createdOpened = true;
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);
    final playedBefore = harness.voice.played.length;

    await _theTeamChoosesItAgain(notifier, read);

    expect(harness.room.sessionIds, hasLength(1));
    expect(
      _opensAsked(harness),
      0,
      reason:
          'a primeira entrada do dia pedia a abertura de um Panorama já aberto',
    );
    expect(harness.voice.played.skip(playedBefore), isEmpty);
    expect(read().voice, VoiceState.invite);
    expect(read().canHearAgain, isTrue);
  });

  test('a passage pill that cannot open after a said Panorama was left lays '
      'that Panorama back in silence', () async {
    final harness = SalaHarness()..room.passages = _theBook;
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);
    await enterThePanorama(notifier, read);
    await waitFor(
      'the Panorama to be said',
      () => read().panoramaSaid && read().voice == VoiceState.invite,
    );
    final panorama = read().panoramaSessionId;
    notifier.leaveThePassage();
    await waitFor('the way back', () => read().entriesOpen);
    harness.room.reachable = false;
    final playedBefore = harness.voice.played.length;

    notifier.openTheEntry(
      read().naRoda!.firstWhere((entry) => entry.pericope == 'P01'),
    );
    await waitFor(
      'the Panorama to be back',
      () => read().station is Panorama && !read().awaitingTheGuide,
    );
    await settle();

    expect(read().panoramaSessionId, panorama);
    expect(read().panoramaSaid, isTrue);
    expect(read().canHearAgain, isTrue);
    expect(harness.voice.played.skip(playedBefore), isEmpty);
  });

  test('its own pill that cannot open offline lays the said Panorama back in '
      'silence', () async {
    final harness = SalaHarness()..room.passages = _theBook;
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);
    await enterThePanorama(notifier, read);
    await waitFor(
      'the Panorama to be said',
      () => read().panoramaSaid && read().voice == VoiceState.invite,
    );
    notifier.leaveThePassage();
    await waitFor('the way back', () => read().entriesOpen);
    harness.room.reachable = false;

    notifier.openTheEntry(read().naRoda!.firstWhere((e) => e.isPanorama));
    await waitFor(
      'the Panorama to be back',
      () => read().station is Panorama && !read().awaitingTheGuide,
    );
    await settle();

    expect(read().panoramaSaid, isTrue);
    expect(read().canHearAgain, isTrue);
  });

  test('the Panorama pill that cannot open offline after a passage was left '
      'lays that passage back', () async {
    final harness = SalaHarness()..room.passages = _theBook;
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);
    await _theSaidPanoramaLeftForAPassage(notifier, read);
    await waitFor('the way back to P01', () => read().entriesOpen);
    final p01 = read().passageLeft!.session;
    harness.room.reachable = false;

    notifier.openTheEntry(read().naRoda!.firstWhere((e) => e.isPanorama));
    await waitFor('P01 to be back', () => read().station is Canvas);
    await settle();

    expect(read().pericope, 'P01');
    expect(read().sessionId, p01);
  });

  test('the ≡ way back to a Panorama whose line was said still comes back in '
      'silence, asking the room nothing', () async {
    final harness = SalaHarness()..room.passages = _theBook;
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);
    await enterThePanorama(notifier, read);
    await waitFor(
      'the Panorama to be said',
      () => read().panoramaSaid && read().voice == VoiceState.invite,
    );
    notifier.leaveThePassage();
    await waitFor('the way back', () => read().entriesOpen);
    final callsBefore = harness.room.calls.length;
    final playedBefore = harness.voice.played.length;

    await notifier.returnToTheLeftEntry();
    await waitFor(
      'the Panorama to be back',
      () => read().station is Panorama && read().panoramaSaid,
    );
    await settle();

    expect(
      harness.room.calls
          .skip(callsBefore)
          .where((call) => call == 'openSession' || call == 'fetchState'),
      isEmpty,
    );
    expect(harness.voice.played.skip(playedBefore), isEmpty);
    expect(read().canHearAgain, isTrue);

    await notifier.hearAgain();
    await waitFor(
      'the held clip to be played again',
      () => harness.voice.played.length > playedBefore,
    );

    expect(harness.voice.played.last, turnoUrl);
    expect(harness.room.sessionsSaidAgain, isEmpty);
  });

  test(
    'the ≡ way back to a Panorama left while its line was still speaking '
    'comes back in silence with «ouvir de novo», asking the room nothing',
    () async {
      final harness = SalaHarness()..room.passages = _theBook;
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);
      harness.voice.holdNextLine();
      await enterThePanorama(notifier, read);
      await waitFor(
        'the Panorama to start speaking',
        () => harness.voice.played.contains(turnoUrl),
      );
      expect(read().panoramaSaid, isFalse);
      notifier.leaveThePassage();
      await waitFor('the way back', () => read().entriesOpen);
      final callsBefore = harness.room.calls.length;
      final playedBefore = harness.voice.played.length;

      await notifier.returnToTheLeftEntry();
      await waitFor(
        'the Panorama to be back',
        () => read().station is Panorama && read().panoramaSaid,
      );
      await settle();

      expect(
        harness.room.calls
            .skip(callsBefore)
            .where((call) => call == 'openSession' || call == 'fetchState'),
        isEmpty,
      );
      expect(harness.voice.played.skip(playedBefore), isEmpty);
      expect(read().canHearAgain, isTrue);

      await notifier.hearAgain();
      await waitFor(
        'the held clip to be played again',
        () => harness.voice.played.length > playedBefore,
      );

      expect(harness.voice.played.last, turnoUrl);
      expect(harness.room.sessionsSaidAgain, isEmpty);
    },
  );

  test('a Panorama chosen again under the room\'s warning rests with that '
      'warning showing, not after the next look', () async {
    final harness = SalaHarness()..room.passages = _theBook;
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);
    await _theSaidPanoramaLeftForAPassage(notifier, read);
    harness.room.serverHalt = HaltKind.warning;

    await _theTeamChoosesItAgain(notifier, read);

    expect(
      read().warning,
      isTrue,
      reason:
          'a leitura do Panorama trazia o aviso da sala e ele só aparecia '
          'na próxima olhada, trinta segundos depois',
    );
  });

  test('the first Panorama of a launch that rests readies her quick '
      'acknowledgements before the team speaks', () async {
    final harness = SalaHarness()
      ..room.passages = _theBook
      ..room.createdOpened = true;
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    await _theTeamChoosesItAgain(notifier, read);

    expect(
      harness.voice.readied,
      containsAll(const [('F0', 'pt'), ('F1', 'pt'), ('F2', 'pt')]),
      reason:
          'o primeiro «estou pensando» depois do Panorama em repouso era '
          'buscado na hora, e numa conexão ruim não era dito',
    );
  });
}
