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
final _fieldPattern = RegExp(
  r'^  (?![^\n]*(=>|\bget\b|\bset\b))(\S[^\n]*?)\s(_\w+)(\s*=[^\n]*)?;$',
  multiLine: true,
);

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
    RegExp('\\b$field = ').hasMatch(body);

void main() {
  test('every field of the room is born with its life', () {
    final room = _theClass(
      File(_theRoom).readAsStringSync().replaceAll(_commentPattern, ''),
    );
    final birth = [
      _theBodyOf(room, 'void _aNewLife() {'),
      _theBodyOf(room, 'SalaSessionState build() {'),
    ].join('\n');

    final fields = _fieldPattern.allMatches(room).toList();
    expect(fields, isNotEmpty, reason: 'the guard reads no field of the room');

    final outlivesItsLife = <String>[];
    for (final field in fields) {
      final name = field.group(3)!;
      if (_whatCrossesLives.contains(name)) continue;
      final declaration = field.group(2)!;
      final bornWithTheLife =
          declaration.startsWith('late ') &&
          !declaration.startsWith('late final ') &&
          field.group(4) == null &&
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
