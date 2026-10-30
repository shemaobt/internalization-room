import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/current_session_ledger.dart';

void main() {
  test('an entry of the ends file reads as a turn of the team\'s only when it '
      'says so; a malformed one reads as unknown', () async {
    final home = Directory.systemTemp.createTempSync('sala-fins');
    addTearDown(() => home.deleteSync(recursive: true));
    final folder = Directory('${home.path}/guardadas')..createSync();
    File('${folder.path}/fins_das_sessoes.json').writeAsStringSync(
      '{"team": {"team": true}, "clip": {"url": "/a", "fixed_line": ""}, '
      '"broken": {"url": 7}, "empty": {}, "text": "x"}',
    );
    final ledger = CurrentSessionLedger(home: () async => home);

    expect((await ledger.endOf('team'))?.line, isNull);
    expect(await ledger.endOf('team'), isNotNull);
    expect((await ledger.endOf('clip'))?.line?.url, '/a');
    expect(await ledger.endOf('broken'), isNull);
    expect(await ledger.endOf('empty'), isNull);
    expect(await ledger.endOf('text'), isNull);
  });
}
