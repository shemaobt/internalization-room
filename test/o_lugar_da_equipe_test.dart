import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';

Future<void> settle([Duration delay = const Duration(milliseconds: 120)]) =>
    Future<void>.delayed(delay);

/// A home the ledger can write into.
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

void main() {
  test('a place the disk refuses to write is spoken to the team', () async {
    final home = _home();
    final harness = SalaHarness(
      emAbertoNoDisco: WorkInProgress(home: () async => home),
    );
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();
    await settle();
    await notifier.goConversa(pericope: 'P01');
    await settle();
    expect(
      harness.voice.assets,
      isNot(contains(strandedTakeAsset(testLanguage))),
      reason:
          'o disco ainda está bom aqui — se a linha já tocou, ela veio de '
          'outro lugar e o caso não mede o ponto de retomada',
    );

    _blockTheDisk(home);
    notifier.goEnsaio();
    await settle();

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
    final ledger = WorkInProgress(home: () async => home);
    final harness = SalaHarness(emAbertoNoDisco: ledger);
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();
    await settle();

    await notifier.goConversa(pericope: 'P01');
    await settle();

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
    final ledger = WorkInProgress(home: () async => home);
    final harness = SalaHarness(emAbertoNoDisco: ledger);
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();
    await settle();

    await notifier.goConversa(pericope: 'P01');
    await settle();
    notifier.goEnsaio();
    await settle();

    expect((await ledger.of('Ruth', 'P01'))?.stage, SalaStage.ensaio);
    expect(
      harness.voice.assets,
      isNot(contains(strandedTakeAsset(testLanguage))),
    );
  });
}
