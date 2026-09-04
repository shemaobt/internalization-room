import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/device_link.dart';

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

  const RememberedLink({this.deviceId, this.team, this.credential});

  factory RememberedLink.fromJson(Map<String, Object?> json) => RememberedLink(
        deviceId: json['device_id'] as String?,
        team: json['project_id'] is String
            ? TeamLink(
                projectId: json['project_id'] as String,
                label: json['label'] as String?,
              )
            : null,
        credential: json['credential'] as String?,
      );

  Map<String, Object?> toJson() => {
        'device_id': ?deviceId,
        'project_id': ?team?.projectId,
        'label': ?team?.label,
        'credential': ?credential,
      };
}

class LinkedTeam {
  final Future<Directory> Function() _home;
  Future<void> _writes = Future<void>.value();

  LinkedTeam({Future<Directory> Function()? home})
      : _home = home ?? getApplicationSupportDirectory;

  Future<File> _file() async {
    final dir = Directory(p.join((await _home()).path, _folder));
    await dir.create(recursive: true);
    return File(p.join(dir.path, _ledger));
  }

  Future<RememberedLink> read() async {
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

  Future<void> rememberDevice(String deviceId) => _write(
        (was) => RememberedLink(
          deviceId: deviceId,
          team: was.team,
          credential: was.credential,
        ),
      );

  Future<void> rememberTeam(TeamLink team) => _write(
        (was) => RememberedLink(
          deviceId: was.deviceId,
          team: team,
          credential: was.credential,
        ),
      );

  Future<void> rememberCredential(String credential) => _write(
        (was) => RememberedLink(
          deviceId: was.deviceId,
          team: was.team,
          credential: credential,
        ),
      );

  /// Everything this tablet knew about being itself, dropped in one write.
  ///
  /// The three are one fact: a device id whose credential is spent cannot be linked
  /// again, so keeping the team beside it would leave the tablet unable to prove a
  /// vínculo it still believes in.
  Future<void> forgetTheLink() => _write((_) => const RememberedLink());

  /// Serialised, staged and flushed, like the other three ledgers, and for their reason:
  /// a read that fails must never become the base of a write.
  Future<void> _write(RememberedLink Function(RememberedLink) change) {
    final next = _writes.then((_) async {
      final file = await _file();
      if (await file.exists() && !await _readable(file)) return;
      final staging = File('${file.path}.novo');
      await staging.writeAsString(jsonEncode(change(await read()).toJson()), flush: true);
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

final linkedTeamProvider = Provider<LinkedTeam>((ref) => LinkedTeam());
