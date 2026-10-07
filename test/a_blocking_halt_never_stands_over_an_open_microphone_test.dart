import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/main.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';
import 'session_notifier_test.dart' show inConversa;

Future<ProviderContainer> _reopensIntoRetro(SalaHarness harness) async {
  final gravada = File(
    '${Directory.systemTemp.createTempSync('sala-1168').path}/p1.m4a',
  )..writeAsBytesSync([1, 2, 3]);
  addTearDown(() => gravada.parent.deleteSync(recursive: true));
  harness.emAberto.rows['Ruth/P01'] = ResumePoint(
    sessionId: 'sessao-antiga',
    stage: SalaStage.retro,
    takes: [
      KeptTake(
        scopeId: KeptScope.parte(1),
        path: gravada.path,
        takeId: 'gravacao-1',
      ),
    ],
  );
  final container = harness.container();
  addTearDown(container.dispose);
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.abrirEscolha();
  await settle();
  await notifier.goConversa(pericope: 'P01');
  await settle();
  return container;
}

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
    'a blocking halt closes and discards the capture\'s microphone',
    () async {
      final harness = SalaHarness();
      final container = await _reopensIntoRetro(harness);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);

      harness.playback.at = const Duration(seconds: 2);
      notifier.cortarTrecho();
      notifier.retroTap();
      await waitFor(
        'a captura abrir',
        () => read().btPhase == BtPhase.capturing,
      );
      await waitFor('o microfone abrir', () => harness.recorder.captures == 1);

      notifier.haltForABrokenBuild();
      await settle();

      _expectTheMicrophoneClosedAndDiscarded(harness, read());
      expect(read().btPhase, isNot(BtPhase.capturing));
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

  testWidgets('after a lift over an open microphone, the way out is there and '
      'answers a tap', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = harness.container();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SalaApp()),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.goConversa();
    await tester.pump(const Duration(milliseconds: 300));

    notifier.conversaTap();
    await tester.pump(const Duration(milliseconds: 100));
    expect(harness.recorder.captures, 1, reason: 'o microfone abriu');

    notifier.haltForABrokenBuild();
    await tester.pump(const Duration(milliseconds: 100));
    notifier.resolveWithPerson();
    await tester.pump(const Duration(milliseconds: 500));

    expect(harness.recorder.deleted, hasLength(1), reason: 'descartado');
    await tester.tap(byLabel('Escolher outra passagem'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      container.read(salaSessionProvider).stage,
      SalaStage.escolha,
      reason: 'a saída respondeu ao toque',
    );
  });
}
