import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Directory aTempDir(String prefix) {
  final dir = Directory.systemTemp.createTempSync(prefix);
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

Future<void> underOneTempRoot(FutureOr<void> Function() testMain) async {
  final root = Directory.systemTemp.createTempSync('sala-arquivo-');
  IOOverrides.global = _TempUnder(root);
  tearDownAll(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });
  await testMain();
}

final class _TempUnder extends IOOverrides {
  final Directory root;

  _TempUnder(this.root);

  @override
  Directory getSystemTempDirectory() => root;
}
