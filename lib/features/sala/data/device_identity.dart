import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const _fileName = 'aparelho.id';

/// Memoised as the *future*, not the value.
///
/// Caching only the result left the check-then-mint open: two callers on the first boot
/// — the hand pulling its inbox while a take uploads — both saw no file, both minted, and
/// one lost. A question already sent under the losing id can never be fetched back,
/// because the server filters replies by device.
Future<String>? _remembered;

Future<String> deviceIdentity() => _remembered ??= _findOrMint();

Future<String> _findOrMint() async {
  final dir = await getApplicationSupportDirectory();
  final file = File(p.join(dir.path, _fileName));
  if (file.existsSync()) {
    final stored = (await file.readAsString()).trim();
    if (stored.isNotEmpty) return stored;
  }
  final minted = _mint();
  await file.writeAsString(minted, flush: true);
  return minted;
}

String _mint() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}
