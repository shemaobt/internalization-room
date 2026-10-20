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
final _birthPattern = RegExp(r'^(_\w+)\s*=(?![=>])');

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
      return source.substring(source.indexOf('{', start) + 1, at);
    }
  }
  return '';
}

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

Iterable<({String head, bool initialized})> _declaratorsOf(String text) sync* {
  var depth = 0;
  var initializing = false;
  final head = StringBuffer();
  for (var at = 0; at < text.length; at++) {
    final char = text[at];
    final opens = initializing ? '([{' : '([{<';
    final closes = initializing ? ')]}' : ')]}>';
    if (opens.contains(char)) depth++;
    if (closes.contains(char)) depth--;
    if (depth == 0 && char == ',') {
      yield (head: head.toString().trim(), initialized: initializing);
      head.clear();
      initializing = false;
      continue;
    }
    if (depth == 0 && !initializing && char == '=') {
      if (at + 1 < text.length && text[at + 1] == '>') return;
      initializing = true;
      continue;
    }
    if (!initializing) head.write(char);
  }
  yield (head: head.toString().trim(), initialized: initializing);
}

Iterable<_Field> _fieldsOf(String member) sync* {
  final text = member
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'@\w+ '), '')
      .trim();
  final declarators = _declaratorsOf(text).toList();
  if (declarators.isEmpty) return;
  final declaration = declarators.first.head;
  if (declaration.endsWith(')') || _accessorPattern.hasMatch(declaration)) {
    return;
  }
  for (final (:head, :initialized) in declarators) {
    final name = _namePattern.firstMatch(head)?.group(1);
    if (name != null) {
      yield (name: name, declaration: declaration, initialized: initialized);
    }
  }
}

Set<String> _bornIn(String body) {
  final born = <String>{};
  var depth = 0;
  final statement = StringBuffer();
  void ends() {
    final name = _birthPattern.firstMatch(statement.toString().trim());
    if (name != null) born.add(name.group(1)!);
    statement.clear();
  }

  for (final char in body.split('')) {
    if (depth == 0 && char == ';') {
      ends();
      continue;
    }
    if (depth == 0 && char == '{') ends();
    if ('([{'.contains(char)) depth++;
    if (')]}'.contains(char)) depth--;
    if (depth == 0 && char == '}') {
      statement.clear();
      continue;
    }
    statement.write(char);
  }
  return born;
}

void main() {
  test('every field of the room is born with its life', () {
    final room = _theClass(
      File(_theRoom).readAsStringSync().replaceAll(_commentPattern, ''),
    );
    final born = {
      ..._bornIn(_theBodyOf(room, 'void _aNewLife() {')),
      ..._bornIn(_theBodyOf(room, 'SalaSessionState build() {')),
    };

    final fields = _membersOf(room).expand(_fieldsOf).toList();
    expect(fields, isNotEmpty, reason: 'the guard reads no field of the room');

    final outlivesItsLife = <String>[];
    for (final field in fields) {
      final (:name, :declaration, :initialized) = field;
      if (_whatCrossesLives.contains(name)) continue;
      final bornWithTheLife =
          declaration.startsWith('late ') &&
          !declaration.startsWith('late final ') &&
          !initialized &&
          born.contains(name);
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
