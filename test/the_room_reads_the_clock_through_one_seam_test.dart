import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _commentPattern = RegExp(r'//.*$', multiLine: true);
final _wallClockPattern = RegExp(
  r'\bDateTime\.(now|timestamp)\b|\bStopwatch\s*\(\s*\)',
);

String _sourceWithoutComments(String path) =>
    File(path).readAsStringSync().replaceAll(_commentPattern, '');

void main() {
  test('no read of the wall clock under lib/ bypasses package:clock', () {
    final offenders = <String>[];

    for (final file
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))) {
      final source = _sourceWithoutComments(file.path);
      final reads = _wallClockPattern.allMatches(source).length;
      if (reads > 0) offenders.add('${file.path} ($reads)');
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'every "now" the room reads comes from package:clock, so a test '
          'can drive it on a fake clock; DateTime.now or a bare Stopwatch() '
          'puts the wall clock back: ${offenders.join(', ')}',
    );
  });
}
