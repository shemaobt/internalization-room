import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const _folder = 'guardadas';
const _ledger = 'lingua_da_sala.json';

class RoomLanguageLedger {
  final Future<Directory> Function() _home;
  String? _chosen;
  Future<void> _writes = Future<void>.value();

  RoomLanguageLedger({Future<Directory> Function()? home})
    : _home = home ?? getApplicationSupportDirectory;

  String? get chosen => _chosen;

  static Future<RoomLanguageLedger> read({
    Future<Directory> Function()? home,
  }) async {
    final ledger = RoomLanguageLedger(home: home);
    try {
      final file = await ledger._file();
      if (await file.exists()) {
        final json =
            jsonDecode(await file.readAsString()) as Map<String, Object?>;
        ledger._chosen = json['language'] as String?;
      }
    } on Object {
      ledger._chosen = null;
    }
    return ledger;
  }

  Future<void> choose(String language) {
    _chosen = language;
    final next = _writes.then((_) async {
      final file = await _file();
      final staging = File('${file.path}.novo');
      await staging.writeAsString(
        jsonEncode({'language': language}),
        flush: true,
      );
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

final roomLanguageLedgerProvider = Provider<RoomLanguageLedger>(
  (ref) => RoomLanguageLedger(),
);
