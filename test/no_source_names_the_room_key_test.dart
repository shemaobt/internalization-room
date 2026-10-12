import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart' show theRoomKeyHeader;

const _itself = 'test/no_source_names_the_room_key_test.dart';

/// The one line that may name it: the doubles' own constant, read by the header tests.
const _theDoublesName = "const theRoomKeyHeader = '$theRoomKeyHeader';";

final _theRoomKey = RegExp('INTERNALIZATION_ROOM_KEY|$theRoomKeyHeader');

Iterable<File> _sources() sync* {
  for (final root in ['lib', 'test', 'tool']) {
    yield* Directory(root)
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => file.path != _itself);
  }
  yield File('.env.example');
}

void main() {
  test('no source names the room key', () {
    final offenders = [
      for (final file in _sources())
        if (_theRoomKey.hasMatch(
          file.readAsStringSync().replaceFirst(_theDoublesName, ''),
        ))
          file.path,
    ];

    expect(
      offenders,
      isEmpty,
      reason:
          'the device credential is the only thing a tablet sends; a shared key '
          'baked into the build is a secret anyone holding the package can '
          'read: ${offenders.join(', ')}',
    );
  });
}
