import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _callersOfTheRoom = [
  'lib/features/sala/data/session_notifier.dart',
  'lib/features/sala/data/device_link_notifier.dart',
  'lib/features/sala/data/take_upload_queue.dart',
];

final _commentPattern = RegExp(r'//.*$', multiLine: true);
final _serverCall = RegExp(r'\b_(room|inbox)\s*\.');
final _catchAll = RegExp(r'^\s*(on\s+(Exception|Object)\b|catch\s*\()');

String _withoutComments(String path) =>
    File(path).readAsStringSync().replaceAll(_commentPattern, '');

int _closingBrace(String source, int opening) {
  var depth = 0;
  for (var at = opening; at < source.length; at++) {
    if (source[at] == '{') depth++;
    if (source[at] == '}' && --depth == 0) return at;
  }
  throw StateError('unbalanced braces after $opening');
}

List<String> _catchAllsOverAServerCall(String source) {
  final found = <String>[];
  for (final handler in RegExp(
    r'\.(catchError|onError)\(',
  ).allMatches(source)) {
    final start = source.lastIndexOf(RegExp(r'[;{}]'), handler.start) + 1;
    if (_serverCall.hasMatch(source.substring(start, handler.start))) {
      final line =
          '\n'.allMatches(source.substring(0, handler.start)).length + 1;
      found.add('line $line: ${handler.group(0)}');
    }
  }
  for (final tryBlock in RegExp(r'\btry\s*\{').allMatches(source)) {
    final bodyEnd = _closingBrace(source, tryBlock.end - 1);
    final body = source.substring(tryBlock.end, bodyEnd);
    if (!_serverCall.hasMatch(body)) continue;
    var at = bodyEnd + 1;
    while (true) {
      final rest = source.substring(at);
      final clause = RegExp(
        r'^\s*(on\s+\w+[^{]*|catch\s*\([^)]*\))\s*\{',
      ).firstMatch(rest);
      if (clause == null) break;
      if (_catchAll.hasMatch(clause.group(0)!)) {
        final line = '\n'.allMatches(source.substring(0, at)).length + 1;
        found.add('line $line: ${clause.group(1)!.trim()}');
      }
      at = _closingBrace(source, at + clause.end - 1) + 1;
    }
  }
  return found;
}

void main() {
  for (final path in _callersOfTheRoom) {
    test('$path catches nothing generic over a call to the server', () {
      expect(
        _catchAllsOverAServerCall(_withoutComments(path)),
        isEmpty,
        reason:
            'the room client answers every door with one of four results; a '
            'generic catch over a call to it hides a case the switch should name',
      );
    });
  }

  test(
    'the guard sees a generic catch over a server call, and nothing else',
    () {
      const overTheRoom = '''
      Future<void> a() async {
        try {
          await _room.fetchState('s');
        } on SessionGone {
          return;
        } on Exception {
          return;
        }
      }
    ''';
      const overTheDisk = '''
      Future<void> b() async {
        try {
          await queue.enqueue(file);
        } on Exception {
          return;
        }
      }
    ''';
      const bareOverTheInbox = '''
      Future<void> c() async {
        try {
          await _inbox.sendQuestion('s', file);
        } catch (error) {
          return;
        }
      }
    ''';

      const aHandlerOverTheRoom = '''
      Future<void> d() async {
        unawaited(_room.fetchState('s').catchError((_) => false));
      }
    ''';
      const aHandlerOverTheDisk = '''
      Future<void> e() async {
        unawaited(_feitas.markBookOpened(_book).catchError((_) {}));
      }
    ''';

      expect(_catchAllsOverAServerCall(overTheRoom), hasLength(1));
      expect(_catchAllsOverAServerCall(aHandlerOverTheRoom), hasLength(1));
      expect(_catchAllsOverAServerCall(aHandlerOverTheDisk), isEmpty);
      expect(_catchAllsOverAServerCall(overTheDisk), isEmpty);
      expect(_catchAllsOverAServerCall(bareOverTheInbox), hasLength(1));
    },
  );
}
