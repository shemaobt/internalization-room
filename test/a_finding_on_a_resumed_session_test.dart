import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';

const _contado = 'gravacao-1@0-30000';

/// A tablet opened again on a passage told back whole the day before: the part is on the
/// tablet, the stretch the room holds is not, so it carries no told file here. The
/// analyst then points at that stretch.
Future<ProviderContainer> _retomadaNoAchado(SalaHarness harness) async {
  final casa = Directory.systemTemp.createTempSync('sala-achado-retomado');
  addTearDown(() => casa.deleteSync(recursive: true));
  harness.playback
    ..length = const Duration(seconds: 30)
    ..measured = const Duration(seconds: 30);
  harness.room
    ..verdictChecked = false
    ..verdictFinding = BtFindingKind.missing
    ..verdictFindingSegmentId = _contado
    ..retroSoFar = const BackTranslationProgress(
      segments: [
        SegmentView(
          segmentId: _contado,
          takeId: 'gravacao-1',
          startsMs: 0,
          endsMs: 30000,
        ),
      ],
    );
  harness.emAberto.rows['Ruth/P01'] = ResumePoint(
    sessionId: 'sessao-antiga',
    stage: SalaStage.retro,
    takes: [
      KeptTake(
        scopeId: KeptScope.parte(1),
        path: (File('${casa.path}/p1.m4a')..writeAsBytesSync([1, 2, 3])).path,
        takeId: 'gravacao-1',
      ),
    ],
  );
  final container = harness.container();
  addTearDown(container.dispose);
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.abrirEscolha();
  await notifier.goConversa(pericope: 'P01');
  await waitFor(
    'a tradução retomada pôr a parte no ar',
    () => container.read(salaSessionProvider).stage == SalaStage.retro,
  );
  harness.playback.finishPlayback();
  await waitFor(
    'a tradução retomada poder pedir o veredito',
    () => container.read(salaSessionProvider).canFinishBackTranslation,
  );
  await notifier.finishBackTranslation();
  await waitFor(
    'o achado apontar o trecho retomado',
    () => container.read(salaSessionProvider).btFindingTrecho != null,
  );
  expect(
    container.read(salaSessionProvider).btFindingTrecho!.retroPath,
    isNull,
    reason: 'o cenário só mede algo se o trecho não tiver arquivo aqui',
  );
  return container;
}

void main() {
  test('sem o arquivo da tradução, o play toca só a língua materna', () async {
    final harness = SalaHarness();
    final container = await _retomadaNoAchado(harness);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    notifier.ouvirOTrechoEATraducao();
    await waitFor('a materna tocar', () => read().btTrechoTocando);
    final tocadas = harness.playback.played.length;
    expect(harness.playback.played.last, read().partes.single.path);

    harness.playback.finishPlayback();
    await waitFor('a materna acabar', () => !read().btTrechoTocando);
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(read().btRetroTocando, isFalse);
    expect(harness.playback.played, hasLength(tocadas));
    expect(harness.playback.sounding, isFalse);
  });

  test('sem o arquivo da tradução, o check espera o círculo gravar, e o '
      'replace sai uma vez', () async {
    final harness = SalaHarness();
    final container = await _retomadaNoAchado(harness);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    notifier.traduzirDeNovoEmPortugues();

    expect(read().btPhase, BtPhase.playing);
    expect(read().btTraducaoPendente, isNull);
    expect(read().canConfirmTranslation, isFalse);
    await notifier.confirmarTraducao();
    expect(harness.room.replacesAsked, isEmpty);

    notifier.retroTap();
    await waitFor(
      'o microfone abrir no trecho',
      () => read().btPhase == BtPhase.capturing,
    );
    await fecharACaptura(container);
    expect(read().canConfirmTranslation, isTrue);
    await notifier.confirmarTraducao();
    await waitFor(
      'a sala sair do pensando',
      () => read().btPhase != BtPhase.thinking,
    );

    expect(harness.room.replacesAsked, ['$_contado@gravacao-1:0-30000']);
    expect(harness.room.chunksSent, 0);
  });
}
