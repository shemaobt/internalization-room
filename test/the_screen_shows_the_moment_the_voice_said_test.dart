import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/moment.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart';

Future<void> _theOpeningSays(
  WidgetTester tester,
  Moment moment, {
  String lingua = 'pt',
}) async {
  final harness = SalaHarness(lingua: lingua)
    ..room.passages = const [Passagem(pericope: 'P01', audioUrl: '/voice/p01')]
    ..room.nextMoment = moment;
  final container = await pumpSala(tester, harness);
  addTearDown(() => closeTheRoom(container));
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.abrirEscolha();
  await tester.pump(const Duration(milliseconds: 300));
  unawaited(notifier.goConversa(pericope: 'P01'));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
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

  testWidgets('an English tablet shows the moment in her English words', (
    tester,
  ) async {
    await _theOpeningSays(
      tester,
      const Moment(at: MomentAt.internalization, part: 2, parts: 4),
      lingua: 'en',
    );

    expect(
      byLabel('Session moment: Internalization · scene 2 of 4'),
      findsOneWidget,
      reason: 'o tablet em inglês mostrou o momento em português',
    );
  });
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
