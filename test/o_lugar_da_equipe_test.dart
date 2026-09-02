import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';

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
  () async => (await ledger.of('Ruth', 'P01'))?.stage == stage,
);

Future<void> _theRoomSays(SalaHarness harness) => waitFor(
  'a sala dizer que uma gravação ficou presa',
  () => harness.voice.assets.contains(strandedTakeAsset(testLanguage)),
);

void main() {
  test('a place the disk refuses to write is spoken to the team', () async {
    final home = _home();
    final ledger = WorkInProgress(
      home: () async => home,
      recordings: () async => Directory('${home.path}/recordings')
        ..createSync(recursive: true),
    );
    final harness = SalaHarness(emAbertoNoDisco: ledger);
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();

    await notifier.goConversa(pericope: 'P01');
    // The write on entering a passage is fire-and-forget. Blocking the disk while it is
    // still in flight would make that write the one that fails, and the case would hear
    // its line and pass for the wrong reason.
    await _placeLands(ledger, SalaStage.conversa);
    expect(
      harness.voice.assets,
      isNot(contains(strandedTakeAsset(testLanguage))),
      reason:
          'o disco ainda está bom aqui: a linha só pode vir do que vem depois',
    );

    _blockTheDisk(home);
    notifier.goEnsaio();

    await _theRoomSays(harness);
    expect(
      harness.voice.assets,
      contains(strandedTakeAsset(testLanguage)),
      reason:
          'perder o lugar exato da equipe em silêncio é a mesma perda que '
          'uma gravação presa, e merece a mesma voz',
    );
  });

  test('a ledger no one can read does not report a place as written', () async {
    final home = _home();
    _corruptTheLedger(home);
    final ledger = WorkInProgress(
      home: () async => home,
      recordings: () async => Directory('${home.path}/recordings')
        ..createSync(recursive: true),
    );
    final harness = SalaHarness(emAbertoNoDisco: ledger);
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();

    await notifier.goConversa(pericope: 'P01');

    await _theRoomSays(harness);
    expect(
      await ledger.of('Ruth', 'P01'),
      isNull,
      reason: 'o arquivo ilegível continua ilegível: nada foi guardado',
    );
    expect(
      harness.voice.assets,
      contains(strandedTakeAsset(testLanguage)),
      reason:
          'a escrita voltava com sucesso sem ter escrito nada, e essa é a '
          'falha que não levanta erro nenhum em camada alguma',
    );
  });

  test('an ordinary place is written without a word', () async {
    final home = _home();
    final ledger = WorkInProgress(
      home: () async => home,
      recordings: () async => Directory('${home.path}/recordings')
        ..createSync(recursive: true),
    );
    final harness = SalaHarness(emAbertoNoDisco: ledger);
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();

    await notifier.goConversa(pericope: 'P01');
    await _placeLands(ledger, SalaStage.conversa);
    notifier.goEnsaio();

    // Measured after the write has actually landed, so the silence below is the room
    // having nothing to say rather than the room not having got there yet.
    await _placeLands(ledger, SalaStage.ensaio);
    expect(
      harness.voice.assets,
      isNot(contains(strandedTakeAsset(testLanguage))),
    );
  });
}
