import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/finished_passages.dart';

void main() {
  late Directory home;

  setUp(() => home = Directory.systemTemp.createTempSync('sala-feitas'));
  tearDown(() => home.deleteSync(recursive: true));

  FinishedPassages ledgerOn() => FinishedPassages(home: () async => home);

  File file() => File('${home.path}/guardadas/passagens_feitas.json');

  test('a passage finished in one book is not finished in another', () async {
    final ledger = ledgerOn();

    await ledger.add('Ruth', 'P01');

    expect(await ledger.all('Ruth'), {'P01'});
    expect(await ledger.all('Jonah'), isEmpty,
        reason: 'os números das passagens se repetem em todo livro; guardá-los crus '
            'riscava do livro novo o que a equipe fez no antigo');
  });

  test('what was written before books were scoped still belongs to Ruth', () async {
    final ledger = ledgerOn();
    await file().create(recursive: true);
    await file().writeAsString('["P01", "P02", "livro:Ruth"]');

    expect(await ledger.all('Ruth'), {'P01', 'P02'});
    expect(await ledger.all('Jonah'), isEmpty);
    expect(await ledger.bookOpened('Ruth'), isTrue);
  });

  test('a ledger it cannot read is never written over', () async {
    final ledger = ledgerOn();
    await ledger.add('Ruth', 'P01');
    await ledger.add('Ruth', 'P02');

    await file().writeAsString('["Ruth/P01", "Ruth');
    await ledger.add('Ruth', 'P03');

    expect(await file().readAsString(), '["Ruth/P01", "Ruth',
        reason: 'a leitura falhava, virava conjunto vazio, e a próxima passagem gravava '
            'um registro de uma linha só — apagando tudo que a equipe já tinha feito');
  });

  test('a ledger holding the wrong shape does not throw past its caller', () async {
    final ledger = ledgerOn();
    await file().create(recursive: true);
    await file().writeAsString('{"feitas": ["P01"]}');

    expect(await ledger.all('Ruth'), isEmpty);
    expect(await ledger.bookOpened('Ruth'), isFalse);
  });
}
