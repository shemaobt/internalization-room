import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/moment.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;

Finder _named(String prefix) => find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      (widget.properties.label?.startsWith(prefix) ?? false),
);

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
    'the passage screen in the Conversation carries no session-moment chip',
    (tester) async {
      await _theOpeningSays(
        tester,
        const Moment(at: MomentAt.familiarization, parts: 4),
      );

      expect(_named('Momento da sessão'), findsNothing);
      expect(find.text('Familiarização · a passagem inteira'), findsNothing);
    },
  );

  testWidgets('the Ensaio Final carries no session-moment chip either', (
    tester,
  ) async {
    await _theOpeningSays(
      tester,
      const Moment(at: MomentAt.ensaioFinal, parts: 4),
    );

    expect(_named('Momento da sessão'), findsNothing);
    expect(find.text('Ensaio Final · a passagem inteira'), findsNothing);
  });

  testWidgets('an English passage screen carries no «Session moment» chip', (
    tester,
  ) async {
    await _theOpeningSays(
      tester,
      const Moment(at: MomentAt.familiarization, parts: 4),
      lingua: 'en',
    );

    expect(_named('Session moment'), findsNothing);
    expect(find.text('Familiarization · the whole passage'), findsNothing);
  });
}
