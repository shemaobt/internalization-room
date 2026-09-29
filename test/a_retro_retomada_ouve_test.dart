import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show settle;

const _traduzidos = BackTranslationProgress(
  segments: [
    SegmentView(
      segmentId: 'trecho-1',
      takeId: 'gravacao-1',
      startsMs: 0,
      endsMs: 12000,
    ),
  ],
);

/// A tablet closed part-way through a passage and opened again on it.
Future<ProviderContainer> _reopensInto(
  SalaHarness harness,
  SalaStage parouEm, {
  BackTranslationProgress contado = const BackTranslationProgress(),
}) async {
  final gravada = File(
    '${Directory.systemTemp.createTempSync('sala-687').path}/p1.m4a',
  )..writeAsBytesSync([1, 2, 3]);
  addTearDown(() => gravada.parent.deleteSync(recursive: true));
  harness.emAberto.rows['Ruth/P01'] = ResumePoint(
    sessionId: 'sessao-antiga',
    stage: parouEm,
    takes: [
      KeptTake(
        scopeId: KeptScope.parte(1),
        path: gravada.path,
        takeId: 'gravacao-1',
      ),
    ],
  );
  harness.room.retroSoFar = contado;
  final container = harness.container();
  addTearDown(container.dispose);
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.abrirEscolha();
  await settle();
  await notifier.goConversa(pericope: 'P01');
  await settle();
  return container;
}

/// The halt as the team meets it: `needsPerson` on. A halt reopened into is one the
/// server already holds, so it is entered without a call (ENG-962): the desk was told
/// by whatever raised it in the first place, not by this reopening — and the app never
/// speaks a line of its own over the halt (ENG-811).
bool _haltEntered(ProviderContainer container) =>
    container.read(salaSessionProvider).needsPerson;

void main() {
  test(
    'reopening into the retro honours the halt the server is holding',
    () async {
      final harness = SalaHarness()..room.serverStatus = 'needs_person';

      final container = await _reopensInto(
        harness,
        SalaStage.retro,
        contado: _traduzidos,
      );

      await waitFor(
        'a sala parar como a conversa pararia',
        () => _haltEntered(container),
      );

      final notifier = container.read(salaSessionProvider.notifier);
      final before = harness.playback.played.length;
      notifier.retroTap();
      notifier.cortarTrecho();
      notifier.retroTap();
      await settle();
      expect(
        harness.playback.played.length,
        before,
        reason:
            'a sala está parada esperando uma pessoa: os gestos da retro não '
            'podem responder como se ela estivesse viva',
      );
    },
  );

  test('reopening into the retro with no halt resumes normally', () async {
    final harness = SalaHarness();

    final container = await _reopensInto(
      harness,
      SalaStage.retro,
      contado: _traduzidos,
    );

    final state = container.read(salaSessionProvider);
    expect(state.stage, SalaStage.retro);
    expect(state.btTrechos, hasLength(1));
    expect(_haltEntered(container), isFalse);
  });

  test(
    'reopening into the rehearsal, halted, leaves the record circle dead',
    () async {
      final harness = SalaHarness()..room.serverStatus = 'needs_person';

      final container = await _reopensInto(harness, SalaStage.ensaio);

      await waitFor('a sala parar', () => _haltEntered(container));

      container.read(salaSessionProvider.notifier).ensaioTap();
      await settle();

      expect(
        harness.recorder.captures,
        0,
        reason:
            'a sala está parada esperando uma pessoa; abrir o microfone aqui '
            'grava a equipe para dentro de uma sala que o servidor já parou',
      );
      expect(
        container.read(salaSessionProvider).ensaio,
        EnsaioStatus.idle,
        reason: 'e a tela não pode dizer que está gravando',
      );
    },
  );
}
