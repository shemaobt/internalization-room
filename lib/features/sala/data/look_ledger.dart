import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const _folder = 'guardadas';
const _ledger = 'aparencia.json';

class LookLedger {
  final Future<Directory> Function() _home;
  String? _chosen;
  Future<void> _writes = Future<void>.value();

  LookLedger({Future<Directory> Function()? home})
    : _home = home ?? getApplicationSupportDirectory;

  String? get chosen => _chosen;

  static Future<LookLedger> read({Future<Directory> Function()? home}) async {
    final ledger = LookLedger(home: home);
    try {
      final file = await ledger._file();
      if (await file.exists()) {
        final json =
            jsonDecode(await file.readAsString()) as Map<String, Object?>;
        ledger._chosen = json['look'] as String?;
      }
    } on Object {
      ledger._chosen = null;
    }
    return ledger;
  }

  Future<void> choose(String look) {
    _chosen = look;
    final next = _writes.then((_) async {
      final file = await _file();
      final staging = File('${file.path}.novo');
      await staging.writeAsString(jsonEncode({'look': look}), flush: true);
      await staging.rename(file.path);
    });
    _writes = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<File> _file() async {
    final dir = Directory(p.join((await _home()).path, _folder));
    await dir.create(recursive: true);
    return File(p.join(dir.path, _ledger));
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
