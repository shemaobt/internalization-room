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

/// The only implementation that talks to the platform, over `FlutterSecureStorage`.
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
      // Before first unlock the Keychain can refuse to answer; that is not the same as
      // "no credential", but the tablet cannot tell the difference from here, and must
      // not delete anything on the strength of a read it could not complete.
      return null;
    }
  }

  @override
  Future<void> keep(String credential) =>
      _storage.write(key: _key, value: credential);

  @override
  Future<void> forget() => _storage.delete(key: _key);
}

final credentialVaultProvider = Provider<CredentialVault>(
  (ref) => KeychainCredentialVault(),
);
