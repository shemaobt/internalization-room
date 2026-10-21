import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show settle;

Directory _home() {
  final home = Directory.systemTemp.createTempSync('sala-lugar');
  addTearDown(() => home.deleteSync(recursive: true));
  return home;
}

/// Put something in the way of the folder the ledger keeps its file in, so every write
/// from here on throws the way a full or read-only disk does.
void _blockTheDisk(Directory home) {
  final folder = Directory('${home.path}/guardadas');
  if (folder.existsSync()) folder.deleteSync(recursive: true);
  File('${home.path}/guardadas').writeAsStringSync('nao sou uma pasta');
}

/// Leave a ledger file on disk that no one can read back.
void _corruptTheLedger(Directory home) {
  Directory('${home.path}/guardadas').createSync(recursive: true);
  File(
    '${home.path}/guardadas/em_curso.json',
  ).writeAsStringSync('{"Ruth/P01": isto nao e json');
}

Future<void> _placeLands(WorkInProgress ledger, SalaStage stage) => waitFor(
  'o ponto de retomada pousar no disco como $stage',
  () async => (await ledger.of('Ruth', 'P01', 'pt'))?.stage == stage,
);

void main() {
  test('a place the disk refuses to write leaves the room going', () async {
    final home = _home();
    final ledger = WorkInProgress(
      home: () async => home,
      recordings: () async =>
          Directory('${home.path}/recordings')..createSync(recursive: true),
    );
    final harness = SalaHarness(emAbertoNoDisco: ledger);
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();

    await notifier.goConversa(book: 'Ruth', pericope: 'P01');
    await _placeLands(ledger, SalaStage.conversa);

    _blockTheDisk(home);
    notifier.goEnsaio();
    await settle();
    notifier.ensaioTap();

    await waitFor(
      'a sala seguir gravando',
      () =>
          container.read(salaSessionProvider).ensaio == EnsaioStatus.recording,
    );
  });

  test('a ledger no one can read does not report a place as written', () async {
    final home = _home();
    _corruptTheLedger(home);
    final ledger = WorkInProgress(
      home: () async => home,
      recordings: () async =>
          Directory('${home.path}/recordings')..createSync(recursive: true),
    );
    final harness = SalaHarness(emAbertoNoDisco: ledger);
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();

    await notifier.goConversa(book: 'Ruth', pericope: 'P01');
    await settle();

    expect(
      await ledger.of('Ruth', 'P01', 'pt'),
      isNull,
      reason: 'o arquivo ilegível continua ilegível: nada foi guardado',
    );
  });

  test('an ordinary place is written at each step', () async {
    final home = _home();
    final ledger = WorkInProgress(
      home: () async => home,
      recordings: () async =>
          Directory('${home.path}/recordings')..createSync(recursive: true),
    );
    final harness = SalaHarness(emAbertoNoDisco: ledger);
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();

    await notifier.goConversa(book: 'Ruth', pericope: 'P01');
    await _placeLands(ledger, SalaStage.conversa);
    notifier.goEnsaio();

    await _placeLands(ledger, SalaStage.ensaio);
  });
}
