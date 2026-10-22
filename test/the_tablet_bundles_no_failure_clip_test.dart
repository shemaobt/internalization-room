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
}
