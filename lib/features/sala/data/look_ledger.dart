import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'choice_ledger.dart';

class LookLedger extends ChoiceLedger {
  LookLedger({super.home}) : super(fileName: 'aparencia.json', key: 'look');

  static Future<LookLedger> read({Future<Directory> Function()? home}) async {
    final ledger = LookLedger(home: home);
    await ledger.load();
    return ledger;
  }
}

final lookLedgerProvider = Provider<LookLedger>((ref) => LookLedger());

final lookProvider = NotifierProvider<Look, ThemeMode>(Look.new);

class Look extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => switch (ref.read(lookLedgerProvider).chosen) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  void choose(ThemeMode look) {
    if (look == ThemeMode.system || look == state) return;
    state = look;
    unawaited(
      ref.read(lookLedgerProvider).choose(look.name).catchError((_) {}),
    );
  }
}
