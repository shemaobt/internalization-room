import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/main.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';
import 'session_notifier_test.dart' show inConversa;

void _expectTheMicrophoneClosedAndDiscarded(
  SalaHarness harness,
  SalaSessionState state,
) {
  expect(state.needsPerson, isTrue, reason: 'a sala parou');
  expect(
    harness.recorder.deleted,
    hasLength(1),
    reason: 'o que o microfone ouviu até a parada foi descartado',
  );
  expect(
    state.voice,
    isNot(VoiceState.listening),
    reason: 'nenhum microfone fica aberto sob a parada',
  );
}

void main() {
  test('a blocking halt closes and discards the conversation\'s '
      'microphone', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    notifier.conversaTap();
    await waitFor('o microfone abrir', () => harness.recorder.captures == 1);

    notifier.haltForABrokenBuild();
    await settle();

    _expectTheMicrophoneClosedAndDiscarded(harness, read());
  });

  test(
    'a blocking halt closes and discards the rehearsal\'s microphone',
    () async {
      final harness = SalaHarness();
      final container = await inConversa(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);

      notifier.goEnsaio();
      notifier.ensaioTap();
      await waitFor('o microfone abrir', () => harness.recorder.captures == 1);

      notifier.haltForABrokenBuild();
      await settle();

      _expectTheMicrophoneClosedAndDiscarded(harness, read());
      expect(
        read().ensaio,
        isNot(EnsaioStatus.recording),
        reason: 'o ensaio não diz que grava',
      );
    },
  );

  test(
    'a blocking halt closes and discards the question\'s microphone',
    () async {
      final harness = SalaHarness();
      final container = await inConversa(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);

      notifier.handTap();
      notifier.conversaTap();
      await waitFor('o microfone abrir', () => harness.recorder.captures == 1);

      notifier.haltForABrokenBuild();
      await settle();

      _expectTheMicrophoneClosedAndDiscarded(harness, read());
      expect(read().noteMode, isFalse, reason: 'a pergunta não segue armada');
    },
  );

  testWidgets(
    'after a tap on the sign over an open microphone, the way out is there and '
    'answers a tap',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = harness.container();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const SalaApp()),
      );
      await tester.pump(const Duration(milliseconds: 100));
      final notifier = container.read(salaSessionProvider.notifier);
      await notifier.goConversa(book: 'Ruth');
      await tester.pump(const Duration(milliseconds: 300));

      notifier.conversaTap();
      await tester.pump(const Duration(milliseconds: 100));
      expect(harness.recorder.captures, 1, reason: 'o microfone abriu');

      notifier.haltForABrokenBuild();
      await tester.pump(const Duration(milliseconds: 100));
      notifier.teamTapped();
      await tester.pump(const Duration(milliseconds: 500));

      expect(harness.recorder.deleted, hasLength(1), reason: 'descartado');
      await tester.tap(byLabel('Escolher outra passagem'));
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        container.read(salaSessionProvider).stage,
        SalaStage.escolha,
        reason: 'a saída respondeu ao toque',
      );
    },
  );
}
