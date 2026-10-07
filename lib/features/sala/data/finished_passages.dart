import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const _folder = 'guardadas';
const _ledger = 'passagens_feitas.json';

/// The book every entry written before passages were scoped belonged to.
///
/// Passage ids come from the meaning maps as `P01`…`P14`, so they repeat in every book:
/// a tablet that finished Ruth would have had those numbers struck from Jonah's wheel the
/// day a second book shipped, and a book with the same passage count would have opened
/// already finished. Only Ruth has ever been served, so an unscoped entry is Ruth's.
const _legacyBook = 'Ruth';

/// Which passages this tablet has already carried to the end.
///
/// It lives on the device, beside the take queue's own manifest, because `ir_sessions`
/// carries no identity at all — the server can say that some session of a passage reached
/// done, never that *this team* finished it. That makes the ledger per tablet, not per
/// team: swap the tablet and the record is gone. Correct for one tablet per team, and the
/// thing that moves server-side once a team login exists.
class FinishedPassages {
  static String _mark(String book, String pericope) => '$book/$pericope';

  final Future<Directory> Function() _home;
  Future<void> _writes = Future<void>.value();

  FinishedPassages({Future<Directory> Function()? home})
    : _home = home ?? getApplicationSupportDirectory;

  Future<File> _file() async {
    final dir = Directory(p.join((await _home()).path, _folder));
    await dir.create(recursive: true);
    return File(p.join(dir.path, _ledger));
  }

  Future<Set<String>> _rows() async {
    final file = await _file();
    if (!await file.exists()) return {};
    try {
      final raw = jsonDecode(await file.readAsString()) as List<Object?>;
      return {for (final entry in raw) entry as String};
    } on Object {
      // `on Exception` let a `TypeError` through — a ledger holding a JSON object rather
      // than a list threw past every caller, and `abrirEscolha` reads this outside its
      // try, so the wheel silently never loaded.
      return {};
    }
  }

  /// The passages of this book the tablet has carried to the end.
  Future<Set<String>> all(String book) async {
    await _writes;
    final rows = await _rows();
    return {
      for (final row in rows)
        if (row.startsWith('$book/'))
          row.substring(book.length + 1)
        else if (book == _legacyBook &&
            !row.contains('/') &&
            !row.startsWith('livro:'))
          row,
    };
  }

  Future<void> add(String book, String pericope) {
    if (pericope.isEmpty) return Future<void>.value();
    return _remember(_mark(book, pericope));
  }

  /// Add one row, without ever writing a ledger built from a read that failed.
  ///
  /// This was a read-modify-write over a plain truncating write, unlike the take queue
  /// two files away: a kill mid-write left a partial array, that array read as `{}`, and
  /// the next passage the team finished wrote a ledger holding exactly one entry. Every
  /// passage they had already carried came back to the wheel.
  Future<void> _remember(String row) {
    final next = _writes.then((_) async {
      final file = await _file();
      if (await file.exists() && (await _readable(file)) == null) return;
      final rows = (await _rows())..add(row);
      final staging = File('${file.path}.novo');
      await staging.writeAsString(
        jsonEncode(rows.toList()..sort()),
        flush: true,
      );
      await staging.rename(file.path);
    });
    _writes = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<List<Object?>?> _readable(File file) async {
    try {
      return jsonDecode(await file.readAsString()) as List<Object?>;
    } on Object {
      return null;
    }
  }
}

final finishedPassagesProvider = Provider<FinishedPassages>(
  (ref) => FinishedPassages(),
);
