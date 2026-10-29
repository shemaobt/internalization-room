import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
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

const _thePanorama = 'OV-Ruth/$testLanguage';

({
  SalaHarness harness,
  SalaSessionNotifier notifier,
  SalaSessionState Function() read,
})
_aRoomThatResumes() {
  final harness = SalaHarness()
    ..room.passages = _theBook
    ..room.resumesTheLatest = true;
  final container = harness.container();
  addTearDown(container.dispose);
  return (
    harness: harness,
    notifier: container.read(salaSessionProvider.notifier),
    read: () => container.read(salaSessionProvider),
  );
}

Future<void> _thePanoramaSaid(
  SalaSessionNotifier notifier,
  SalaSessionState Function() read,
) async {
  await enterThePanorama(notifier, read);
  await waitFor(
    'the Panorama to be said',
    () => read().panoramaSaid && read().voice == VoiceState.invite,
  );
}

Future<void> _theSaidPanoramaLeftForAPassage(
  SalaSessionNotifier notifier,
  SalaSessionState Function() read,
) async {
  await _thePanoramaSaid(notifier, read);
  notifier.leaveThePassage();
  await enterThePassage(notifier, read, 'P01');
  await waitFor('P01 to open', () => read().sessionId != null);
  await waitFor('P01 to be said', () => read().voice == VoiceState.invite);
  notifier.leaveThePassage();
}

void main() {
  test('a Panorama chosen again after the room reset it plays the opening of '
      'the new session, not silence on the old one', () async {
    final (:harness, :notifier, :read) = _aRoomThatResumes();
    await _theSaidPanoramaLeftForAPassage(notifier, read);
    harness.room.latestSessions.remove(_thePanorama);
    harness.room.nextSessionId = 'sessao-zerada';
    final playedBefore = harness.voice.played.length;

    await enterThePanorama(notifier, read);
    await waitFor(
      'the Panorama to land',
      () => harness.voice.played.length > playedBefore || read().canHearAgain,
    );
    await settle();

    expect(
      read().panoramaSessionId,
      'sessao-zerada',
      reason: 'o Panorama zerado pela facilitadora ficava na sessão velha',
    );
    expect(harness.room.sessionsSpokenTo.last, 'sessao-zerada');
    expect(harness.voice.played.skip(playedBefore), [turnoUrl]);
    expect(read().station, isA<Panorama>());
  });

  test('a Panorama chosen again that another tablet already opened rests on '
      'that session with «ouvir de novo», saying nothing', () async {
    final (:harness, :notifier, :read) = _aRoomThatResumes();
    await _theSaidPanoramaLeftForAPassage(notifier, read);
    harness.room.latestSessions[_thePanorama] = 'sessao-do-outro-tablet';
    harness.room.openedSessions.add('sessao-do-outro-tablet');
    final playedBefore = harness.voice.played.length;

    await enterThePanorama(notifier, read);
    await waitFor(
      'the Panorama to land',
      () => harness.voice.played.length > playedBefore || read().canHearAgain,
    );
    await settle();

    expect(
      read().panoramaSessionId,
      'sessao-do-outro-tablet',
      reason: 'a sessão aberta noutro tablet nunca chegava a este',
    );
    expect(harness.voice.played.skip(playedBefore), isEmpty);
    expect(read().canHearAgain, isTrue);
  });

  test('a Panorama chosen again whose session the room no longer has opens '
      'the one the room answers, instead of leaving the Panorama', () async {
    final (:harness, :notifier, :read) = _aRoomThatResumes();
    await _theSaidPanoramaLeftForAPassage(notifier, read);
    harness.room.forgetTheSession(read().panoramaSessionId!);
    harness.room.nextSessionId = 'sessao-nova';
    final playedBefore = harness.voice.played.length;

    await enterThePanorama(notifier, read);
    await waitFor(
      'the Panorama to land',
      () =>
          harness.voice.played.length > playedBefore ||
          read().canHearAgain ||
          read().station is Menu,
    );
    await settle();

    expect(
      read().station,
      isA<Panorama>(),
      reason: 'a leitura da sessão perdida falhava e a equipe saía do Panorama',
    );
    expect(read().panoramaSessionId, 'sessao-nova');
    expect(harness.room.sessionsSpokenTo.last, 'sessao-nova');
    expect(harness.voice.played.skip(playedBefore), [turnoUrl]);
  });

  test('the pill of the Panorama just left asks the room too, and after a '
      'reset plays the new opening', () async {
    final (:harness, :notifier, :read) = _aRoomThatResumes();
    await _thePanoramaSaid(notifier, read);
    notifier.leaveThePassage();
    harness.room.latestSessions.remove(_thePanorama);
    harness.room.nextSessionId = 'sessao-zerada';
    final playedBefore = harness.voice.played.length;

    await enterThePanorama(notifier, read);
    await settle();
    await waitFor(
      'the Panorama to rest',
      () => !read().awaitingTheGuide && read().voice == VoiceState.invite,
    );
    await settle();

    expect(
      read().panoramaSessionId,
      'sessao-zerada',
      reason:
          'o toque no Panorama deixado voltava em silêncio à sessão velha, '
          'sem perguntar nada à sala',
    );
    expect(harness.voice.played.skip(playedBefore), [turnoUrl]);
  });

  test('the pill of the Panorama just left, still the room\'s opened session, '
      'rests with «ouvir de novo» armed and says nothing', () async {
    final (:harness, :notifier, :read) = _aRoomThatResumes();
    await _thePanoramaSaid(notifier, read);
    final panorama = read().panoramaSessionId;
    notifier.leaveThePassage();
    final playedBefore = harness.voice.played.length;

    await enterThePanorama(notifier, read);
    await settle();
    await waitFor(
      'the Panorama to rest',
      () => !read().awaitingTheGuide && read().voice == VoiceState.invite,
    );
    await settle();

    expect(
      read().canHearAgain,
      isTrue,
      reason: 'o Panorama deixado voltava pelo toque sem o «ouvir de novo»',
    );
    expect(read().panoramaSessionId, panorama);
    expect(harness.voice.played.skip(playedBefore), isEmpty);
  });
}
