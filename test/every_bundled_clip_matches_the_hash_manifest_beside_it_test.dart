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

List<String> _clipsIn(Directory language) => [
  for (final file in language.listSync(recursive: true).whereType<File>())
    if (file.path.endsWith('.mp3'))
      file.path.substring(language.path.length + 1),
]..sort();

void main() {
  final noManifestYet = !_languages().any((l) => _manifestOf(l).existsSync());

  test(
    'every bundled clip matches the hash manifest beside it',
    () {
      for (final language in _languages()) {
        final manifest = _manifestOf(language);
        expect(
          manifest.existsSync(),
          isTrue,
          reason: '${language.path} holds no $_manifestName',
        );
        final record = jsonDecode(manifest.readAsStringSync()) as Map;
        final named = (record['clips'] as Map).cast<String, String>();

        expect(named.keys.toList()..sort(), _clipsIn(language));
        for (final MapEntry(:key, :value) in named.entries) {
          final bytes = File('${language.path}/$key').readAsBytesSync();
          expect(sha256.convert(bytes).toString(), value, reason: key);
        }
        for (final field in ['rendered_at', 'api_commit', 'voice_id']) {
          expect(record[field], isA<String>(), reason: '$field missing');
          expect(record[field] as String, isNotEmpty, reason: '$field empty');
        }
      }
    },
    skip: noManifestYet
        ? 'no hash manifest yet: the clips are re-rendered in ENG-1458'
        : false,
  );
}
