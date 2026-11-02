import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/current_session_ledger.dart';

import 'support/temp.dart';

void main() {
  late Directory home;
  late Directory folder;
  late CurrentSessionLedger ledger;

  setUp(() {
    home = aTempDir('sala-sessao');
    folder = Directory('${home.path}/guardadas')..createSync();
    ledger = CurrentSessionLedger(home: () async => home);
  });

  void record(String text) =>
      File('${folder.path}/sessao_atual.json').writeAsStringSync(text);

  test('no record is a known nothing held', () async {
    final read = await ledger.readIfKnown();

    expect(read, isNotNull);
    expect(read!.session, isNull);
  });

  test('a readable record is the session it holds', () async {
    record(
      '{"session_id": "s1", "book": "Ruth", "pericope": "P01", '
      '"language": "en"}',
    );

    expect((await ledger.readIfKnown())?.session?.sessionId, 's1');
  });

  for (final (why, text) in [
    ('torn text', '{"session_id": "s1", "bo'),
    ('a record that is not an object', '[1, 2]'),
    ('a record missing its book', '{"session_id": "s1"}'),
  ]) {
    test('$why is unknown, not nothing held', () async {
      record(text);

      expect(await ledger.readIfKnown(), isNull);
    });
  }

  test('a disk that cannot be read is unknown, not nothing held', () async {
    final broken = CurrentSessionLedger(
      home: () async => throw const FileSystemException('o disco morreu'),
    );

    expect(await broken.readIfKnown(), isNull);
  });
}
