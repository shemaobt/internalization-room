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
  final int pass;

  const ResumePoint({
    required this.sessionId,
    required this.stage,
    this.takes = const [],
    this.pass = 1,
  });

  Map<String, Object?> toJson() => {
        'session_id': sessionId,
        'stage': stage.name,
        'pass': pass,
        'takes': [
          for (final take in takes)
            {'path': take.path, 'scope': take.scopeId},
        ],
      };

  static ResumePoint? fromJson(Map<String, Object?> json) {
    final sessionId = json['session_id'];
    if (sessionId is! String || sessionId.isEmpty) return null;
    return ResumePoint(
      sessionId: sessionId,
      stage: SalaStage.values.firstWhere(
        (stage) => stage.name == json['stage'],
        orElse: () => SalaStage.conversa,
      ),
      pass: json['pass'] as int? ?? 1,
      takes: [
        for (final raw in (json['takes'] as List? ?? const []))
          if (raw is Map)
            KeptTake(
              path: raw['path'] as String? ?? '',
              scopeId: raw['scope'] as String? ?? KeptScope.whole,
            ),
      ],
    );
  }
}

class WorkInProgress {
  final Future<Directory> Function() _home;
  Future<void> _writes = Future<void>.value();

  WorkInProgress({Future<Directory> Function()? home})
      : _home = home ?? getApplicationSupportDirectory;

  Future<File> _file() async {
    final dir = Directory(p.join((await _home()).path, _folder));
    await dir.create(recursive: true);
    return File(p.join(dir.path, _ledger));
  }

  static String _mark(String book, String pericope) => '$book/$pericope';

  Future<Map<String, ResumePoint>> _rows() async {
    final file = await _file();
    if (!await file.exists()) return const {};
    try {
      final raw = jsonDecode(await file.readAsString()) as Map<String, Object?>;
      return {
        for (final entry in raw.entries)
          if (entry.value is Map)
            entry.key: ?ResumePoint.fromJson(
              (entry.value as Map).cast<String, Object?>(),
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
      if (await file.exists() && !await _readable(file)) return;
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

final workInProgressProvider = Provider<WorkInProgress>((ref) => WorkInProgress());
