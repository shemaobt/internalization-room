import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'session_notifier_test.dart' show inConversa;
import 'scenario_helpers.dart' show settle;

/// The app's storage, which a restore, a reinstall or a new tablet moves wholesale.
class _Storage {
  final Directory root = Directory.systemTemp.createTempSync(
    'sala-armazenamento',
  );
  late Directory _recordings = _makeRecordings('um');

  Directory _makeRecordings(String prefix) =>
      Directory('${root.path}/$prefix/recordings')..createSync(recursive: true);

  Directory get recordings => _recordings;

  File take(String name) =>
      File('${_recordings.path}/$name')..writeAsBytesSync([1, 2, 3]);

  /// What a restore does: the container prefix changes, the files come back under it,
  /// and the old prefix is gone for good.
  void movesUnderneath() {
    final was = _recordings;
    final now = _makeRecordings('dois');
    for (final file in was.listSync().whereType<File>()) {
      file.copySync('${now.path}/${file.uri.pathSegments.last}');
    }
    was.parent.deleteSync(recursive: true);
    _recordings = now;
  }

  /// The recordings are not moved, they are gone.
  void recordingsVanish() {
    for (final file in _recordings.listSync().whereType<File>()) {
      file.deleteSync();
    }
  }

  void dispose() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  }
}

({_Storage storage, WorkInProgress ledger}) _aTabletWithAPlace() {
  final storage = _Storage();
  addTearDown(storage.dispose);
  final ledgerHome = Directory.systemTemp.createTempSync('sala-em-curso');
  addTearDown(() => ledgerHome.deleteSync(recursive: true));
  return (
    storage: storage,
    ledger: WorkInProgress(
      home: () async => ledgerHome,
      recordings: () async => storage.recordings,
    ),
  );
}

Future<void> _theyStoppedInTheRehearsal(
  _Storage storage,
  WorkInProgress ledger,
) async {
  final gravada = storage.take('p1.m4a');
  await ledger.remember(
    'Ruth',
    'P01',
    ResumePoint(
      sessionId: 'sessao-de-ontem',
      stage: SalaStage.ensaio,
      takes: [KeptTake(scopeId: KeptScope.parte(1), path: gravada.path)],
    ),
  );
}

Future<ProviderContainer> _opensThePassage(SalaHarness harness) async {
  final container = harness.container();
  addTearDown(container.dispose);
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.abrirEscolha();
  await waitFor(
    'a roda dizer quais passagens têm trabalho esperando',
    () => container.read(salaSessionProvider).naRoda != null,
  );
  await notifier.goConversa(pericope: 'P01');
  return container;
}

void main() {
  test(
    'the team resumes after the storage location moves underneath them',
    () async {
      final (:storage, :ledger) = _aTabletWithAPlace();
      await _theyStoppedInTheRehearsal(storage, ledger);

      storage.movesUnderneath();

      final harness = SalaHarness(emAbertoNoDisco: ledger);
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      await notifier.abrirEscolha();
      await waitFor(
        'a roda abrir',
        () => container.read(salaSessionProvider).naRoda != null,
      );
      await notifier.goConversa(pericope: 'P01');

      expect(
        container.read(salaSessionProvider).stage,
        SalaStage.ensaio,
        reason:
            'os arquivos estão todos lá, sob a pasta nova: uma restauração de '
            'backup não pode devolver a equipe ao começo da conversa',
      );
    },
  );

  test(
    'a place the room cannot honour either opens at the conversa, and keeps itself',
    () async {
      final (:storage, :ledger) = _aTabletWithAPlace();
      await _theyStoppedInTheRehearsal(storage, ledger);

      storage.recordingsVanish();

      final harness = SalaHarness(emAbertoNoDisco: ledger);
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      await notifier.abrirEscolha();
      await waitFor(
        'a roda abrir',
        () => container.read(salaSessionProvider).naRoda != null,
      );

      await notifier.goConversa(pericope: 'P01');
      expect(
        container.read(salaSessionProvider).stage,
        SalaStage.conversa,
        reason:
            'nem o tablet nem a sala têm o ensaio: a conversa é o passo que '
            'ainda funciona',
      );
      expect(
        container.read(salaSessionProvider).sessionId,
        'sessao-de-ontem',
        reason:
            'o id da sessão não mora em nenhum outro lugar — o servidor não '
            'guarda aparelho — então esquecer a linha abandonaria de vez o '
            'trabalho que já subiu',
      );

      // A segunda vez é a que importa: a falha de retomada que se repete para
      // sempre é o dano, não a primeira. A saída é a sala devolver o ensaio, e
      // ela só pode fazê-lo enquanto a linha continuar de pé.
      expect(
        (await ledger.of('Ruth', 'P01'))?.takes,
        hasLength(1),
        reason:
            'reescrever a linha sem as gravações fecha essa porta para '
            'sempre: a próxima abertura não acharia nada para restaurar, e o '
            'ensaio que a sala guardasse ficaria fora do alcance da equipe',
      );

      harness.room.takes.add(
        const TakeView(
          takeId: 'gravacao-1',
          kind: 'ensaio',
          scope: 'parte-1',
          ordinal: 1,
        ),
      );
      await notifier.abrirEscolha();
      await waitFor(
        'a roda abrir de novo',
        () => container.read(salaSessionProvider).naRoda != null,
      );
      await notifier.goConversa(pericope: 'P01');
      await waitFor(
        'o ensaio voltar da sala',
        () => container.read(salaSessionProvider).partes.isNotEmpty,
      );

      expect(
        container.read(salaSessionProvider).stage,
        SalaStage.ensaio,
        reason:
            'com o ensaio na sala a equipe volta para ele, e é por isso que '
            'a linha tinha de sobreviver à primeira abertura',
      );
    },
  );

  test('an ordinary resume still resumes', () async {
    final (:storage, :ledger) = _aTabletWithAPlace();
    await _theyStoppedInTheRehearsal(storage, ledger);

    final harness = SalaHarness(emAbertoNoDisco: ledger);
    final container = await _opensThePassage(harness);

    expect(container.read(salaSessionProvider).stage, SalaStage.ensaio);
    expect(
      container.read(salaSessionProvider).partes.single.scopeId,
      KeptScope.parte(1),
    );
  });

  test(
    'a tap while the microphone is still opening never reaches a stop',
    () async {
      final harness = SalaHarness()..recorder.holdNextStart();
      final container = await inConversa(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      final turnsBefore = harness.room.turnsSent;

      notifier.conversaTap();
      notifier.conversaTap();
      harness.recorder.finishStart();
      await settle();

      expect(
        harness.room.turnsSent,
        turnsBefore,
        reason:
            'o segundo toque caiu enquanto o gravador ainda abria; ele nunca '
            'devia alcançar um _finishListening, guard ou não',
      );
      expect(
        container.read(salaSessionProvider).needsPerson,
        isFalse,
        reason: 'um toque nessa janela não é uma falha do gravador',
      );
    },
  );
}
