import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const _folder = 'guardadas';
const _ledger = 'passagens_feitas.json';

/// Which passages this tablet has already carried to the end.
///
/// It lives on the device, beside the take queue's own manifest, because `ir_sessions`
/// carries no identity at all — the server can say that some session of a passage reached
/// done, never that *this team* finished it. That makes the ledger per tablet, not per
/// team: swap the tablet and the record is gone. Correct for one tablet per team, and the
/// thing that moves server-side once a team login exists.
class FinishedPassages {
  static String _bookMark(String book) => 'livro:$book';

  final Future<Directory> Function() _home;

  FinishedPassages({Future<Directory> Function()? home})
      : _home = home ?? getApplicationSupportDirectory;

  Future<File> _file() async {
    final dir = Directory(p.join((await _home()).path, _folder));
    await dir.create(recursive: true);
    return File(p.join(dir.path, _ledger));
  }

  Future<Set<String>> all() async {
    final file = await _file();
    if (!await file.exists()) return {};
    try {
      final raw = jsonDecode(await file.readAsString()) as List<Object?>;
      return {for (final entry in raw) entry as String};
    } on Exception {
      return {};
    }
  }

  /// Whether the book's panorama has already been heard on this tablet.
  ///
  /// It opens the room and takes minutes. Playing it on every launch made the team sit
  /// through the whole book again before they could choose where to work, and minted an
  /// orphan panorama session on the server each time.
  Future<bool> bookOpened(String book) async =>
      (await all()).contains(_bookMark(book));

  Future<void> markBookOpened(String book) => add(_bookMark(book));

  Future<void> add(String pericope) async {
    if (pericope.isEmpty) return;
    final done = await all()..add(pericope);
    await (await _file()).writeAsString(jsonEncode(done.toList()..sort()));
  }
}

final finishedPassagesProvider = Provider<FinishedPassages>(
  (ref) => FinishedPassages(),
);
