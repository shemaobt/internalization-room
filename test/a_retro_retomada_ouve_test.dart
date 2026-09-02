import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';

Future<void> settle([Duration delay = const Duration(milliseconds: 120)]) =>
    Future<void>.delayed(delay);

Future<void> waitFor(
  String what,
  FutureOr<bool> Function() ready, {
  Duration limit = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(limit);
  while (!await ready()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('esperei ${limit.inSeconds}s e $what não aconteceu');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

const _contados = BackTranslationProgress(
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

/// The halt as the team meets it: the room says it out loud and the desk is told.
bool _calledForAPerson(SalaHarness harness) =>
    harness.voice.assets.contains(fixedLineAsset(needsPersonLine, testLanguage)) &&
    harness.room.personsAsked > 0;

void main() {
  test('reopening into the retro honours the halt the server is holding',
      () async {
    final harness = SalaHarness()..room.serverStatus = 'needs_person';

    final container = await _reopensInto(
      harness,
      SalaStage.retro,
      contado: _contados,
    );

    await waitFor('a sala parar como a conversa pararia',
        () => _calledForAPerson(harness));

    final notifier = container.read(salaSessionProvider.notifier);
    final before = harness.playback.played.length;
    notifier.retroTap();
    notifier.cortarTrecho();
    await settle();
    expect(
      harness.playback.played.length,
      before,
      reason: 'a sala está parada esperando uma pessoa: os gestos da retro não '
          'podem responder como se ela estivesse viva',
    );
  });

  test('reopening into the retro with no halt resumes normally', () async {
    final harness = SalaHarness();

    final container = await _reopensInto(
      harness,
      SalaStage.retro,
      contado: _contados,
    );

    final state = container.read(salaSessionProvider);
    expect(state.stage, SalaStage.retro);
    expect(state.btTrechos, hasLength(1));
    expect(_calledForAPerson(harness), isFalse);
  });
}
