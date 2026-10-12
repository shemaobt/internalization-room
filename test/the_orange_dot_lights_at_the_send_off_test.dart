import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/moment.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show stateReads;

final _dot = find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      (widget.properties.label == 'Gravar o ensaio de vocês' ||
          widget.properties.label == 'Record your rehearsal'),
);

final _label = find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      ((widget.properties.label?.startsWith('Momento da sessão') ?? false) ||
          (widget.properties.label?.startsWith('Session moment') ?? false)),
);

String _shown(WidgetTester tester) => tester
    .widgetList<Text>(find.descendant(of: _label, matching: find.byType(Text)))
    .map((text) => text.data)
    .join();

double _dotOpacity(WidgetTester tester) => tester
    .widgetList<AnimatedOpacity>(
      find.ancestor(of: _dot, matching: find.byType(AnimatedOpacity)),
    )
    .fold(1.0, (opacity, fade) => opacity * fade.opacity);

bool _dotIsDeaf(WidgetTester tester) => tester
    .widgetList<IgnorePointer>(
      find.ancestor(of: _dot, matching: find.byType(IgnorePointer)),
    )
    .any((pointer) => pointer.ignoring);

Color? _dotColour(WidgetTester tester) => tester
    .widgetList<DecoratedBox>(
      find.descendant(of: _dot, matching: find.byType(DecoratedBox)),
    )
    .map((box) => box.decoration)
    .whereType<BoxDecoration>()
    .firstWhere((decoration) => decoration.shape == BoxShape.circle)
    .color;

const _lastScene = Moment(at: MomentAt.articulation, part: 3, parts: 3);
const _sendOff = Moment(at: MomentAt.ensaioFinal, parts: 3);

Future<(SalaHarness, ProviderContainer)> _inTheLastScene(
  WidgetTester tester, {
  String lingua = 'pt',
  bool watching = false,
}) async {
  final harness = SalaHarness(lingua: lingua, watchesWithoutAHalt: watching)
    ..room.passages = const [Passagem(pericope: 'P01', audioUrl: '/voice/p01')]
    ..room.nextMoment = _lastScene;
  final container = await pumpSala(tester, harness);
  addTearDown(() => closeTheRoom(container));
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.abrirEscolha();
  await tester.pump(const Duration(milliseconds: 300));
  unawaited(notifier.goConversa(pericope: 'P01'));
  await _pumpUntil(
    tester,
    () => container.read(salaSessionProvider).voice == VoiceState.invite,
  );
  await tester.pump(const Duration(milliseconds: 500));
  return (harness, container);
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

Future<void> _theNextReplyPlays(
  WidgetTester tester,
  SalaHarness harness,
  ProviderContainer container,
  Moment moment,
) async {
  final notifier = container.read(salaSessionProvider.notifier);
  harness.room.nextMoment = moment;
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
}

Future<void> _theReplyEnds(
  WidgetTester tester,
  SalaHarness harness,
  ProviderContainer container,
) async {
  harness.voice.finishHeldLine();
  await _pumpUntil(
    tester,
    () => container.read(salaSessionProvider).voice != VoiceState.speaking,
  );
  await tester.pump(const Duration(milliseconds: 500));
}

Future<(SalaHarness, ProviderContainer)> _afterTheSendOff(
  WidgetTester tester, {
  bool watching = false,
}) async {
  final (harness, container) = await _inTheLastScene(
    tester,
    watching: watching,
  );
  await _theNextReplyPlays(tester, harness, container, _sendOff);
  await _theReplyEnds(tester, harness, container);
  expect(_dotOpacity(tester), 0.85);
  expect(_dotIsDeaf(tester), isFalse);
  return (harness, container);
}

void main() {
  testWidgets(
    'the send-off lights the dot as it starts, and the team first sees it when the voice ends',
    (tester) async {
      final (harness, container) = await _inTheLastScene(tester);
      expect(_dot, findsNothing);

      await _theNextReplyPlays(tester, harness, container, _sendOff);

      expect(_shown(tester), 'Ensaio Final · a passagem inteira');
      expect(
        _dot,
        findsOneWidget,
        reason: 'a despedida começou e o ponto só acenderia com o done',
      );
      expect(
        _dotOpacity(tester),
        0.0,
        reason: 'o ponto apareceu com a voz ainda falando',
      );
      expect(_dotIsDeaf(tester), isTrue);

      await _theReplyEnds(tester, harness, container);

      expect(harness.room.done, isFalse);
      expect(
        _dotOpacity(tester),
        0.85,
        reason: 'a despedida acabou e o ponto não acendeu sem o done da sala',
      );
      expect(_dotIsDeaf(tester), isFalse);
      expect(_dotColour(tester), const Color(0xFFBE4A01));
    },
  );

  testWidgets(
    'an English session lights the same dot on the English send-off, named in English',
    (tester) async {
      final (harness, container) = await _inTheLastScene(tester, lingua: 'en');

      await _theNextReplyPlays(tester, harness, container, _sendOff);

      expect(_shown(tester), 'Final Rehearsal · the whole passage');
      expect(_dotOpacity(tester), 0.0);

      await _theReplyEnds(tester, harness, container);

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label == 'Record your rehearsal',
        ),
        findsOneWidget,
        reason: 'a sessão em inglês dava ao ponto o nome em português',
      );
      expect(_dotOpacity(tester), 0.85);
      expect(_dotIsDeaf(tester), isFalse);
    },
  );

  testWidgets(
    'a reply the room keeps in the scene, the send-off not its last words, lights nothing',
    (tester) async {
      final (harness, container) = await _inTheLastScene(tester);

      await _theNextReplyPlays(tester, harness, container, _lastScene);
      await _theReplyEnds(tester, harness, container);

      expect(container.read(salaSessionProvider).voice, VoiceState.invite);
      expect(_shown(tester), 'Articulação · cena 3 de 3');
      expect(
        _dot,
        findsNothing,
        reason: 'o ponto acendeu numa resposta que a sala deixou na cena',
      );
    },
  );

  testWidgets(
    'a turn that reaches the floor before the send-off lights the dot and leaves the scene on the label',
    (tester) async {
      final (harness, container) = await _inTheLastScene(tester);
      harness.room
        ..done = true
        ..readsDone = false;

      await _theNextReplyPlays(tester, harness, container, _lastScene);
      await _theReplyEnds(tester, harness, container);

      expect(container.read(salaSessionProvider).voice, VoiceState.done);
      expect(_shown(tester), 'Articulação · cena 3 de 3');
      expect(
        _dotOpacity(tester),
        0.85,
        reason: 'a sala disse done e o ponto ficou apagado, ao contrário dela',
      );
      expect(_dotIsDeaf(tester), isFalse);
    },
  );

  testWidgets(
    'a read that reports the floor at rest lights the dot and leaves the scene on the label',
    (tester) async {
      final (harness, container) = await _inTheLastScene(
        tester,
        watching: true,
      );
      expect(_dot, findsNothing);

      harness.room.readsDone = true;
      final reads = stateReads(harness);
      await _pumpUntil(
        tester,
        () => stateReads(harness) != reads,
        beat: const Duration(seconds: 1),
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(container.read(salaSessionProvider).voice, VoiceState.done);
      expect(_shown(tester), 'Articulação · cena 3 de 3');
      expect(
        _dotOpacity(tester),
        0.85,
        reason:
            'a leitura disse done e o ponto ficou apagado, ao contrário dela',
      );
      expect(_dotIsDeaf(tester), isFalse);
      closeTheRoom(container);
    },
  );

  testWidgets(
    'the dot goes, and takes no touch, while the microphone listens',
    (tester) async {
      final (_, container) = await _afterTheSendOff(tester);

      container.read(salaSessionProvider.notifier).conversaTap();
      await tester.pump(const Duration(milliseconds: 500));

      expect(container.read(salaSessionProvider).voice, VoiceState.listening);
      expect(
        _dotOpacity(tester),
        0.0,
        reason: 'o ponto continuou aceso com o microfone aberto',
      );
      expect(_dotIsDeaf(tester), isTrue);
    },
  );

  testWidgets('the dot goes, and takes no touch, while the voice thinks', (
    tester,
  ) async {
    final (harness, container) = await _afterTheSendOff(tester);
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
    expect(
      _dotOpacity(tester),
      0.0,
      reason: 'o ponto continuou aceso com a voz pensando',
    );
    expect(_dotIsDeaf(tester), isTrue);
    harness.room.finishHeldTurn();
    await _pumpUntil(
      tester,
      () => container.read(salaSessionProvider).voice == VoiceState.invite,
    );
  });

  testWidgets(
    'the dot goes, and takes no touch, while the screen calls a person',
    (tester) async {
      final (harness, container) = await _afterTheSendOff(
        tester,
        watching: true,
      );

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
      expect(
        _dotOpacity(tester),
        0.0,
        reason: 'o ponto continuou aceso com a tela chamando o facilitador',
      );
      expect(_dotIsDeaf(tester), isTrue);
      closeTheRoom(container);
    },
  );
}
