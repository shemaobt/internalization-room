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

  /// Where the stretches mended by the long way sit in the rehearsal.
  ///
  /// The one thing about a telling-back that the server cannot hand back: a mend's take
  /// is no part of the rehearsal, so the place of the stretch it replaced is known here
  /// and nowhere else, and closing the tablet used to lose it.
  final List<LugarDoTrecho> lugares;

  /// When this row was written, so a resume can tell a session abandoned last month from
  /// one abandoned a minute ago. Null for a row written before this field existed.
  final DateTime? savedAt;

  const ResumePoint({
    required this.sessionId,
    required this.stage,
    this.takes = const [],
    this.pass = 1,
    this.lugares = const [],
    this.savedAt,
  });

  Map<String, Object?> toJson() => {
        'session_id': sessionId,
        'stage': stage.name,
        'pass': pass,
        'saved_at': ?savedAt?.millisecondsSinceEpoch,
        'takes': [
          for (final take in takes)
            {
              'name': p.basename(take.path),
              'scope': take.scopeId,
              'take': ?take.takeId,
            },
        ],
        'lugares': [
          for (final lugar in lugares)
            {
              'take': lugar.takeId,
              'parte': lugar.parte,
              'de': lugar.from.inMilliseconds,
              'ate': lugar.to.inMilliseconds,
              'segmento': ?lugar.segmentId,
              if (lugar.fallbackPath != null)
                'fallback_arquivo': p.basename(lugar.fallbackPath!),
              if (lugar.fallbackFrom != null)
                'fallback_de': lugar.fallbackFrom!.inMilliseconds,
              if (lugar.fallbackTo != null)
                'fallback_ate': lugar.fallbackTo!.inMilliseconds,
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
      pass: json['pass'] as int? ?? 1,
      savedAt: json['saved_at'] is int
          ? DateTime.fromMillisecondsSinceEpoch(json['saved_at'] as int)
          : null,
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
            ),
      ],
      lugares: [
        for (final raw in (json['lugares'] as List? ?? const []))
          if (raw is Map && raw['take'] is String && raw['parte'] is int)
            LugarDoTrecho(
              takeId: raw['take'] as String,
              parte: raw['parte'] as int,
              from: Duration(milliseconds: raw['de'] as int? ?? 0),
              to: Duration(milliseconds: raw['ate'] as int? ?? 0),
              segmentId: raw['segmento'] as String?,
              fallbackPath: raw['fallback_arquivo'] is String
                  ? p.join(folder, raw['fallback_arquivo'] as String)
                  : null,
              fallbackFrom: raw['fallback_de'] is int
                  ? Duration(milliseconds: raw['fallback_de'] as int)
                  : null,
              fallbackTo: raw['fallback_ate'] is int
                  ? Duration(milliseconds: raw['fallback_ate'] as int)
                  : null,
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
  })  : _home = home ?? getApplicationSupportDirectory,
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

final workInProgressProvider = Provider<WorkInProgress>((ref) => WorkInProgress());
