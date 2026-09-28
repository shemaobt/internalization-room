import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/kept_take.dart';
import '../domain/session_state.dart';

const _folder = 'guardadas';
const _ledger = 'em_curso.json';

/// Where a passage was left, so the team can go back to it.
///
/// The session id lived only in memory, so leaving a passage — or the app being killed —
/// abandoned the session on the server for good. The server cannot find it again either:
/// `ir_sessions` carries no device, so nothing but this tablet can say which session
/// belonged to which passage. Everything needed to resume was already on the server; it
/// only needed to be asked for by name.
class ResumePoint {
  final String sessionId;
  final SalaStage stage;
  final List<KeptTake> takes;

  /// When the session this row names was created. The record of it, and nothing more: a
  /// resume never judges a row by its age (ADR 0031). Null for a row written before this
  /// field existed.
  final DateTime? savedAt;

  /// The language the session was created in. Null for a row written before this field
  /// existed, or before this stage carried the language forward on its own rewrites.
  final String? language;

  /// The part the team came back to the Rehearsal to record again (ADR 0026), 0-based
  /// like `parteARegravar` in the session it mirrors. Null when no part is marked, and
  /// for a row written before this field existed.
  final int? partBeingRecordedAgain;

  const ResumePoint({
    required this.sessionId,
    required this.stage,
    this.takes = const [],
    this.savedAt,
    this.language,
    this.partBeingRecordedAgain,
  });

  Map<String, Object?> toJson() => {
    'session_id': sessionId,
    'stage': stage.name,
    'saved_at': ?savedAt?.millisecondsSinceEpoch,
    'language': ?language,
    'part_being_recorded_again': ?partBeingRecordedAgain,
    'takes': [
      for (final take in takes)
        {
          'name': p.basename(take.path),
          'scope': take.scopeId,
          'take': ?take.takeId,
          'pass': take.pass,
        },
    ],
  };

  static ResumePoint? fromJson(
    Map<String, Object?> json, {
    required String folder,
  }) {
    final sessionId = json['session_id'];
    if (sessionId is! String || sessionId.isEmpty) return null;
    return ResumePoint(
      sessionId: sessionId,
      stage: SalaStage.values.firstWhere(
        (stage) => stage.name == json['stage'],
        orElse: () => SalaStage.conversa,
      ),
      savedAt: json['saved_at'] is int
          ? DateTime.fromMillisecondsSinceEpoch(json['saved_at'] as int)
          : null,
      language: json['language'] as String?,
      partBeingRecordedAgain: json['part_being_recorded_again'] as int?,
      takes: [
        for (final raw in (json['takes'] as List? ?? const []))
          if (raw is Map)
            KeptTake(
              // The name, rejoined against where the recordings live today. Storing the
              // whole path meant a restore, a reinstall or a new tablet — each of which
              // changes the container prefix — left every take pointing at a directory
              // that no longer exists, and the team was sent back to the start of the
              // conversa for good. `path` is still read so ledgers written by the
              // shipped app keep resolving; the queue took this same shape in ENG-577.
              path: p.join(
                folder,
                p.basename((raw['name'] ?? raw['path']) as String? ?? ''),
              ),
              scopeId: raw['scope'] as String? ?? KeptScope.whole,
              takeId: raw['take'] as String?,
              // A row written before the count was kept per take carries one for the
              // whole rehearsal, which says nothing about which recording of which part
              // each take is. Counting from it would number parts nobody recorded again.
              pass: raw['pass'] as int? ?? 1,
            ),
      ],
    );
  }
}

class WorkInProgress {
  final Future<Directory> Function() _home;

  /// Where the recordings themselves live, which is not where this ledger lives: the
  /// takes sit under the documents directory, the ledger under application support.
  final Future<Directory> Function() _recordings;
  Future<void> _writes = Future<void>.value();

  WorkInProgress({
    Future<Directory> Function()? home,
    Future<Directory> Function()? recordings,
  }) : _home = home ?? getApplicationSupportDirectory,
       _recordings = recordings ?? _recordingsHome;

  static Future<Directory> _recordingsHome() async => Directory(
    p.join((await getApplicationDocumentsDirectory()).path, 'recordings'),
  );

  Future<File> _file() async {
    final dir = Directory(p.join((await _home()).path, _folder));
    await dir.create(recursive: true);
    return File(p.join(dir.path, _ledger));
  }

  static String _mark(String book, String pericope) => '$book/$pericope';

  Future<Map<String, ResumePoint>> _rows() async {
    final file = await _file();
    if (!await file.exists()) return const {};
    // Outside the catch on purpose. That catch is for a file whose contents cannot be
    // parsed, and answering "nothing saved" is the honest reply to that. Failing to find
    // where the recordings live is a different thing entirely, and reporting it as an
    // empty ledger would tell a team with work waiting that they have none.
    final folder = (await _recordings()).path;
    try {
      final raw = jsonDecode(await file.readAsString()) as Map<String, Object?>;
      return {
        for (final entry in raw.entries)
          if (entry.value is Map)
            entry.key: ?ResumePoint.fromJson(
              (entry.value as Map).cast<String, Object?>(),
              folder: folder,
            ),
      };
    } on Object {
      return const {};
    }
  }

  /// The passages of this book with work waiting in them.
  Future<Set<String>> startedIn(String book) async => {
    for (final key in (await _rows()).keys)
      if (key.startsWith('$book/')) key.substring(book.length + 1),
  };

  Future<ResumePoint?> of(String book, String pericope) async =>
      (await _rows())[_mark(book, pericope)];

  Future<void> remember(String book, String pericope, ResumePoint point) =>
      _write((rows) => {...rows, _mark(book, pericope): point});

  Future<void> forget(String book, String pericope) =>
      _write((rows) => {...rows}..remove(_mark(book, pericope)));

  /// Serialised, staged and flushed — the pattern the take queue and the finished ledger
  /// both arrived at, for the same reason: a read that fails must never become the base
  /// of a write.
  Future<void> _write(
    Map<String, ResumePoint> Function(Map<String, ResumePoint>) change,
  ) {
    final next = _writes.then((_) async {
      final file = await _file();
      if (await file.exists() && !await _readable(file)) {
        // Not overwritten — the rows of every other passage are in there, and a read that
        // failed must never become the base of a write. Not swallowed either: returning
        // here reported a place as saved that was never saved, and that is the one
        // failure on this path that raises no error at any layer.
        throw FormatException('em_curso.json ilegível', file.path);
      }
      final rows = change(await _rows());
      final staging = File('${file.path}.novo');
      await staging.writeAsString(
        jsonEncode({
          for (final entry in rows.entries) entry.key: entry.value.toJson(),
        }),
        flush: true,
      );
      await staging.rename(file.path);
    });
    _writes = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<bool> _readable(File file) async {
    try {
      jsonDecode(await file.readAsString()) as Map<String, Object?>;
      return true;
    } on Object {
      return false;
    }
  }
}

final workInProgressProvider = Provider<WorkInProgress>(
  (ref) => WorkInProgress(),
);
