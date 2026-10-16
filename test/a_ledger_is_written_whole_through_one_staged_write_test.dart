import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/staged_write.dart';
import 'package:path/path.dart' as p;

final _commentPattern = RegExp(r'//.*$', multiLine: true);

String _sourceWithoutComments(File file) =>
    file.readAsStringSync().replaceAll(_commentPattern, '');

void main() {
  test('a ledger write that dies halfway leaves the last whole file', () async {
    final home = Directory.systemTemp.createTempSync('sala-livro');
    addTearDown(() => home.deleteSync(recursive: true));
    final ledger = File(p.join(home.path, 'fila.json'))
      ..writeAsStringSync('["a tomada de ontem"]');
    Directory('${ledger.path}.novo').createSync();

    await expectLater(
      writeWhole(ledger, '["a tomada de hoje"]'),
      throwsA(isA<FileSystemException>()),
    );

    expect(
      ledger.readAsStringSync(),
      '["a tomada de ontem"]',
      reason:
          'um livro escrito pela metade sob o nome final seria lido como '
          'vazio, e a fila esqueceria o que a equipe gravou',
    );
  });

  test('no ledger stages its own write', () {
    final staging = RegExp(r'\.novo\b');
    final allowed = {
      p.join('lib', 'features', 'sala', 'data', 'staged_write.dart'),
      p.join(
        'lib',
        'features',
        'sala',
        'data',
        'facilitator_voice_service.dart',
      ),
    };
    final offenders = [
      for (final file
          in Directory('lib')
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => file.path.endsWith('.dart')))
        if (!allowed.contains(file.path) &&
            staging.hasMatch(_sourceWithoutComments(file)))
          file.path,
    ];

    expect(
      offenders,
      isEmpty,
      reason:
          'cada livro que encena sua própria escrita é mais um lugar onde '
          'esquecer o flush ou o rename: ${offenders.join(', ')}',
    );
  });
}
