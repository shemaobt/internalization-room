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
  notifier.openTheEntry(container.read(salaSessionProvider).naRoda!.first);
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _theCircleReadsWhileTheTeamRecords(
  WidgetTester tester, {
  required String? lingua,
  required String words,
}) async {
  final harness = SalaHarness(
    lingua: lingua ?? testLanguage,
    filaEmMemoria: true,
  );
  final container = await _pump(tester, harness);
  await _enterThePanorama(tester, harness, container);

  expect(byLabel(words), findsOneWidget);
  await tester.tap(byLabel(words));
  await tester.pump(const Duration(milliseconds: 200));

  expect(
    container.read(salaSessionProvider).voice,
    VoiceState.listening,
    reason: 'o toque depois da abertura grava a resposta da equipe',
  );
  expect(
    byLabel(words),
    findsOneWidget,
    reason:
        'o círculo trocava para um rótulo de gravação que o dela não tem; '
        'o dela diz sempre o mesmo',
  );
}

void main() {
  testWidgets(
    'the Panorama circle still reads «Toque para falar» while the team '
    'records, never a recording line',
    (tester) async {
      await _theCircleReadsWhileTheTeamRecords(
        tester,
        lingua: null,
        words: 'Toque para falar',
      );
    },
  );

  testWidgets(
    'an English Panorama circle still reads «Tap to speak» while the team '
    'records, never a recording line',
    (tester) async {
      await _theCircleReadsWhileTheTeamRecords(
        tester,
        lingua: 'en',
        words: 'Tap to speak',
      );
    },
  );

  Future<void> raiseTheHand(
    WidgetTester tester, {
    required String? lingua,
    required String words,
  }) async {
    final harness = SalaHarness(lingua: lingua ?? testLanguage)
      ..room.peerCue = true;
    final container = await _pump(tester, harness);
    final notifier = container.read(salaSessionProvider.notifier);
    notifier.goConversa(book: 'Ruth');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    expect(container.read(salaSessionProvider).peerCue, isTrue);
    expect(onTheCircle(words), findsOneWidget);

    notifier.handTap();
    await tester.pump(const Duration(milliseconds: 200));

    expect(container.read(salaSessionProvider).noteMode, isTrue);
    expect(onTheCircle(words), findsOneWidget);
  }

  testWidgets('a raised hand in an English room reads the plain label on the '
      'circle', (tester) async {
    await raiseTheHand(tester, lingua: 'en', words: 'Tap to speak');
  });

  testWidgets('a raised hand in a Portuguese room reads the plain label on the '
      'circle', (tester) async {
    await raiseTheHand(tester, lingua: null, words: 'Toque para falar');
  });
}
