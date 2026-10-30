import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/look_ledger.dart';
import 'package:path/path.dart' as p;

import 'support/temp.dart';

void main() {
  late Directory home;

  setUp(() => home = aTempDir('sala-aparencia'));

  test('the Look the tablet chose is read back from its own file', () async {
    final first = await LookLedger.read(home: () async => home);

    expect(first.chosen, isNull);

    await first.choose('dark');
    final again = await LookLedger.read(home: () async => home);

    expect(again.chosen, 'dark');
  });

  test('an unreadable file is a tablet that never chose', () async {
    final folder = Directory(p.join(home.path, 'guardadas'))..createSync();
    File(p.join(folder.path, 'aparencia.json')).writeAsStringSync('{not json');

    final ledger = await LookLedger.read(home: () async => home);

    expect(ledger.chosen, isNull);
  });

  test(
    'two quick choices land in the order they were made, though the first is slow to reach the disk',
    () async {
      final firstWriteMayGo = Completer<void>();
      var opened = 0;
      final ledger = LookLedger(
        home: () async {
          if (opened++ == 0) await firstWriteMayGo.future;
          return home;
        },
      );

      final first = ledger.choose('dark');
      final second = ledger.choose('light');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      firstWriteMayGo.complete();
      await Future.wait([first, second]);
      final again = await LookLedger.read(home: () async => home);

      expect(again.chosen, 'light');
    },
  );
}
