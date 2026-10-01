import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';

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

Future<ProviderContainer> _atTheConferida(
  WidgetTester tester,
  SalaHarness harness,
) async {
  harness.room.verdictChecked = true;
  final container = await _pump(tester, harness);
  final sala = container.read(salaSessionProvider.notifier);
  await sala.goConversa(pericope: 'P01');
  await tester.pump(const Duration(milliseconds: 200));
  sala.goEnsaio();
  sala.ensaioTap();
  sala.ensaioTap();
  await tester.pump(const Duration(milliseconds: 100));
  sala.takeKeep();
  await letTheRehearsalReachTheRoom(tester);
  sala.startRetro();
  await tester.pump(const Duration(milliseconds: 200));
  harness.playback.at = const Duration(seconds: 10);
  sala.cortarTrecho();
  sala.retroTap();
  await tester.pump(const Duration(milliseconds: 200));
  await confirmarATraducaoNaTela(tester, container);
  await tester.pump(const Duration(milliseconds: 600));
  harness.playback.finishPlayback();
  await tester.pump(const Duration(milliseconds: 200));
  await sala.finishBackTranslation();
  await tester.pump(const Duration(milliseconds: 300));
  expect(container.read(salaSessionProvider).btPhase, BtPhase.conferida);
  return container;
}

void main() {
  testWidgets('an approval refused while the recording was paused offers no '
      'Pausar and leaves the Channel silent', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _atTheConferida(tester, harness);
    final sala = container.read(salaSessionProvider.notifier);
    final pausar = byLabel(retroLabelFor('pause', testLanguage));

    sala.ouvirGravacao();
    await tester.pump(const Duration(milliseconds: 100));
    expect(pausar, findsOneWidget);
    sala.ouvirGravacao();
    await tester.pump(const Duration(milliseconds: 100));
    expect(pausar, findsNothing);

    harness.room.reachable = false;
    await sala.aprovarRascunhoFinal();
    await tester.pump(const Duration(milliseconds: 300));

    expect(pausar, findsNothing);
    expect(container.read(salaSessionProvider).channel, const Silence());
    closeTheRoom(container);
  });

  testWidgets('"Enviar a pergunta" shows only once the microphone opened for '
      'the question', (tester) async {
    final harness = SalaHarness();
    final container = await _pump(tester, harness);
    final sala = container.read(salaSessionProvider.notifier);
    final enviar = byLabel(circleLabelFor('noteMode', testLanguage));
    await sala.goConversa();
    await tester.pump(const Duration(milliseconds: 300));

    sala.handTap();
    await tester.pump(const Duration(milliseconds: 100));

    expect(container.read(salaSessionProvider).noteMode, isTrue);
    expect(enviar, findsNothing);

    sala.conversaTap();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      container.read(salaSessionProvider).channel,
      const Microphone(MicOwner.question),
    );
    expect(enviar, findsOneWidget);
    closeTheRoom(container);
  });
}
