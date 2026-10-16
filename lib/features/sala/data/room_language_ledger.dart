import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'choice_ledger.dart';

class RoomLanguageLedger extends ChoiceLedger {
  RoomLanguageLedger({super.home})
    : super(fileName: 'lingua_da_sala.json', key: 'language');

  static Future<RoomLanguageLedger> read({
    Future<Directory> Function()? home,
  }) async {
    final ledger = RoomLanguageLedger(home: home);
    await ledger.load();
    return ledger;
  }
}

final roomLanguageLedgerProvider = Provider<RoomLanguageLedger>(
  (ref) => RoomLanguageLedger(),
);
