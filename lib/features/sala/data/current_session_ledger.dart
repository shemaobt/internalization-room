import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/ports.dart';

const _folder = 'guardadas';
const _ledger = 'sessao_atual.json';

/// The Current session on disk, in a file of its own: every entry of the Resume points'
/// file is read as a Resume point.
class CurrentSessionLedger {
  final Future<Directory> Function() _home;
  Future<void> _writes = Future<void>.value();

  CurrentSessionLedger({Future<Directory> Function()? home})
    : _home = home ?? getApplicationSupportDirectory;

  Future<File> _file() async {
    final dir = Directory(p.join((await _home()).path, _folder));
    await dir.create(recursive: true);
    return File(p.join(dir.path, _ledger));
  }

  Future<CurrentSession?> read() async {
    await _writes;
    try {
      return await _held(await _file());
    } on Object {
      return null;
    }
  }

  Future<void> hold(CurrentSession session) => _write((_) => session);

  Future<void> letGo({String? only}) =>
      _write((held) => only == null || held?.sessionId == only ? null : held);

  /// Serialised, staged and renamed: a hold never overtakes an earlier let-go, nor the
  /// reverse. An unreadable record is written over, since it holds nothing else.
  Future<void> _write(CurrentSession? Function(CurrentSession? held) change) {
    final next = _writes.then((_) async {
      final file = await _file();
      final session = change(await _held(file));
      if (session == null) {
        if (await file.exists()) await file.delete();
        return;
      }
      final staging = File('${file.path}.novo');
      await staging.writeAsString(
        jsonEncode({
          'session_id': session.sessionId,
          'book': session.book,
          'pericope': session.pericope,
          'language': session.language,
        }),
        flush: true,
      );
      await staging.rename(file.path);
    });
    _writes = next.then((_) {}, onError: (_) {});
    return next;
  }

  static Future<CurrentSession?> _held(File file) async {
    if (!await file.exists()) return null;
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, Object?>;
      return CurrentSession(
        sessionId: json['session_id']! as String,
        book: json['book']! as String,
        pericope: json['pericope']! as String,
        language: json['language']! as String,
      );
    } on Object {
      return null;
    }
  }
}

final currentSessionLedgerProvider = Provider<CurrentSessionLedger>(
  (ref) => CurrentSessionLedger(),
);
