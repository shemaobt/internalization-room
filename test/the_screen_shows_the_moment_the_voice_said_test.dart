import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/moment.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/presentation/widgets/moment_label.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart';

const _familiarizationLabel =
    'Momento da sessão: Familiarização · a passagem inteira';

double _labelOpacity(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(
      find.ancestor(
        of: byLabel(_familiarizationLabel),
        matching: find.byType(AnimatedOpacity),
      ),
    )
    .opacity;

Future<(SalaHarness, ProviderContainer)> _theOpeningSays(
  WidgetTester tester,
  Moment moment, {
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

void main() {
  testWidgets(
    'a label with no separator shows whole instead of breaking the screen',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: MomentLabel(
              moment: Moment(at: MomentAt.familiarization, parts: 4),
              words: 'Familiarização',
              language: 'pt',
            ),
          ),
        ),
      );

      expect(
        tester.takeException(),
        isNull,
        reason:
            'uma etiqueta sem o separador derrubava a tela no meio do build',
      );
      expect(byLabel('Momento da sessão: Familiarização'), findsOneWidget);
    },
  );

  testWidgets(
    'the opening that begins the Familiarization puts it on the screen as the voice starts',
    (tester) async {
      await _theOpeningSays(
        tester,
        const Moment(at: MomentAt.familiarization, parts: 4),
      );

      expect(
        byLabel('Momento da sessão: Familiarização · a passagem inteira'),
        findsOneWidget,
        reason: 'a voz abriu a Familiarização e a tela não mostrou o momento',
      );
    },
  );

  for (final MapEntry(key: words, value: moment) in _herWords.entries) {
    testWidgets(
      'a reply in another moment puts her words for it on the screen: $words',
      (tester) async {
        await _theOpeningSays(tester, moment);

        expect(
          byLabel('Momento da sessão: $words'),
          findsOneWidget,
          reason: 'a tela não mostrou o momento com as palavras dela',
        );
      },
    );
  }

  for (final MapEntry(key: words, value: moment) in _herEnglishWords.entries) {
    testWidgets(
      'an English tablet shows the moment in her English words: $words',
      (tester) async {
        await _theOpeningSays(tester, moment, lingua: 'en');

        expect(
          byLabel('Session moment: $words'),
          findsOneWidget,
          reason: 'o tablet em inglês mostrou o momento em português',
        );
      },
    );
  }

  testWidgets(
    'the label dims while the voice speaks and comes back when it stops',
    (tester) async {
      final (harness, _) = await _theOpeningSays(
        tester,
        const Moment(at: MomentAt.familiarization, parts: 4),
        heldMidLine: true,
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        _labelOpacity(tester),
        0.6,
        reason: 'o momento disputava a atenção com a voz enquanto ela falava',
      );

      harness.voice.finishHeldLine();
      await tester.pump(const Duration(milliseconds: 400));
      expect(_labelOpacity(tester), 1.0);
    },
  );

  testWidgets('the label goes while the screen calls for a person', (
    tester,
  ) async {
    final (harness, container) = await _theOpeningSays(
      tester,
      const Moment(at: MomentAt.familiarization, parts: 4),
      watching: true,
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(_labelOpacity(tester), 1.0);

    harness.room
      ..serverStatus = 'needs_person'
      ..serverHalt = HaltKind.blocking;
    final reads = stateReads(harness);
    var vez = 0;
    while (stateReads(harness) == reads && vez < 30) {
      await tester.pump(const Duration(seconds: 1));
      vez++;
    }
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      _labelOpacity(tester),
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
        const Moment(at: MomentAt.familiarization, parts: 4),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(_labelOpacity(tester), 1.0);

      container.read(salaSessionProvider.notifier).handTap();
      await tester.pump(const Duration(milliseconds: 400));

      expect(container.read(salaSessionProvider).noteMode, isTrue);
      expect(
        _labelOpacity(tester),
        0.0,
        reason:
            'a equipe abriu um recado e o momento continuou disputando a tela',
      );
    },
  );
}

const _herWords = {
  'Internalização · cena 2 de 4': Moment(
    at: MomentAt.internalization,
    part: 2,
    parts: 4,
  ),
  'Articulação · cena 2 de 4': Moment(
    at: MomentAt.articulation,
    part: 2,
    parts: 4,
  ),
  'Ensaio Final · a passagem inteira': Moment(
    at: MomentAt.ensaioFinal,
    parts: 4,
  ),
};

const _herEnglishWords = {
  'Familiarization · the whole passage': Moment(
    at: MomentAt.familiarization,
    parts: 4,
  ),
  'Internalization · scene 2 of 4': Moment(
    at: MomentAt.internalization,
    part: 2,
    parts: 4,
  ),
  'Articulation · scene 2 of 4': Moment(
    at: MomentAt.articulation,
    part: 2,
    parts: 4,
  ),
  'Final Rehearsal · the whole passage': Moment(
    at: MomentAt.ensaioFinal,
    parts: 4,
  ),
};
