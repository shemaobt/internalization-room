import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';

/// Wait for something to happen, and say what did not when it never does.
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

/// The app's storage, which a restore, a reinstall or a new tablet moves wholesale.
class _Storage {
  final Directory root = Directory.systemTemp.createTempSync('sala-armazenamento');
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
  await waitFor('a roda dizer quais passagens têm trabalho esperando',
      () => container.read(salaSessionProvider).naRoda != null);
  await notifier.goConversa(pericope: 'P01');
  return container;
}

void main() {
  test('the team resumes after the storage location moves underneath them',
      () async {
    final (:storage, :ledger) = _aTabletWithAPlace();
    await _theyStoppedInTheRehearsal(storage, ledger);

    storage.movesUnderneath();

    final harness = SalaHarness(emAbertoNoDisco: ledger);
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();
    await waitFor('a roda abrir',
        () => container.read(salaSessionProvider).naRoda != null);
    await notifier.goConversa(pericope: 'P01');

    expect(
      container.read(salaSessionProvider).stage,
      SalaStage.ensaio,
      reason: 'os arquivos estão todos lá, sob a pasta nova: uma restauração de '
          'backup não pode devolver a equipe ao começo da conversa',
    );
  });

  test('a place that can no longer be honoured does not trap the team forever',
      () async {
    final (:storage, :ledger) = _aTabletWithAPlace();
    await _theyStoppedInTheRehearsal(storage, ledger);

    storage.recordingsVanish();

    final harness = SalaHarness(emAbertoNoDisco: ledger);
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();
    await waitFor('a roda abrir',
        () => container.read(salaSessionProvider).naRoda != null);

    await notifier.goConversa(pericope: 'P01');
    expect(container.read(salaSessionProvider).stage, SalaStage.conversa,
        reason: 'sem as gravações o ensaio não existe; a conversa é o passo que '
            'ainda funciona');

    // A segunda vez é a que importa: a falha de retomada que se repete para
    // sempre é o dano, não a primeira. A limpeza é fire-and-forget, então a
    // espera é sobre ela ter pousado, não sobre o que a equipe vê.
    await waitFor(
      'a sala esquecer o ponto que não pode mais ser honrado',
      () async => await ledger.of('Ruth', 'P01') == null,
    );
    await notifier.abrirEscolha();
    await waitFor('a roda abrir de novo',
        () => container.read(salaSessionProvider).naRoda != null);

    expect(
      container.read(salaSessionProvider).comecadas,
      isNot(contains('P01')),
      reason: 'a roda não pode seguir prometendo uma retomada que já se provou '
          'impossível — é isso que prende a equipe indefinidamente',
    );
  });

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
}
