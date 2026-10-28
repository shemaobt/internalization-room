import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart';

const _theSign = 'Um momento para uma pessoa';
const _hearAgain = 'Ouvir de novo';
const _theRetryFaces = ['Tocar para tentar de novo', 'Tap to try again'];

typedef _Sala = ({
  WidgetTester tester,
  SalaHarness harness,
  ProviderContainer container,
});

SalaSessionState _read(_Sala sala) => sala.container.read(salaSessionProvider);

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

Future<_Sala> _atRestInTheConversation(WidgetTester tester) async {
  final harness = SalaHarness(filaEmMemoria: true)
    ..room.passages = const [Passagem(pericope: 'P01', audioUrl: '/voice/p01')];
  final container = await pumpSala(tester, harness);
  final sala = (tester: tester, harness: harness, container: container);
  await _until(sala, 'the Choice to be listed', () => _read(sala).entriesOpen);
  unawaited(
    container
        .read(salaSessionProvider.notifier)
        .goConversa(book: 'Ruth', pericope: 'P01'),
  );
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

Future<void> _speak(_Sala sala) async {
  await sala.tester.tap(find.byType(FacilitatorCircle));
  await _pass(sala);
  await sala.tester.tap(find.byType(FacilitatorCircle));
  await _pass(sala);
}

void main() {
  testWidgets(
    'losing the connection during a session speaks no line and shows no '
    'offline face',
    (tester) async {
      final sala = await _atRestInTheConversation(tester);
      final played = sala.harness.voice.played.length;
      final assets = sala.harness.voice.assets.length;
      final fixedLines = sala.harness.voice.fixedLines.length;
      sala.harness.room.reachable = false;

      await _speak(sala);
      await _until(sala, 'the person sign', () => _read(sala).needsPerson);
      await _pass(sala, 30);

      expect(byLabel(_theSign), findsOneWidget);
      expect(sala.harness.voice.played, hasLength(played));
      expect(sala.harness.voice.assets, hasLength(assets));
      expect(
        sala.harness.voice.fixedLines,
        hasLength(fixedLines + 1),
        reason: 'the acknowledgement and nothing else',
      );
      for (final face in _theRetryFaces) {
        expect(byLabel(face), findsNothing);
      }
      closeTheRoom(sala.container);
    },
  );

  testWidgets(
    'a turn answered with her fail-safe line says it and shows nothing more',
    (tester) async {
      final sala = await _atRestInTheConversation(tester);
      sala.harness.room
        ..turnsAreCanned = true
        ..turnsAreDegraded = true;
      final played = sala.harness.voice.played.length;
      final texts = find.byType(Text).evaluate().length;

      await _speak(sala);
      await _until(
        sala,
        'the room to rest after the reply',
        () =>
            sala.harness.voice.played.length == played + 1 &&
            _read(sala).voice == VoiceState.invite &&
            !_read(sala).awaitingTheGuide,
      );
      await _pass(sala, 20);

      expect(sala.harness.voice.played.last, turnoUrl);
      expect(byLabel(_theSign), findsNothing);
      expect(byLabel(_hearAgain).hitTestable(), findsOneWidget);
      expect(find.byType(Text).evaluate().length, texts);
      closeTheRoom(sala.container);
    },
  );
}
