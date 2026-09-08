import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _key = 'device_credential';

/// Where the device's one proof of who it is lives once it leaves `vinculo.json`.
///
/// A boundary, not a client: `LinkedTeam` asks it to keep, read or forget a credential,
/// and never learns that a Keychain sits behind that on iOS (AGENTS.md §9 — "auth tokens
/// in flutter_secure_storage").
abstract class CredentialVault {
  Future<String?> read();
  Future<void> keep(String credential);
  Future<void> forget();
}

/// Thrown by [CredentialVault] when the store could not answer at all — distinct from a
/// confirmed-empty read. On iOS, `first_unlock_this_device` refuses every access before
/// the device's first unlock since a reboot; a call landing in that window must not be
/// read as "there is no credential."
class VaultUnavailable implements Exception {
  const VaultUnavailable();
}

class KeychainCredentialVault implements CredentialVault {
  final FlutterSecureStorage _storage;

  /// `first_unlock_this_device`, not the plugin's default `unlocked`: the credential must
  /// survive the tablet rebooting before anyone unlocks it (a poll started at boot must
  /// still find it), but must never leave this device — an iCloud Keychain restore onto a
  /// different tablet must not hand it a credential the server issued to another row.
  KeychainCredentialVault({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  @override
  Future<String?> read() async {
    try {
      return await _storage.read(key: _key);
    } on Object {
      throw const VaultUnavailable();
    }
  }

  @override
  Future<void> keep(String credential) async {
    try {
      await _storage.write(key: _key, value: credential);
    } on Object {
      throw const VaultUnavailable();
    }
  }

  @override
  Future<void> forget() async {
    try {
      await _storage.delete(key: _key);
    } on Object {
      throw const VaultUnavailable();
    }
  }
}

final credentialVaultProvider = Provider<CredentialVault>(
  (ref) => KeychainCredentialVault(),
);
