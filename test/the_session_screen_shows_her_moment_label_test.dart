import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/moment.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/moment_label.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show stateReads;

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

Color? _dot(WidgetTester tester) => tester
    .widgetList<DecoratedBox>(
      find.descendant(of: _label, matching: find.byType(DecoratedBox)),
    )
    .map((box) => box.decoration)
    .whereType<BoxDecoration>()
    .firstWhere((decoration) => decoration.shape == BoxShape.circle)
    .color;

double _opacity(WidgetTester tester) => tester
    .widgetList<AnimatedOpacity>(
      find.ancestor(of: _label, matching: find.byType(AnimatedOpacity)),
    )
    .fold(1.0, (opacity, fade) => opacity * fade.opacity);

Future<(SalaHarness, ProviderContainer)> _theOpeningSays(
  WidgetTester tester,
  Moment? moment, {
  String lingua = 'pt',
  bool heldMidLine = false,
  bool watching = false,
}) async {
  final harness = SalaHarness(lingua: lingua, watchesWithoutAHalt: watching)
    ..room.passages = const [Passagem(pericope: 'P01', audioUrl: '/voice/p01')]
    ..room.nextMoment = moment;
  final container = await pumpSala(tester, harness);
  addTearDown(() => closeTheRoom(container));
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.abrirEscolha();
  await tester.pump(const Duration(milliseconds: 300));
  if (heldMidLine) harness.voice.holdNextLine();
  unawaited(notifier.goConversa(pericope: 'P01'));
  await tester.pump(const Duration(milliseconds: 300));
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

Future<void> _theNextReplySays(
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
  expect(container.read(salaSessionProvider).voice, VoiceState.speaking);
}

void main() {
  testWidgets(
    'the opening of a new session writes the Familiarização in her words and her teal',
    (tester) async {
      await _theOpeningSays(
        tester,
        const Moment(at: MomentAt.familiarization, parts: 3),
      );

      expect(
        _label,
        findsOneWidget,
        reason:
            'a voz abriu a Familiarização e a tela não mostrou momento algum',
      );
      expect(_shown(tester), 'Familiarização · a passagem inteira');
      expect(_dot(tester), const Color(0xFF2E6F63));
    },
  );

  testWidgets(
    'the reply that opens scene two turns the label violet as it starts to play',
    (tester) async {
      final (harness, container) = await _theOpeningSays(
        tester,
        const Moment(at: MomentAt.familiarization, parts: 3),
      );

      await _theNextReplySays(
        tester,
        harness,
        container,
        const Moment(at: MomentAt.internalization, part: 2, parts: 3),
      );

      expect(
        _shown(tester),
        'Internalização · cena 2 de 3',
        reason: 'a voz abriu a cena 2 e a tela ficou na Familiarização',
      );
      expect(_dot(tester), const Color(0xFF6A4C9C));
    },
  );

  testWidgets(
    'the reply that carries the practice of scene three turns the label red',
    (tester) async {
      final (harness, container) = await _theOpeningSays(
        tester,
        const Moment(at: MomentAt.internalization, part: 3, parts: 3),
      );

      await _theNextReplySays(
        tester,
        harness,
        container,
        const Moment(at: MomentAt.articulation, part: 3, parts: 3),
      );

      expect(
        _shown(tester),
        'Articulação · cena 3 de 3',
        reason:
            'a voz deu o ensaio da cena 3 e a tela seguiu na Internalização',
      );
      expect(_dot(tester), const Color(0xFFC8321E));
    },
  );

  testWidgets('the send-off turns the label to her orange Ensaio Final', (
    tester,
  ) async {
    await _theOpeningSays(
      tester,
      const Moment(at: MomentAt.ensaioFinal, parts: 3),
    );

    expect(
      _shown(tester),
      'Ensaio Final · a passagem inteira',
      reason: 'a voz mandou a equipe ao Ensaio Final e a tela não disse',
    );
    expect(_dot(tester), const Color(0xFFBE4A01));
  });

  testWidgets(
    'the Ensaio Final in the dark wears her orange, not the theme\'s',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(
            body: MomentLabel(
              at: MomentAt.ensaioFinal,
              words: 'Ensaio Final · a passagem inteira',
              aria: 'Momento da sessão',
            ),
          ),
        ),
      );

      expect(
        _dot(tester),
        const Color(0xFFD6612A),
        reason: 'no escuro o Ensaio Final usava o laranja do tema, #E36A1E',
      );
      expect(
        tester.widget<Text>(find.text('Ensaio Final')).style?.color,
        const Color(0xFFECEADC),
        reason: 'as palavras dela usavam a tinta do tema, não o verde dela',
      );
    },
  );

  testWidgets(
    'the label dims while the voice speaks, thinks or listens, and is whole at rest',
    (tester) async {
      final (harness, container) = await _theOpeningSays(
        tester,
        const Moment(at: MomentAt.familiarization, parts: 3),
        heldMidLine: true,
      );
      final notifier = container.read(salaSessionProvider.notifier);
      VoiceState voice() => container.read(salaSessionProvider).voice;

      expect(voice(), VoiceState.speaking);
      expect(
        _opacity(tester),
        0.6,
        reason: 'o momento disputava a atenção com a voz enquanto ela falava',
      );

      harness.voice.finishHeldLine();
      await tester.pump(const Duration(milliseconds: 400));
      expect(voice(), VoiceState.invite);
      expect(_opacity(tester), 1.0);

      harness.room.holdNextTurn();
      notifier.conversaTap();
      await tester.pump(const Duration(milliseconds: 300));
      expect(voice(), VoiceState.listening);
      expect(
        _opacity(tester),
        0.6,
        reason: 'o momento seguia inteiro com o microfone aberto',
      );

      notifier.conversaTap();
      await tester.pump(const Duration(milliseconds: 300));
      expect(voice(), VoiceState.thinking);
      expect(
        _opacity(tester),
        0.6,
        reason: 'o momento seguia inteiro enquanto a voz pensava',
      );

      harness.room.finishHeldTurn();
      await _pumpUntil(tester, () => voice() == VoiceState.invite);
    },
  );

  testWidgets('the label goes while the screen calls for a person', (
    tester,
  ) async {
    final (harness, container) = await _theOpeningSays(
      tester,
      const Moment(at: MomentAt.familiarization, parts: 3),
      watching: true,
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(_opacity(tester), 1.0);

    harness.room
      ..serverStatus = 'needs_person'
      ..serverHalt = HaltKind.blocking;
    final reads = stateReads(harness);
    await _pumpUntil(
      tester,
      () => stateReads(harness) != reads,
      beat: const Duration(seconds: 1),
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(container.read(salaSessionProvider).needsPerson, isTrue);
    expect(
      _opacity(tester),
      0.0,
      reason: 'a tela chamou o facilitador e o momento continuou ali',
    );
    closeTheRoom(container);
  });

  testWidgets(
    'the label goes while the team opens a note for the facilitator',
    (tester) async {
      final (_, container) = await _theOpeningSays(
        tester,
        const Moment(at: MomentAt.familiarization, parts: 3),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(_opacity(tester), 1.0);

      container.read(salaSessionProvider.notifier).handTap();
      await tester.pump(const Duration(milliseconds: 400));

      expect(container.read(salaSessionProvider).noteMode, isTrue);
      expect(
        _opacity(tester),
        0.0,
        reason:
            'a equipe abriu um recado e o momento continuou disputando a tela',
      );
    },
  );

  for (final MapEntry(key: words, value: moment) in _herEnglishWords.entries) {
    testWidgets('an English session shows her English words: $words', (
      tester,
    ) async {
      await _theOpeningSays(tester, moment, lingua: 'en');

      expect(
        _shown(tester),
        words,
        reason: 'o tablet em inglês mostrava o momento em português',
      );
    });
  }
}

const _herEnglishWords = {
  'Familiarization · the whole passage': Moment(
    at: MomentAt.familiarization,
    parts: 3,
  ),
  'Internalization · scene 2 of 3': Moment(
    at: MomentAt.internalization,
    part: 2,
    parts: 3,
  ),
  'Articulation · scene 1 of 3': Moment(
    at: MomentAt.articulation,
    part: 1,
    parts: 3,
  ),
  'Final Rehearsal · the whole passage': Moment(
    at: MomentAt.ensaioFinal,
    parts: 3,
  ),
};
