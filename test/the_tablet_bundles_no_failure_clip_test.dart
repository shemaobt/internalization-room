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
}
