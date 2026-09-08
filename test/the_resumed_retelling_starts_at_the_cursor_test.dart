import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';

Future<void> settle([Duration delay = const Duration(milliseconds: 120)]) async {
  await Future<void>.delayed(delay);
}

/// A tablet opened again on a passage the team was part-way through telling back.
///
/// [contado] is what the room is holding, addressed to the recordings by name:
/// `gravacao-1` is the first part of the rehearsal, `gravacao-2` the second. Both files
/// are on the tablet, so nothing here is the resume that has to start the room over.
Future<ProviderContainer> _retomar(
  SalaHarness harness, {
  required List<SegmentView> contado,
  int partes = 1,
}) async {
  final casa = Directory.systemTemp.createTempSync('sala-retro-no-cursor');
  addTearDown(() => casa.deleteSync(recursive: true));
  harness.emAberto.rows['Ruth/P01'] = ResumePoint(
    sessionId: 'sessao-antiga',
    stage: SalaStage.retro,
    takes: [
      for (var n = 1; n <= partes; n++)
        KeptTake(
          scopeId: KeptScope.parte(n),
          path: (File('${casa.path}/p$n.m4a')..writeAsBytesSync([1, 2, 3])).path,
          takeId: 'gravacao-$n',
        ),
    ],
  );
  harness.room.retroSoFar = BackTranslationProgress(segments: contado);
  final container = harness.container();
  addTearDown(container.dispose);
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.abrirEscolha();
  await settle();
  await notifier.goConversa(pericope: 'P01');
  await settle();
  return container;
}

SegmentView _contado(String gravacao, int de, int ate) => SegmentView(
      segmentId: '$gravacao@$de-$ate',
      takeId: gravacao,
      startsMs: de,
      endsMs: ate,
    );

/// Where the cursor is, read the only way the room lets anyone read it from outside: the
/// beginning of the span the next cut sends.
///
/// It spends the cut it makes — the cursor moves to the far end afterwards — so a test
/// asks this once, at its end.
Future<Duration> _cursorPeloCorte(
  SalaHarness harness,
  SalaSessionNotifier notifier,
) async {
  final antes = harness.room.chunkSpans.length;
  harness.playback.at = const Duration(minutes: 5);
  notifier.cortarTrecho();
  await settle();
  notifier.retroTap();
  await waitFor(
    'o corte chegar à sala',
    () => harness.room.chunkSpans.length > antes,
  );
  final span = harness.room.chunkSpans.last.split('-').first;
  return Duration(milliseconds: int.parse(span));
}

void main() {
  test('a part picked back up plays on from where the telling-back stopped',
      () async {
    final harness = SalaHarness()..playback.length = const Duration(seconds: 32);
    final container = await _retomar(
      harness,
      contado: [_contado('gravacao-1', 0, 30000)],
    );
    final notifier = container.read(salaSessionProvider.notifier);

    // Nobody writes the position here: where the clip starts is the whole question, and
    // the two seconds after it are the team telling one more stretch back.
    final comecou = harness.playback.at;
    harness.playback.walkWhilePlaying(step: const Duration(seconds: 2));
    await waitFor(
      'o ensaio andar dois segundos',
      () => harness.playback.at >= comecou + const Duration(seconds: 2),
    );
    harness.playback.stopWalking();
    notifier.cortarTrecho();
    await settle();
    notifier.retroTap();
    await settle();

    expect(harness.room.chunkSpans, ['30000-32000'],
        reason: 'a equipe volta e ouve de novo os trinta segundos que já '
            'contou, e a tesoura é recusada calada enquanto isso');
  });

  test('what the team heard on the way back is counted from the cursor',
      () async {
    final harness = SalaHarness()..playback.length = const Duration(seconds: 40);
    final container = await _retomar(
      harness,
      contado: [_contado('gravacao-1', 0, 30000)],
    );
    final notifier = container.read(salaSessionProvider.notifier);

    harness.playback.finishPlayback();
    await settle();
    await notifier.finishBackTranslation();
    await settle();

    expect(harness.room.playedRangesSent.last, [
      [30000, 40000]
    ],
        reason: 'o portão da sala lê o que foi ouvido nesta rodada, e contar os '
            'trinta segundos que ninguém tocou é dizer que se ouviu áudio que '
            'não saiu do tablet');
  });

  test('parts told back whole are stepped over, and the next one starts at nought',
      () async {
    final harness = SalaHarness();
    final container = await _retomar(
      harness,
      partes: 2,
      contado: [_contado('gravacao-1', 0, 30000)],
    );

    await waitFor(
      'a segunda parte entrar no ar',
      () => harness.playback.played.isNotEmpty,
    );
    expect(harness.playback.played.single, endsWith('p2.m4a'),
        reason: 'a primeira parte foi contada inteira; tocá-la de novo é a '
            'volta ao começo que esta mudança existe para não fazer');
    expect(harness.playback.at, Duration.zero,
        reason: 'e a segunda ninguém contou ainda, então ela começa onde '
            'sempre começou');
    expect(container.read(salaSessionProvider).stage, SalaStage.retro);
  });

  test('crossing into a part nobody told back starts it at nought', () async {
    final harness = SalaHarness()..playback.length = const Duration(seconds: 30);
    final container = await _retomar(
      harness,
      partes: 2,
      contado: [_contado('gravacao-1', 0, 12000)],
    );
    final notifier = container.read(salaSessionProvider.notifier);

    harness.playback.finishPlayback();
    await settle();
    notifier.ouvirGravacao();
    await settle();

    expect(harness.playback.played.last, endsWith('p2.m4a'));
    expect(harness.playback.at, Duration.zero,
        reason: 'o cursor pertence ao arquivo no ar, e a parte nova não tem '
            'chão contado nenhum');
  });

  test('crossing into a part half told back starts it at its own cursor', () async {
    final harness = SalaHarness()..playback.length = const Duration(seconds: 30);
    final container = await _retomar(
      harness,
      partes: 2,
      contado: [
        _contado('gravacao-1', 0, 12000),
        _contado('gravacao-2', 0, 10000),
      ],
    );
    final notifier = container.read(salaSessionProvider.notifier);

    harness.playback.finishPlayback();
    await settle();
    notifier.ouvirGravacao();
    await settle();

    expect(harness.playback.played.last, endsWith('p2.m4a'));
    expect(harness.playback.at, const Duration(seconds: 10),
        reason: 'atravessar não é diferente de retomar: a parte que se abre '
            'começa depois do que já foi contado dela');
  });

  test('holding the rehearsal and letting it run again does not rewind it',
      () async {
    final harness = SalaHarness();
    final container = await _retomar(
      harness,
      contado: [_contado('gravacao-1', 0, 30000)],
    );
    final notifier = container.read(salaSessionProvider.notifier);
    await settle();
    final tocados = harness.playback.played.length;

    notifier.ouvirGravacao();
    await settle();
    notifier.ouvirGravacao();
    await settle();

    expect(harness.playback.played, hasLength(tocados),
        reason: 'segurar e soltar é o mesmo som voltando, não um clipe novo — '
            'carregá-lo outra vez é que devolveria a equipe ao começo');
    expect(harness.playback.at, const Duration(seconds: 30),
        reason: 'e a posição fica onde a equipe pausou');
  });

  test('a rehearsal with nothing left to tell still reaches its end', () async {
    // The last part is never stepped over, so one told back whole now opens at its own
    // end — and what says the clip finished stops being the player's own completion and
    // becomes the ceiling that counts what is left of it. `terminei` is offered either
    // way, which is the promise this holds down.
    final harness = SalaHarness(clipGrace: const Duration(milliseconds: 100))
      ..playback.length = const Duration(seconds: 30);
    final container = await _retomar(
      harness,
      contado: [_contado('gravacao-1', 0, 30000)],
    );

    await waitFor(
      'a sala oferecer o terminei',
      () => container.read(salaSessionProvider).canFinishBackTranslation,
    );

    expect(harness.playback.at, const Duration(seconds: 30),
        reason: 'não sobrou nada para contar nesta gravação, e ouvi-la inteira '
            'outra vez para poder encerrar é exatamente a duplicação que a '
            'retomada existe para evitar');
  });

  group('nothing in the telling-back is born behind the cursor', () {
    test('resuming into a part with told ground', () async {
      final harness = SalaHarness();
      final container = await _retomar(
        harness,
        contado: [_contado('gravacao-1', 0, 30000)],
      );
      final notifier = container.read(salaSessionProvider.notifier);

      final comecou = harness.playback.at;
      final cursor = await _cursorPeloCorte(harness, notifier);

      expect(comecou, greaterThanOrEqualTo(cursor));
    });

    test('resuming into a part nobody told back yet', () async {
      final harness = SalaHarness();
      final container = await _retomar(
        harness,
        partes: 2,
        contado: [_contado('gravacao-1', 0, 30000)],
      );
      final notifier = container.read(salaSessionProvider.notifier);
      await waitFor(
        'a segunda parte entrar no ar',
        () => harness.playback.played.isNotEmpty,
      );

      final comecou = harness.playback.at;
      final cursor = await _cursorPeloCorte(harness, notifier);

      expect(comecou, greaterThanOrEqualTo(cursor));
    });

    test('crossing into the next part', () async {
      final harness = SalaHarness()
        ..playback.length = const Duration(seconds: 30);
      final container = await _retomar(
        harness,
        partes: 2,
        contado: [
          _contado('gravacao-1', 0, 12000),
          _contado('gravacao-2', 0, 10000),
        ],
      );
      final notifier = container.read(salaSessionProvider.notifier);
      harness.playback.finishPlayback();
      await settle();
      notifier.ouvirGravacao();
      await settle();

      final comecou = harness.playback.at;
      final cursor = await _cursorPeloCorte(harness, notifier);

      expect(comecou, greaterThanOrEqualTo(cursor));
    });

    test('letting the rehearsal run again after holding it', () async {
      final harness = SalaHarness();
      final container = await _retomar(
        harness,
        contado: [_contado('gravacao-1', 0, 30000)],
      );
      final notifier = container.read(salaSessionProvider.notifier);
      notifier.ouvirGravacao();
      await settle();
      notifier.ouvirGravacao();
      await settle();

      final comecou = harness.playback.at;
      final cursor = await _cursorPeloCorte(harness, notifier);

      expect(comecou, greaterThanOrEqualTo(cursor));
    });

    test('carrying on after a stretch was told back', () async {
      final harness = SalaHarness();
      final container = await _retomar(
        harness,
        contado: [_contado('gravacao-1', 0, 30000)],
      );
      final notifier = container.read(salaSessionProvider.notifier);
      harness.playback.at = const Duration(seconds: 44);
      notifier.cortarTrecho();
      await settle();
      notifier.retroTap();
      await waitFor('o trecho chegar à sala', () => harness.room.chunksSent == 1);
      notifier.ouvirGravacao();
      await settle();

      final comecou = harness.playback.at;
      final cursor = await _cursorPeloCorte(harness, notifier);

      expect(comecou, greaterThanOrEqualTo(cursor));
    });
  });
}
