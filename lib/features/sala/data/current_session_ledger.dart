import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/ports.dart';
import '../domain/spoken_line.dart';
import 'staged_write.dart';

const _folder = 'guardadas';
const _ledger = 'sessao_atual.json';
const _endsLedger = 'fins_das_sessoes.json';

/// The Current session on disk, in a file of its own: every entry of the Resume points'
/// file is read as a Resume point.
class CurrentSessionLedger {
  final Future<Directory> Function() _home;
  Future<void> _writes = Future<void>.value();

  CurrentSessionLedger({Future<Directory> Function()? home})
    : _home = home ?? getApplicationSupportDirectory;

  Future<File> _file([String name = _ledger]) async {
    final dir = Directory(p.join((await _home()).path, _folder));
    await dir.create(recursive: true);
    return File(p.join(dir.path, name));
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

  Future<({SpokenLine? line})?> endOf(String session) async {
    await _writes;
    final ends = await _ends(await _file(_endsLedger));
    return ends.containsKey(session) ? (line: ends[session]) : null;
  }

  Future<void> holdTheEnd(String session, SpokenLine? line) =>
      _writeEnds((ends) => {...ends, session: line});

  Future<void> letGoOfTheEnd(String session) =>
      _writeEnds((ends) => {...ends}..remove(session));

  Future<void> _writeEnds(
    Map<String, SpokenLine?> Function(Map<String, SpokenLine?> ends) change,
  ) {
    final next = _writes.then((_) async {
      final file = await _file(_endsLedger);
      final ends = change(await _ends(file));
      if (ends.isEmpty) {
        if (await file.exists()) await file.delete();
        return;
      }
      await writeWhole(
        file,
        jsonEncode({
          for (final MapEntry(:key, :value) in ends.entries)
            key: value == null
                ? {'team': true}
                : {'url': value.url, 'fixed_line': value.fixedLine},
        }),
      );
    });
    _writes = next.then((_) {}, onError: (_) {});
    return next;
  }

  static Future<Map<String, SpokenLine?>> _ends(File file) async {
    if (!await file.exists()) return {};
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, Object?>;
      return {
        for (final MapEntry(:key, :value) in json.entries)
          if (value case {
            'url': final String url,
            'fixed_line': final String fixed,
          })
            key: SpokenLine(url: url, fixedLine: fixed)
          else if (value case {'team': true})
            key: null,
      };
    } on Object {
      return {};
    }
  }

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
      await writeWhole(
        file,
        jsonEncode({
          'session_id': session.sessionId,
          'book': session.book,
          'pericope': session.pericope,
          'language': session.language,
          if (session.lastLine case final line?) ...{
            'last_url': line.url,
            'last_fixed_line': line.fixedLine,
          },
          if (session.teamSpokeLast) 'team_spoke_last': true,
          if (session.panorama) 'panorama': true,
        }),
      );
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
        lastLine: json['last_url'] == null
            ? null
            : SpokenLine(
                url: json['last_url']! as String,
                fixedLine: json['last_fixed_line']! as String,
              ),
        teamSpokeLast: json['team_spoke_last'] == true,
        panorama: json['panorama'] == true,
      );
    } on Object {
      return null;
    }
  }
}

final currentSessionLedgerProvider = Provider<CurrentSessionLedger>(
  (ref) => CurrentSessionLedger(),
);
