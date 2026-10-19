import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show byLabel, stateReads;
import 'the_kept_retellings_are_numbered_buttons_on_the_conversation_test.dart'
    show aKept, atRestAfterATurn;

final _first = byLabel('Hear how you told part 1');

double _opacity(WidgetTester tester) => tester
    .widgetList<AnimatedOpacity>(
      find.ancestor(of: _first, matching: find.byType(AnimatedOpacity)),
    )
    .fold(1.0, (opacity, fade) => opacity * fade.opacity);

bool _deaf(WidgetTester tester) => tester
    .widgetList<IgnorePointer>(
      find.ancestor(of: _first, matching: find.byType(IgnorePointer)),
    )
    .any((pointer) => pointer.ignoring);

void _expectAway(WidgetTester tester, {required String reason}) {
  expect(_first, findsOneWidget, reason: 'os botões não estavam montados');
  expect(_opacity(tester), 0.0, reason: reason);
  expect(_deaf(tester), isTrue);
  expect(
    tester.getSemantics(_first),
    isSemantics(hasTapAction: false),
    reason: 'o leitor de tela ainda abria o take',
  );
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  Duration beat = const Duration(milliseconds: 100),
}) async {
  for (var vez = 0; vez < 30 && !done(); vez++) {
    await tester.pump(beat);
  }
}

Future<(SalaHarness, ProviderContainer)> _atRest(
  WidgetTester tester, {
  bool watching = false,
}) async {
  final (harness, container) = await atRestAfterATurn(tester, [
    aKept('S1', 2),
    aKept('S2', 4),
    aKept('S3', 6),
  ], watching: watching);
  expect(
    _opacity(tester),
    1.0,
    reason: 'em repouso os botões estavam apagados',
  );
  expect(_deaf(tester), isFalse);
  return (harness, container);
}

void main() {
  testWidgets(
    'the buttons go, and take no touch, while the microphone listens',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final (_, container) = await _atRest(tester);

      container.read(salaSessionProvider.notifier).conversaTap();
      await tester.pump(const Duration(milliseconds: 500));

      expect(container.read(salaSessionProvider).voice, VoiceState.listening);
      _expectAway(tester, reason: 'os botões ficaram com o microfone aberto');
      semantics.dispose();
    },
  );

  testWidgets('the buttons go, and take no touch, while the voice thinks', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final (harness, container) = await _atRest(tester);
    final notifier = container.read(salaSessionProvider.notifier);
    harness.room.holdNextTurn();
    notifier.conversaTap();
    await tester.pump(const Duration(milliseconds: 300));
    notifier.conversaTap();
    await _pumpUntil(
      tester,
      () => container.read(salaSessionProvider).voice == VoiceState.thinking,
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(container.read(salaSessionProvider).voice, VoiceState.thinking);
    _expectAway(tester, reason: 'os botões ficaram com a voz pensando');
    harness.room.finishHeldTurn();
    await _pumpUntil(
      tester,
      () => container.read(salaSessionProvider).voice == VoiceState.invite,
    );
    semantics.dispose();
  });

  testWidgets('the buttons go, and take no touch, while the voice speaks', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final (harness, container) = await _atRest(tester);
    final notifier = container.read(salaSessionProvider.notifier);
    harness.voice.holdNextLine();
    notifier.conversaTap();
    await tester.pump(const Duration(milliseconds: 300));
    notifier.conversaTap();
    await _pumpUntil(
      tester,
      () => container.read(salaSessionProvider).voice == VoiceState.speaking,
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(container.read(salaSessionProvider).voice, VoiceState.speaking);
    _expectAway(tester, reason: 'os botões ficaram com a voz falando');
    harness.voice.finishHeldLine();
    await _pumpUntil(
      tester,
      () => container.read(salaSessionProvider).voice != VoiceState.speaking,
    );
    semantics.dispose();
  });

  testWidgets(
    'the buttons go, and take no touch, while the screen calls a person',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final (harness, container) = await _atRest(tester, watching: true);

      harness.room
        ..serverStatus = 'needs_person'
        ..serverHalt = HaltKind.blocking;
      final reads = stateReads(harness);
      await _pumpUntil(
        tester,
        () => stateReads(harness) != reads,
        beat: const Duration(seconds: 1),
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(container.read(salaSessionProvider).needsPerson, isTrue);
      _expectAway(
        tester,
        reason: 'os botões ficaram com a tela chamando uma pessoa',
      );
      semantics.dispose();
      closeTheRoom(container);
    },
  );

  testWidgets(
    'the buttons go, and take no touch, while a note for the facilitator is armed',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final (_, container) = await _atRest(tester);

      container.read(salaSessionProvider.notifier).handTap();
      await tester.pump(const Duration(milliseconds: 500));

      final session = container.read(salaSessionProvider);
      expect(session.noteMode, isTrue);
      expect(session.voice, VoiceState.invite);
      _expectAway(tester, reason: 'os botões ficaram com o bilhete armado');
      semantics.dispose();
    },
  );
}
