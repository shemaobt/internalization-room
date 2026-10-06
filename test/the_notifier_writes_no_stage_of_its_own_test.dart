import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _theNotifier = 'lib/features/sala/data/session_notifier.dart';

final _comment = RegExp(r'//.*$', multiLine: true);

final _aStageArgument = RegExp(r'\bstage:');

/// The call whose argument list holds [at]: the name before its open parenthesis.
String _theCallAround(String source, int at) {
  var depth = 0;
  for (var from = at - 1; from >= 0; from--) {
    final char = source[from];
    if (')]}'.contains(char)) depth++;
    if ('([{'.contains(char)) {
      if (depth == 0) {
        return RegExp(r'(\w+)\s*$').firstMatch(source.substring(0, from))?[1] ??
            '';
      }
      depth--;
    }
  }
  return '';
}

void main() {
  test('the notifier writes no stage of its own', () {
    final source = File(
      _theNotifier,
    ).readAsStringSync().replaceAll(_comment, '');
    final writes = [
      for (final match in _aStageArgument.allMatches(source))
        if (_theCallAround(source, match.start) != 'ResumePoint')
          source.substring(match.start, source.indexOf('\n', match.start)),
    ];

    expect(
      RegExp(r'\bSalaStage\b').allMatches(source),
      isEmpty,
      reason: 'the notifier asks the machine\'s Station, never the enum',
    );
    expect(
      writes,
      isEmpty,
      reason:
          'the Station changes only inside reduce; only the stored resume '
          'point names a stage',
    );
  });
}
