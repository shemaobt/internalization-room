import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/device_link.dart';
import 'credential_vault.dart';

const _folder = 'guardadas';
const _ledger = 'vinculo.json';

/// Which device this tablet is, and which team it was linked to.
///
/// Both halves have to survive the app closing, and for different reasons. Forgetting the
/// team would put the code screen back in front of a room that is already working, which
/// is the one thing the installation moment must never do twice. Forgetting the device id
/// would abandon the row the code was drawn for, so a facilitator walking over with the
/// code written down would find a different one on the screen.
class RememberedLink {
  final String? deviceId;
  final TeamLink? team;
  final String? credential;

  /// Set only by [LinkedTeam.read] — never persisted, never produced by [fromJson] —
  /// when the vault could not answer at all. `credential` is `null` in that case too, but
  /// this is what tells a caller the difference between "unavailable" and "confirmed
  /// empty": collecting a fresh one, or forgetting the link, would be wrong for the
  /// former and right for the latter.
  final bool credentialUnavailable;

  const RememberedLink({
    this.deviceId,
    this.team,
    this.credential,
    this.credentialUnavailable = false,
  });

  factory RememberedLink.fromJson(Map<String, Object?> json) => RememberedLink(
    deviceId: json['device_id'] as String?,
    team: json['project_id'] is String
        ? TeamLink(
            projectId: json['project_id'] as String,
            label: json['label'] as String?,
          )
        : null,
    // Read, never written back: a file from before this change still carries one,
    // and `LinkedTeam.read()` is where that copy is moved into the vault.
    credential: json['credential'] as String?,
  );

  /// The file's own shape — and the one thing missing from it on purpose.
  ///
  /// ADR 0017 names the credential as the one local secret that belongs in the Keychain
  /// (`flutter_secure_storage` here), not beside it in a file `pub get`'s dependency tree
  /// can read as plainly as the team that owns the tablet can.
  Map<String, Object?> toJson() => {
    'device_id': ?deviceId,
    'project_id': ?team?.projectId,
    'label': ?team?.label,
  };
}

class LinkedTeam {
  final Future<Directory> Function() _home;
  final CredentialVault _vault;
  Future<void> _writes = Future<void>.value();

  LinkedTeam({Future<Directory> Function()? home, CredentialVault? vault})
    : _home = home ?? getApplicationSupportDirectory,
      _vault = vault ?? KeychainCredentialVault();

  Future<File> _file() async {
    final dir = Directory(p.join((await _home()).path, _folder));
    await dir.create(recursive: true);
    return File(p.join(dir.path, _ledger));
  }

  Future<RememberedLink> _readFile() async {
    final file = await _file();
    if (!await file.exists()) return const RememberedLink();
    try {
      return RememberedLink.fromJson(
        (jsonDecode(await file.readAsString()) as Map).cast<String, Object?>(),
      );
    } on Object {
      return const RememberedLink();
    }
  }

  /// The file for who this tablet is, the vault for what proves it.
  ///
  /// Migration is on read, once: a file written before the vault existed still carries a
  /// `credential`, which moves into the vault here and is rewritten out of the file — and
  /// the same line clears a credential left behind by a migration interrupted between the
  /// vault write and the file rewrite, where both would otherwise hold one.
  ///
  /// Never throws on a vault that cannot answer (before the tablet's first unlock since a
  /// reboot, the Keychain refuses every access): `credentialUnavailable` says so instead,
  /// and nothing is written — not the vault, not the file — so an old file still carrying
  /// its credential migrates on the next look that finds the vault reachable.
  Future<RememberedLink> read() async {
    final onDisk = await _readFile();
    String? vaulted;
    var unavailable = false;
    try {
      vaulted = await _vault.read();
    } on VaultUnavailable {
      unavailable = true;
    }
    if (!unavailable && onDisk.credential != null) {
      if (vaulted == null) {
        try {
          await _vault.keep(onDisk.credential!);
        } on VaultUnavailable {
          unavailable = true;
        }
      }
      if (!unavailable) {
        await _write(
          (was) => RememberedLink(deviceId: was.deviceId, team: was.team),
        );
      }
    }
    return RememberedLink(
      deviceId: onDisk.deviceId,
      team: onDisk.team,
      credential: unavailable ? null : (vaulted ?? onDisk.credential),
      credentialUnavailable: unavailable,
    );
  }

  Future<void> rememberDevice(String deviceId) =>
      _write((was) => RememberedLink(deviceId: deviceId, team: was.team));

  Future<void> rememberTeam(TeamLink team) =>
      _write((was) => RememberedLink(deviceId: was.deviceId, team: team));

  Future<void> rememberCredential(String credential) => _vault.keep(credential);

  /// Everything this tablet knew about being itself, dropped in one write.
  ///
  /// The three are one fact: a device id whose credential is spent cannot be linked
  /// again, so keeping the team beside it would leave the tablet unable to prove a
  /// vínculo it still believes in. The credential's copy lives in the vault now, so
  /// forgetting it is a second, separate erasure — not a line in the file's write.
  Future<void> forgetTheLink() async {
    await _vault.forget();
    await _write((_) => const RememberedLink());
  }

  /// Serialised, staged and flushed, like the other ledgers, and for their reason: a read
  /// that fails must never become the base of a write. Reads `_readFile` rather than
  /// `read`, which this itself is called from during migration — `read` calling back into
  /// `_write` calling back into `read` would never return.
  Future<void> _write(RememberedLink Function(RememberedLink) change) {
    final next = _writes.then((_) async {
      final file = await _file();
      if (await file.exists() && !await _readable(file)) return;
      final staging = File('${file.path}.novo');
      await staging.writeAsString(
        jsonEncode(change(await _readFile()).toJson()),
        flush: true,
      );
      await staging.rename(file.path);
    });
    _writes = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<bool> _readable(File file) async {
    try {
      jsonDecode(await file.readAsString()) as Map<String, Object?>;
      return true;
    } on Object {
      return false;
    }
  }
}

final linkedTeamProvider = Provider<LinkedTeam>(
  (ref) => LinkedTeam(vault: ref.watch(credentialVaultProvider)),
);
