import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _commentPattern = RegExp(r'//.*$', multiLine: true);
final _namedVoice = RegExp(r'\bvoice\s*:');
final _assignedVoice = RegExp(r'\bvoice\s*=(?!=)');
final _callee = RegExp(r'([A-Za-z_][A-Za-z0-9_]*)\s*$');

String _sourceWithoutComments(String path) =>
    File(path).readAsStringSync().replaceAll(_commentPattern, '');

String? _calleeOf(String source, int at) {
  var depth = 0;
  for (var i = at - 1; i >= 0; i--) {
    final char = source[i];
    if (char == ')') depth++;
    if (char == '(') {
      if (depth == 0) {
        return _callee.firstMatch(source.substring(0, i))?.group(1);
      }
      depth--;
    }
  }
  return null;
}

void main() {
  test('no code under lib/ writes the voice: it is only ever derived', () {
    final offenders = <String>[];

    for (final file
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))) {
      final source = _sourceWithoutComments(file.path);
      for (final named in _namedVoice.allMatches(source)) {
        final callee = _calleeOf(source, named.start);
        if (callee == 'copyWith' || callee == 'SalaSessionState') {
          offenders.add('${file.path} ($callee)');
        }
      }
      if (_assignedVoice.hasMatch(source)) {
        offenders.add('${file.path} (voice =)');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'the voice is a reading of the Channel, the Halt, the Reach and the '
          'Step; a write beside them is a second truth that drifts: '
          '${offenders.join(', ')}',
    );
  });
}
