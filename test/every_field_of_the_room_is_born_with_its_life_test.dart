import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _theRoom = 'lib/features/sala/data/session_notifier.dart';

const _whatCrossesLives = {
  '_highestGeneration',
  '_firstGeneration',
  '_gestures',
  '_lines',
  '_random',
};

final _commentPattern = RegExp(r'//.*$', multiLine: true);
final _accessorPattern = RegExp(r'\b(get|set)\s+\w+\s*$');
final _namePattern = RegExp(r'(_\w+)\s*$');

typedef _Field = ({String name, String declaration, bool initialized});

String _theClass(String source) {
  final start = source.indexOf('class SalaSessionNotifier ');
  return source.substring(start, source.indexOf('\n}\n', start));
}

String _theBodyOf(String source, String signature) {
  final start = source.indexOf(signature);
  if (start < 0) return '';
  var depth = 0;
  for (var at = source.indexOf('{', start); at < source.length; at++) {
    if (source[at] == '{') depth++;
    if (source[at] == '}' && --depth == 0) {
      return source.substring(start, at + 1);
    }
  }
  return '';
}

bool _isAssignedIn(String body, String field) =>
    RegExp('\\b$field\\s*=(?![=>])').hasMatch(body);

Iterable<String> _membersOf(String room) sync* {
  var depth = 0;
  var assigned = false;
  var block = false;
  final member = StringBuffer();
  for (final char in room.substring(room.indexOf('{') + 1).split('')) {
    if (depth == 0 && char == ';') {
      yield member.toString();
      member.clear();
      assigned = false;
      continue;
    }
    if (depth == 0 && char == '=') assigned = true;
    if (depth == 0 && char == '{') block = !assigned;
    if ('([{'.contains(char)) depth++;
    if (')]}'.contains(char)) depth--;
    member.write(char);
    if (depth == 0 && char == '}' && block) {
      member.clear();
      block = false;
    }
  }
}

_Field? _aField(String member) {
  final text = member
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'@\w+ '), '')
      .trim();
  if (text.contains('=>')) return null;
  final at = text.indexOf('=');
  final head = (at < 0 ? text : text.substring(0, at)).trim();
  if (head.endsWith(')') || _accessorPattern.hasMatch(head)) return null;
  final name = _namePattern.firstMatch(head)?.group(1);
  if (name == null) return null;
  return (name: name, declaration: head, initialized: at >= 0);
}

void main() {
  test('every field of the room is born with its life', () {
    final room = _theClass(
      File(_theRoom).readAsStringSync().replaceAll(_commentPattern, ''),
    );
    final birth = [
      _theBodyOf(room, 'void _aNewLife() {'),
      _theBodyOf(room, 'SalaSessionState build() {'),
    ].join('\n');

    final fields = _membersOf(room).map(_aField).nonNulls.toList();
    expect(fields, isNotEmpty, reason: 'the guard reads no field of the room');

    final outlivesItsLife = <String>[];
    for (final field in fields) {
      final (:name, :declaration, :initialized) = field;
      if (_whatCrossesLives.contains(name)) continue;
      final bornWithTheLife =
          declaration.startsWith('late ') &&
          !declaration.startsWith('late final ') &&
          !initialized &&
          _isAssignedIn(birth, name);
      if (!bornWithTheLife) outlivesItsLife.add(name);
    }

    expect(
      outlivesItsLife,
      isEmpty,
      reason:
          'a revocation rebuilds the room on the same notifier (ADR 0070); a '
          'field with its own initializer, or one _aNewLife or build never '
          'assigns, carries the earlier life into the next: '
          '${outlivesItsLife.join(', ')}',
    );
  });
}
