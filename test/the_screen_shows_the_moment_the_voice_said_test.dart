import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/moment.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart';

Future<void> _theOpeningSays(WidgetTester tester, Moment moment) async {
  final harness = SalaHarness()
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
}
