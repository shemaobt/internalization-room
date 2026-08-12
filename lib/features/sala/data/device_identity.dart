import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const _fileName = 'aparelho.id';

String? _remembered;
Future<String> deviceIdentity() async {
  final cached = _remembered;
  if (cached != null) return cached;
  final dir = await getApplicationSupportDirectory();
  final file = File(p.join(dir.path, _fileName));
  if (file.existsSync()) {
    final stored = (await file.readAsString()).trim();
    if (stored.isNotEmpty) return _remembered = stored;
  }
  final minted = _mint();
  await file.writeAsString(minted);
  return _remembered = minted;
}

String _mint() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}
