import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart'
    show intoTheBackTranslation, intoTheRecordingHome, settle;

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

/// A tablet closed part-way through a passage, opened again on it, and walked from its
/// conversation back to the station it stood on.
Future<ProviderContainer> _reopensInto(
  SalaHarness harness,
  SalaStage parouEm, {
  BackTranslationProgress contado = const BackTranslationProgress(),
}) async {
  final gravada = File(
    '${Directory.systemTemp.createTempSync('sala-687').path}/p1.m4a',
  )..writeAsBytesSync([1, 2, 3]);
  addTearDown(() => gravada.parent.deleteSync(recursive: true));
  harness.emAberto.rows['Ruth/P01/pt'] = ResumePoint(
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
  await notifier.goConversa(book: 'Ruth', pericope: 'P01');
  SalaSessionState read() => container.read(salaSessionProvider);
  if (parouEm == SalaStage.retro) {
    await intoTheBackTranslation(notifier, read);
  } else {
    await intoTheRecordingHome(notifier, read);
  }
  await settle();
  return container;
}

/// The halt as the team meets it: `needsPerson` on.
bool _haltEntered(ProviderContainer container) =>
    container.read(salaSessionProvider).needsPerson;

void main() {
  test('reopening into the retro while the server says it needs a person '
      'shows no sign, and the retro plays its part', () async {
    final harness = SalaHarness()..room.serverStatus = 'needs_person';

    final container = await _reopensInto(
      harness,
      SalaStage.retro,
      contado: _traduzidos,
    );
    await waitFor('a parte tocar', () => harness.playback.played.isNotEmpty);

    final state = container.read(salaSessionProvider);
    expect(state.stage, SalaStage.retro);
    expect(state.btTrechos, hasLength(1));
    expect(
      _haltEntered(container),
      isFalse,
      reason: 'uma leitura nunca levanta o sinal da pessoa',
    );
  });

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

  test('a resume onto a telling in progress whose listened report fails stays '
      'quiet and plays from the told end, not the first listen', () async {
    final harness = SalaHarness()
      ..room.failListeningWith = const NetworkFailed('sem rede');

    final container = await _reopensInto(
      harness,
      SalaStage.retro,
      contado: _traduzidos,
    );
    await waitFor('a parte tocar', () => harness.playback.played.isNotEmpty);

    expect(harness.voice.fixedLines, isEmpty);
    expect(container.read(salaSessionProvider).btSoOuvir, isFalse);
    expect(
      harness.playback.playedFrom.last,
      const Duration(milliseconds: 12000),
    );
  });

  test('a resume onto a frase that awaits whose listened report fails goes '
      'back to the frase, not the first listen', () async {
    final harness = SalaHarness()
      ..room.failListeningWith = const NetworkFailed('sem rede');

    final container = await _reopensInto(
      harness,
      SalaStage.retro,
      contado: const BackTranslationProgress(
        segments: [
          SegmentView(
            segmentId: 'trecho-1',
            takeId: 'gravacao-1',
            startsMs: 0,
            endsMs: 12000,
          ),
        ],
        awaitingSegmentId: 'trecho-1',
      ),
    );
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.btSoOuvir, isFalse);
    expect(state.btFraseQueAguarda, isNotNull);
    expect(
      harness.voice.fixedLines.map((linha) => linha.$1),
      isNot(contains('P0')),
    );
  });

  test('entering from the home a passage the room checked, when the listened '
      'report fails, keeps the verdict and not the first listen', () async {
    final harness = SalaHarness();
    final container = await _reopensInto(
      harness,
      SalaStage.ensaio,
      contado: const BackTranslationProgress(
        segments: [
          SegmentView(
            segmentId: 'trecho-1',
            takeId: 'gravacao-1',
            startsMs: 0,
            endsMs: 12000,
          ),
        ],
        checked: true,
      ),
    );
    harness.room.failListeningWith = const NetworkFailed('sem rede');

    container.read(salaSessionProvider.notifier).startRetro();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.btSoOuvir, isFalse);
    expect(state.btPhase, BtPhase.conferida);
  });

  test('reopening into the rehearsal while the server says it needs a person '
      'shows no sign, and the record circle records', () async {
    final harness = SalaHarness()..room.serverStatus = 'needs_person';

    final container = await _reopensInto(harness, SalaStage.ensaio);
    expect(
      _haltEntered(container),
      isFalse,
      reason: 'uma leitura nunca levanta o sinal da pessoa',
    );

    container.read(salaSessionProvider.notifier).gravarACena(2);
    await settle();

    expect(harness.recorder.captures, 1);
    expect(container.read(salaSessionProvider).ensaio, EnsaioStatus.recording);
  });
}
