import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show enterThePassage, settle;
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

void main() {
  test(
    'the lines warmed when the team goes back into an English session are warmed in English',
    () async {
      final (it, english) =
          await _anEnglishSessionReachedAgainAfterPtWasTapped();
      it.harness.voice.readied.clear();

      await _backInTheSession(it, english);

      expect(it.harness.voice.readied, isNotEmpty);
      expect(it.harness.voice.readied.map((it) => it.$2), everyElement('en'));
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
    'the approval line is spoken in the language the session was opened in, whatever the room language became',
    () async {
      final it = await umEnsaioDeTresPartesContadoInteiro();
      await pedirOVeredito(it);
      it.sala.chooseTheLanguage('en');
      await settle();
      it.harness.voice.fixedLines.clear();

      await it.sala.aprovarRascunhoFinal();
      await settle();

      expect(it.harness.voice.fixedLines, contains((approvedLine, 'pt')));
      expect(
        it.harness.voice.fixedLines,
        isNot(contains((approvedLine, 'en'))),
      );
    },
  );

  test(
    'a recorded line said inside an English session is recorded in English',
    () async {
      final (it, english) =
          await _anEnglishSessionReachedAgainAfterPtWasTapped();
      await _backInTheSession(it, english);

      it.sala.sayTheMicIsBlocked();
      await settle();

      expect(it.harness.voice.assets, [micBlockedAsset('en')]);
    },
  );

  test(
    'a recorded line said on the Choice is recorded in the room language, though a session was left in English',
    () async {
      final (it, english) =
          await _anEnglishSessionReachedAgainAfterPtWasTapped();

      it.sala.sayTheMicIsBlocked();
      await settle();

      expect(it.harness.voice.assets, [micBlockedAsset('pt')]);
    },
  );
}
