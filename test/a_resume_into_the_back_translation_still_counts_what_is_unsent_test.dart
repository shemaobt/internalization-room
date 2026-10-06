import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show settle;

void main() {
  test(
    'a resume that lands in the back-translation still counts what is unsent',
    () async {
      final harness = SalaHarness(filaEmMemoria: true);
      final fila = harness.takes as FakeTakeQueue;
      final gravada = File(
        '${Directory.systemTemp.createTempSync('sala-1446').path}/p1.m4a',
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
      harness.room.retroSoFar = const BackTranslationProgress(
        segments: [
          SegmentView(
            segmentId: 'trecho-1',
            takeId: 'gravacao-1',
            startsMs: 0,
            endsMs: 12000,
          ),
        ],
      );
      await fila.enqueue(
        gravada,
        sessionId: 'sessao-antiga',
        kind: 'ensaio',
        scope: 'parte-1',
      );
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);

      await notifier.abrirEscolha();
      await settle();
      fila.holdTheNextReading();
      await notifier.goConversa(pericope: 'P01');
      await waitFor(
        'a retomada pousar na retro com a contagem ainda presa',
        () => read().stage == SalaStage.retro && fila.readingHeld,
      );
      fila.releaseTheHeldReading();
      await settle();

      expect(
        read().unsentTakes,
        1,
        reason:
            'a gravação que ainda não subiu continua na fila; pousar na '
            'retro não pode apagar a contagem que a equipe vê',
      );
    },
  );
}
