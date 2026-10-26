import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the tablet bundles no failure clip in any language', () async {
    final bundled = (await AssetManifest.loadFromAssetBundle(
      rootBundle,
    )).listAssets();

    expect(
      bundled.where(
        (path) => path.contains('sem_conexao') || path.contains('microfone'),
      ),
      isEmpty,
    );
  });

  test('the tablet bundles no sound of its own, so every line it plays comes '
      'from her file through the room', () async {
    final bundled = (await AssetManifest.loadFromAssetBundle(
      rootBundle,
    )).listAssets();

    expect(
      bundled.where(
        (path) => RegExp(
          r'\.(mp3|wav|m4a|aac|ogg|opus|flac)$',
          caseSensitive: false,
        ).hasMatch(path),
      ),
      isEmpty,
      reason:
          'o tablet levava avisos gravados que ela nunca aprovou, como '
          'gravacao_presa, fora dos dois nomes que o teste acima procura',
    );
  });

  test('every line the tablet names by itself is in a family of her file the '
      'room voices, never B, C, E or a name of ours', () {
    final named = [
      for (final file
          in Directory('lib')
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => file.path.endsWith('.dart')))
        for (final name in RegExp(
          r'''['"]([A-Z][0-9]+)['"]''',
        ).allMatches(file.readAsStringSync()))
          '${file.path} ${name.group(1)}',
    ];

    expect(named, isNotEmpty);
    expect(
      named.where((name) => !RegExp(r' [ADFPXN][0-9]+$').hasMatch(name)),
      isEmpty,
      reason:
          'o tablet pedia por nome uma fala que o app dela nunca diz sozinho, '
          'como a pausa E0',
    );
  });
}
