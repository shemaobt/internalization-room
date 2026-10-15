import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';

const _thePanorama = Passagem(
  pericope: 'panorama',
  audioUrl: '/voice/panorama',
  kind: PassagemKind.panorama,
);

Future<ProviderContainer> _pump(
  WidgetTester tester,
  SalaHarness harness,
) async {
  final container = harness.container();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await tester.pump(const Duration(milliseconds: 100));
  return container;
}

Future<void> _enterThePanorama(
  WidgetTester tester,
  SalaHarness harness,
  ProviderContainer container,
) async {
  harness.room.passages = [_thePanorama, ...harness.room.passages];
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.abrirEscolha();
  await tester.pump(const Duration(milliseconds: 300));
  notifier.entrarNaOferecida();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _theCircleReadsWhileTheTeamRecords(
  WidgetTester tester, {
  required String? lingua,
  required String resting,
  required String recording,
}) async {
  final harness = SalaHarness(
    lingua: lingua ?? testLanguage,
    filaEmMemoria: true,
  );
  final container = await _pump(tester, harness);
  await _enterThePanorama(tester, harness, container);

  expect(byLabel(resting), findsOneWidget);
  await tester.tap(byLabel(resting));
  await tester.pump(const Duration(milliseconds: 200));

  expect(
    container.read(salaSessionProvider).voice,
    VoiceState.listening,
    reason: 'o toque depois da abertura grava a resposta da equipe',
  );
  expect(byLabel(recording), findsOneWidget);
  expect(byLabel(resting), findsNothing);
}

void main() {
  testWidgets(
    'the Panorama circle reads «Tocar ao terminar» while the team records',
    (tester) async {
      await _theCircleReadsWhileTheTeamRecords(
        tester,
        lingua: null,
        resting: 'Falar com o facilitador',
        recording: 'Tocar ao terminar',
      );
    },
  );

  testWidgets(
    'an English Panorama circle reads «Tap when you are done» while the team '
    'records',
    (tester) async {
      await _theCircleReadsWhileTheTeamRecords(
        tester,
        lingua: 'en',
        resting: 'Talk to the facilitator',
        recording: 'Tap when you are done',
      );
    },
  );

  Future<void> raiseTheHand(
    WidgetTester tester, {
    required String? lingua,
    required String question,
    required String teamTalk,
  }) async {
    final harness = SalaHarness(lingua: lingua ?? testLanguage)
      ..room.peerCue = true;
    final container = await _pump(tester, harness);
    final notifier = container.read(salaSessionProvider.notifier);
    notifier.goConversa();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    expect(byLabel(teamTalk), findsOneWidget);

    notifier.handTap();
    await tester.pump(const Duration(milliseconds: 200));

    expect(container.read(salaSessionProvider).noteMode, isTrue);
    expect(byLabel(question), findsOneWidget);
    expect(byLabel(teamTalk), findsNothing);
  }

  testWidgets('a raised hand in an English room reads the plain label on the '
      'circle', (tester) async {
    await raiseTheHand(
      tester,
      lingua: 'en',
      question: 'Tap to speak',
      teamTalk: 'Talk among yourselves — tap when you want to tell me',
    );
  });

  testWidgets('a raised hand in a Portuguese room reads the plain label on the '
      'circle', (tester) async {
    await raiseTheHand(
      tester,
      lingua: null,
      question: 'Tocar para falar',
      teamTalk: 'Conversem entre vocês — tocar quando quiserem me contar',
    );
  });
}
