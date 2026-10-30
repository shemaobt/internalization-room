import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart'
    show enterThePanorama, enterThePassage, intoTheBackTranslation, settle;
import 'um_ensaio_de_tres_partes.dart';

Future<(Sala, String)> _anEnglishSessionReachedAgainAfterPtWasTapped({
  String? turnFixedLine,
}) async {
  final harness = SalaHarness(lingua: null);
  if (turnFixedLine != null) harness.room.fixedLine = turnFixedLine;
  final container = harness.container();
  addTearDown(container.dispose);
  final it = Sala(harness, container);
  it.sala.chooseTheLanguage('en');
  await settle();
  await enterThePassage(it.sala, () => it.estado, 'P01');
  await waitFor(
    'the session to open',
    () => it.estado.sessionId != null && it.estado.voice == VoiceState.invite,
  );
  await settle();
  final english = it.estado.sessionId!;
  it.sala.leaveThePassage();
  await waitFor('the way back', () => it.estado.theWayBackIsLive);
  it.sala.chooseTheLanguage('pt');
  await settle();
  return (it, english);
}

Future<void> _backInTheSession(Sala it, String session) async {
  await it.sala.returnToTheLeftEntry();
  await waitFor(
    'the team to be back in the session',
    () => it.estado.sessionId == session,
  );
  await settle();
}

Future<Sala> _aPortugueseRehearsalReachedAgainInEnglish() async {
  final it = await umEnsaioDeTresPartesContadoInteiro();
  await pedirOVeredito(it);
  final portuguese = it.estado.sessionId!;
  it.sala.leaveThePassage();
  await waitFor('the way back', () => it.estado.theWayBackIsLive);
  it.sala.chooseTheLanguage('en');
  await settle();
  await _backInTheSession(it, portuguese);
  await intoTheBackTranslation(it.sala, () => it.estado);
  await theClipOpens(it.harness);
  it.harness.playback.finishPlayback();
  await waitFor('the clip to end', () => it.estado.btClipEnded);
  await pedirOVeredito(it);
  return it;
}

void main() {
  test(
    'the lines warmed when the team goes back into an English session are warmed in the room language',
    () async {
      final (it, english) =
          await _anEnglishSessionReachedAgainAfterPtWasTapped();
      it.harness.voice.readied.clear();

      await _backInTheSession(it, english);

      expect(it.harness.voice.readied, isNotEmpty);
      expect(it.harness.voice.readied.map((it) => it.$2), everyElement('pt'));
    },
  );

  test(
    'a fixed line the server names for a turn plays in the language of the session, not of the room',
    () async {
      final (it, english) = await _anEnglishSessionReachedAgainAfterPtWasTapped(
        turnFixedLine: 'D1',
      );
      await _backInTheSession(it, english);
      it.harness.voice.fixedLines.clear();

      it.sala.conversaTap();
      await settle();
      it.sala.conversaTap();
      await waitFor(
        'her line for the turn',
        () => it.harness.voice.fixedLines.any((line) => line.$1 == 'D1'),
      );

      expect(it.harness.voice.fixedLines, contains(('D1', 'en')));
    },
  );

  test(
    'a fixed line the server names for a turn is fetched in the language of the session before it plays',
    () async {
      final (it, english) = await _anEnglishSessionReachedAgainAfterPtWasTapped(
        turnFixedLine: 'D1',
      );
      await _backInTheSession(it, english);
      it.harness.voice.readied.clear();

      it.sala.conversaTap();
      await settle();
      it.sala.conversaTap();
      await waitFor(
        'her line for the turn',
        () => it.harness.voice.readied.any((line) => line.$1 == 'D1'),
      );

      expect(it.harness.voice.readied, contains(('D1', 'en')));
    },
  );

  test(
    'the approval line is spoken in the room language, whatever language the session was opened in',
    () async {
      final it = await _aPortugueseRehearsalReachedAgainInEnglish();
      it.harness.voice.fixedLines.clear();

      await it.sala.aprovarRascunhoFinal();
      await settle();

      expect(it.harness.voice.fixedLines, contains((approvedLine, 'en')));
      expect(
        it.harness.voice.fixedLines,
        isNot(contains((approvedLine, 'pt'))),
      );
    },
  );

  test(
    'the line the room names when a part is still unheard plays in the room language',
    () async {
      final it = await _aPortugueseRehearsalReachedAgainInEnglish();
      it.harness.room
        ..verdictRefusal = CheckRefusal.partUnheard
        ..verdictFixedLine = 'P2'
        ..verdictUnheardTakeIds = [it.estado.partes.first.takeId!];
      it.harness.voice.fixedLines.clear();

      await pedirOVeredito(it);

      expect(it.harness.voice.fixedLines, contains(('P2', 'en')));
    },
  );

  test(
    'the line the room names when a told frase awaits plays in the room language',
    () async {
      final it = await _aPortugueseRehearsalReachedAgainInEnglish();
      it.harness.room
        ..verdictRefusal = CheckRefusal.fraseAwaiting
        ..verdictFixedLine = 'N5'
        ..verdictUntoldSegmentId = 'trecho-1';
      it.harness.voice.fixedLines.clear();

      await pedirOVeredito(it);

      expect(it.harness.voice.fixedLines, contains(('N5', 'en')));
    },
  );

  test(
    'the line the room names when a stretch is untranslated plays in the room language',
    () async {
      final it = await _aPortugueseRehearsalReachedAgainInEnglish();
      it.harness.room
        ..verdictRefusal = CheckRefusal.stretchUntranslated
        ..verdictFixedLine = 'N2';
      it.harness.voice.fixedLines.clear();

      await pedirOVeredito(it);

      expect(it.harness.voice.fixedLines, contains(('N2', 'en')));
    },
  );

  test(
    'an English Panorama left before it was heard is opened again in English, in its own session, on the next tap',
    () async {
      final harness = SalaHarness(lingua: null)
        ..room.passages = const [
          Passagem(
            pericope: 'panorama',
            audioUrl: '/voice/panorama',
            kind: PassagemKind.panorama,
          ),
          Passagem(pericope: 'P01', audioUrl: '/voice/p01'),
        ];
      final container = harness.container();
      addTearDown(container.dispose);
      final it = Sala(harness, container);
      it.sala.chooseTheLanguage('en');
      await settle();
      harness.voice.holdNextFetch();
      await enterThePanorama(it.sala, () => it.estado);
      await waitFor(
        'the Panorama session to be asked for',
        () => harness.room.languagesSent.length == 1,
      );
      it.sala.leaveThePassage();
      harness.voice.finishHeldFetch();
      await waitFor('the way back', () => it.estado.theWayBackIsLive);
      it.sala.chooseTheLanguage('pt');
      await settle();
      harness.room.reachable = false;
      await it.sala.returnToTheLeftEntry();
      await settle();

      harness.room.reachable = true;
      it.sala.panoramaTap();
      await waitFor('the Panorama to be said', () => it.estado.panoramaSaid);

      expect(harness.room.languagesSent, ['en']);
      expect(harness.room.sessionsSpokenTo, isNotEmpty);
      expect(
        harness.room.sessionsSpokenTo,
        everyElement(harness.room.sessionIds.first),
      );
    },
  );

  test(
    'a fixed line the server names in a Panorama plays in the language the Panorama was opened in',
    () async {
      final harness = SalaHarness(lingua: null)
        ..room.fixedLine = 'D1'
        ..room.passages = const [
          Passagem(
            pericope: 'panorama',
            audioUrl: '/voice/panorama',
            kind: PassagemKind.panorama,
          ),
          Passagem(pericope: 'P01', audioUrl: '/voice/p01'),
        ];
      final container = harness.container();
      addTearDown(container.dispose);
      final it = Sala(harness, container);
      it.sala.chooseTheLanguage('en');
      await settle();
      await enterThePanorama(it.sala, () => it.estado);
      await waitFor('the Panorama to be said', () => it.estado.panoramaSaid);
      await settle();
      it.sala.leaveThePassage();
      await waitFor('the way back', () => it.estado.theWayBackIsLive);
      it.sala.chooseTheLanguage('pt');
      await settle();
      await it.sala.returnToTheLeftEntry();
      await waitFor(
        'the Panorama to be back',
        () =>
            it.estado.stage == SalaStage.panorama &&
            it.estado.panoramaSaid &&
            it.estado.voice == VoiceState.invite,
      );
      await settle();
      it.harness.voice.fixedLines.clear();

      it.sala.panoramaTap();
      await settle();
      it.sala.panoramaTap();
      await waitFor(
        'her line for the turn',
        () => it.harness.voice.fixedLines.any((line) => line.$1 == 'D1'),
      );

      expect(it.harness.voice.fixedLines, contains(('D1', 'en')));
    },
  );

  test(
    'the acknowledgement plays in the room language after a Panorama is reached again, whatever language it was opened in',
    () async {
      final harness = SalaHarness(lingua: null)
        ..room.passages = const [
          Passagem(
            pericope: 'panorama',
            audioUrl: '/voice/panorama',
            kind: PassagemKind.panorama,
          ),
          Passagem(pericope: 'P01', audioUrl: '/voice/p01'),
        ];
      final container = harness.container();
      addTearDown(container.dispose);
      final it = Sala(harness, container);
      it.sala.chooseTheLanguage('en');
      await settle();
      await enterThePanorama(it.sala, () => it.estado);
      await waitFor('the Panorama to be said', () => it.estado.panoramaSaid);
      await settle();
      it.sala.leaveThePassage();
      await waitFor('the way back', () => it.estado.theWayBackIsLive);
      it.sala.chooseTheLanguage('pt');
      await settle();
      await it.sala.returnToTheLeftEntry();
      await waitFor(
        'the Panorama to be back',
        () =>
            it.estado.stage == SalaStage.panorama &&
            it.estado.panoramaSaid &&
            it.estado.voice == VoiceState.invite,
      );
      await settle();
      it.harness.voice.fixedLines.clear();

      it.sala.panoramaTap();
      await settle();
      it.sala.panoramaTap();
      await waitFor(
        'the acknowledgement to be said',
        () => it.harness.voice.fixedLines.isNotEmpty,
      );

      expect(it.harness.voice.fixedLines.first.$2, 'pt');
    },
  );
}
