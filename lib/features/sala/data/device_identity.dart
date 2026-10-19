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

String _mint() => _hex(_secureBytes());

/// A fresh v4 uuid, minted from the same secure bytes as the device id.
String mintAUuid() {
  final bytes = _secureBytes();
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = _hex(bytes);
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

List<int> _secureBytes() {
  final random = Random.secure();
  return List<int>.generate(16, (_) => random.nextInt(256));
}

String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
