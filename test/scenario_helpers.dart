import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/bead_row.dart';
import 'package:internalization_room/features/sala/presentation/widgets/retro_view.dart';

import 'fakes.dart';

/// Finds a widget by the label its `Semantics` node carries — the room's own
/// tests read the screen the way a screen reader would, not by widget type.
Finder byLabel(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);

/// How many times the room has been asked to read the session's state back —
/// the only witness that a watch actually re-polled, since the watch itself
/// has no other observable trace.
int stateReads(SalaHarness harness) =>
    harness.room.calls.where((call) => call == 'fetchState').length;

/// A fixed pause, for the gestures whose landing has no state of its own to wait on.
Future<void> settle([
  Duration delay = const Duration(milliseconds: 120),
]) async {
  await Future<void>.delayed(delay);
}

const umaParteInteira = Duration(seconds: 30);

/// Record a part through the widget tree: two taps to bracket the take, a pump for the
/// binding to settle, then keep it and let it reach the room.
Future<void> gravarUmaParte(
  WidgetTester tester,
  SalaSessionNotifier notifier,
) async {
  notifier.ensaioTap();
  notifier.ensaioTap();
  await tester.pump(const Duration(milliseconds: 100));
  notifier.takeKeep();
  await letTheRehearsalReachTheRoom(tester);
}

/// Tell the part in the air back whole, from its beginning to its end, then let it finish.
Future<void> traduzirAParteInteira(
  WidgetTester tester,
  SalaHarness harness,
  ProviderContainer container,
) async {
  final notifier = container.read(salaSessionProvider.notifier);
  harness.playback.at = umaParteInteira;
  notifier.cortarTrecho();
  notifier.retroTap();
  await tester.pump(const Duration(milliseconds: 200));
  await confirmarATraducaoNaTela(tester, container);
  await tester.pump(const Duration(milliseconds: 600));
  harness.playback.finishPlayback();
  await tester.pump(const Duration(milliseconds: 200));
}

/// Every stretch a `RetroView`'s bead row is showing, one entry per bead.
List<String> contas(WidgetTester tester) => [
  for (final conta
      in tester
          .widget<BeadRow>(
            find.descendant(
              of: find.byType(RetroView),
              matching: find.byType(BeadRow),
            ),
          )
          .entries)
    '${conta.fill.name}${conta.current ? ' com anel' : ''}',
];

class _FileThatAnswersAtOnce implements File {
  _FileThatAnswersAtOnce(String path) : _real = Zone.root.run(() => File(path));

  final File _real;

  @override
  String get path => _real.path;

  @override
  Future<bool> exists() => Future.value(_real.existsSync());

  @override
  bool existsSync() => _real.existsSync();

  @override
  int lengthSync() => _real.lengthSync();

  @override
  void writeAsStringSync(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) => _real.writeAsStringSync(
    contents,
    mode: mode,
    encoding: encoding,
    flush: flush,
  );

  @override
  void writeAsBytesSync(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) => _real.writeAsBytesSync(bytes, mode: mode, flush: flush);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

T withDiskThatAnswersAtOnce<T>(T Function() body) => IOOverrides.runZoned(
  body,
  createFile: (path) => _FileThatAnswersAtOnce(path),
);

const everyAcknowledgementLineTheAppEverHad = ['F0', 'F1', 'F2', 'F3'];

Future<void> theHaltIsLifted(
  SalaHarness harness,
  SalaSessionNotifier notifier,
  SalaSessionState Function() read,
) async {
  harness.voice.roomFailsWith = null;
  harness.room.theDeskAttended();
  notifier.resolveWithPerson();
  await waitFor('a sala soltar', () => !read().needsPerson);
  await settle();
}
