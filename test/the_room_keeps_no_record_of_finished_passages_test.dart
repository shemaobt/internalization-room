import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/current_session_ledger.dart';
import 'package:internalization_room/features/sala/data/effect_runner.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'a_station_host_double.dart';
import 'fake_ports.dart';
import 'fakes.dart';
import 'scenario_helpers.dart' show settle;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('on the tablet', () {
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late Directory home;

    setUp(() {
      home = Directory.systemTemp.createTempSync('sala-casa');
      messenger.setMockMethodCallHandler(
        pathProvider,
        (call) async => home.path,
      );
    });

    tearDown(() {
      messenger.setMockMethodCallHandler(pathProvider, null);
      home.deleteSync(recursive: true);
    });

    test('closing a passage writes nothing about it on the tablet', () async {
      final currentSession = CurrentSessionLedger();
      final harness = SalaHarness(
        currentSession: currentSession,
        emAbertoNoDisco: WorkInProgress(),
      );
      final container = harness.container();
      addTearDown(container.dispose);
      final sala = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);

      await sala.goConversa(book: 'Ruth', pericope: 'P01');
      await settle();
      sala.goEnsaio();
      sala.gravarACena(1);
      sala.gravarACena(1);
      await settle();
      sala.takeKeep();
      await untilTheAdvanceDiscLights(sala);
      sala.startRetro();
      await settle();
      harness.playback.finishPlayback();
      await settle();
      await sala.finishBackTranslation();
      await settle();
      await sala.aprovarRascunhoFinal();
      await waitFor('o ensaio salvo', () => read().ensaioSalvo != null);
      sala.pronto();
      sala.leaveThePassage();
      await waitFor(
        'a equipe sair da passagem aprovada para a Escolha',
        () => read().stage == SalaStage.escolha && read().naRoda != null,
      );

      await sala.goConversa(book: 'Ruth', pericope: 'P02');
      await waitFor(
        'a P02 abrir',
        () => read().stage == SalaStage.conversa && read().sessionId != null,
      );
      await settle();
      harness.room
        ..failTurnsWith = const Refused('PIPELINE_REFUSED')
        ..askForAPersonFailsWith = const Refused('PASSAGE_CLOSED');
      sala.conversaTap();
      await settle();
      sala.conversaTap();
      await waitFor(
        'a passagem fechada levar a sala à Escolha',
        () =>
            harness.room.calls.contains('askForAPerson') &&
            read().stage == SalaStage.escolha,
      );
      await settle();

      expect(
        File('${home.path}/guardadas/passagens_feitas.json').existsSync(),
        isFalse,
        reason:
            'nada no tablet lia a lista das passagens feitas: a P01 aprovada '
            'e a P02 fechada pela sala não deixam registro no aparelho',
      );
      expect(
        await currentSession.read(),
        isNull,
        reason: 'a equipe deixou as duas sessões, e a Sessão atual foi largada',
      );
    });
  });

  test(
    'a call that meets a closed passage closes the session in the same turn',
    () {
      final store = AStorePort();
      final host = AStationHost()..session = 'sessao-1';
      final runner = EffectRunner(
        room: ARoomPort(),
        sound: ASoundPort(),
        recorder: ARecorderPort(),
        store: store,
        host: host,
        watchPeriod: () => const Duration(seconds: 30),
        retryDelay: (_) => const Duration(seconds: 2),
        partCeiling: () => null,
        clipGrace: () => Duration.zero,
        lookAgainAfter: () => Duration.zero,
        reloadAfter: () => Duration.zero,
        generation: () => 0,
      );
      addTearDown(runner.dispose);

      runner.run(const [CloseThePassage()]);

      expect(host.passagesClosedHeard, ['sessao-1']);
      expect(store.heard, isEmpty);
    },
  );
}
