import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

const _audio = 'assets/audio';
const _manifestName = 'clip_hashes.json';

List<Directory> _languages() =>
    Directory(_audio).listSync().whereType<Directory>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));

File _manifestOf(Directory language) => File('${language.path}/$_manifestName');

Map _recordOf(Directory language) {
  final manifest = _manifestOf(language);
  expect(
    manifest.existsSync(),
    isTrue,
    reason: '${language.path} holds no $_manifestName',
  );
  return jsonDecode(manifest.readAsStringSync()) as Map;
}

List<String> _clipsIn(Directory language) => [
  for (final file in language.listSync(recursive: true).whereType<File>())
    if (file.path.endsWith('.mp3'))
      file.path.substring(language.path.length + 1),
]..sort();

void main() {
  test('every bundled clip matches the hash manifest beside it', () {
    for (final language in _languages()) {
      final named = (_recordOf(language)['clips'] as Map)
          .cast<String, String>();

      expect(named.keys.toList()..sort(), _clipsIn(language));
      for (final MapEntry(:key, :value) in named.entries) {
        final bytes = File('${language.path}/$key').readAsBytesSync();
        expect(sha256.convert(bytes).toString(), value, reason: key);
      }
    }
  });

  test(
    'the hash manifest says when, from which server commit and in which voice the clips were rendered',
    () {
      for (final language in _languages()) {
        final record = _recordOf(language);

        expect(
          DateTime.tryParse('${record['rendered_at']}'),
          isNotNull,
          reason: '${language.path} rendered_at',
        );
        expect(
          record['api_commit'],
          matches(RegExp(r'^[0-9a-f]{40}$')),
          reason: '${language.path} api_commit',
        );
        expect(record['voice_id'], isA<String>());
        expect(record['voice_id'] as String, isNotEmpty);
      }
    },
  );

  test('every clip listed as unrendered is a clip of the bundle', () {
    for (final language in _languages()) {
      final record = _recordOf(language);
      final unrendered = record['unrendered'];

      expect(unrendered, isA<List>(), reason: '${language.path} unrendered');
      for (final path in unrendered as List) {
        expect((record['clips'] as Map).keys, contains(path));
      }
    }
  });

  test(
    'the only clip the render left in the old voice is the Portuguese sem_conexao',
    () {
      final pt = _recordOf(Directory('$_audio/pt'));
      final en = _recordOf(Directory('$_audio/en'));

      expect(pt['unrendered'], ['sem_conexao.mp3']);
      expect(
        (pt['clips'] as Map)['sem_conexao.mp3'],
        '5abc5bc5b69aa0c64825e949f80afc5ce00a6af1c51653bf3ddb63e7f619a8cb',
      );
      expect(en['unrendered'], isEmpty);
    },
  );

  test('the bundle holds her three acknowledgements and no fourth', () {
    for (final language in _languages()) {
      final acknowledgements = _clipsIn(
        language,
      ).where((clip) => RegExp(r'^fixed/F\d+\.mp3$').hasMatch(clip));

      expect(acknowledgements, [
        'fixed/F0.mp3',
        'fixed/F1.mp3',
        'fixed/F2.mp3',
      ]);
    }
  });
}
