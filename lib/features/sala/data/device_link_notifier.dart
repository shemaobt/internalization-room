import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../dev/dev_skip_bar.dart';
import '../domain/device_link.dart';
import 'credential_vault.dart';
import 'hand_inbox_repository.dart';
import 'linked_team.dart';
import 'room_repository.dart';
import 'session_notifier.dart';

/// How often the tablet asks whether its code has been spent yet.
///
/// A provider, not a constant, for the reason every other timing value here is one: a wait
/// no test can shrink is a wait no test can reach. Thirty seconds is the room's own settle
/// cadence, which is slow enough that a tablet waiting all afternoon is not a load and fast
/// enough that the facilitator has walked back to the table by the time it lands.
///
/// Nullable like `beckonIntervalProvider`, and for its reason: a widget test that ends with
/// a timer still armed fails on the pending timer rather than on what it was looking at.
final linkPollIntervalProvider = Provider<Duration?>(
  (ref) => const Duration(seconds: 30),
);

class DeviceLink {
  final ClaimCode? code;
  final TeamLink? team;

  const DeviceLink({this.code, this.team});

  bool get linked => team != null;
}

class DeviceLinkNotifier extends Notifier<DeviceLink> {
  Timer? _next;
  String? _deviceId;
  String? _credential;
  int _failures = 0;
  bool _closed = false;

  RoomRepository get _room => ref.read(roomRepositoryProvider);

  LinkedTeam get _ledger => ref.read(linkedTeamProvider);

  HandInboxRepository get _inbox => ref.read(handInboxRepositoryProvider);

  @override
  DeviceLink build() {
    ref.onDispose(() {
      _closed = true;
      _next?.cancel();
    });
    return const DeviceLink();
  }

  /// Find out who this tablet belongs to, and keep asking until somebody says.
  Future<void> findTheTeam() async {
    if (Env.devAtalhos ||
        (ref.read(debugBuildProvider) && Env.devPularFases)) {
      state = const DeviceLink(team: TeamLink(projectId: 'dev'));
      return;
    }
    final remembered = await _ledger.read();
    if (_closed) return;
    if (remembered.credentialUnavailable) {
      // The vault could not say whether this device already holds a credential. Asking
      // the server for one now risks a 403 for a credential that is not actually lost —
      // only unreadable right now — which would forget a vínculo that is not broken.
      // Looked at again on the same cadence a network failure already uses.
      _tryAgainLater(findTheTeam);
      return;
    }
    _failures = 0;
    _deviceId = remembered.deviceId;
    _present(remembered.credential);
    final team = remembered.team;
    if (team != null) {
      state = DeviceLink(team: team);
      return _collectTheCredential();
    }
    await _lookForTheTeam();
  }

  /// Draw the one copy of this tablet's credential, and never draw it twice.
  ///
  /// The server keeps only a hash of what it hands over, so a second ask is answered 403
  /// forever — which is also what a 200 lost on the way back turns into. Collecting is
  /// therefore something a tablet does once in its life, right after it learns whose it
  /// is, and a tablet linked before any of this existed does it on its next start.
  Future<void> _collectTheCredential() async {
    if (_closed || _credential != null) return;
    final deviceId = _deviceId;
    if (deviceId == null) return;
    // Held before the ask, because the ledger is read off a container the tablet being
    // put down disposes. The vault behind it is what the answer has to reach, and it
    // outlives both.
    final ledger = _ledger;
    final String credential;
    try {
      credential = await _room.collectTheCredential(deviceId);
    } on CredentialNotYet {
      _lookAgainLater();
      return;
    } on CredentialTaken {
      await _startOver(ledger);
      return;
    } on SessionGone {
      // The server does not know this device at all. Keeping the team beside an id
      // nobody claimed is a lie the next opening believes: it walks into the room as
      // linked, and the code the facilitator would have to write down never shows.
      await _startOver(ledger);
      return;
    } on Exception {
      _tryAgainLater(_collectTheCredential);
      return;
    }
    // The one copy was spent on the server the moment it was handed over: kept down
    // regardless of whether the tablet is still up (a credential dropped because nobody
    // was there to receive it is a credential lost for good — the next opening asks
    // again and is answered 403), and never drawn a second time from here on — asking
    // again over a write the vault merely could not finish yet would draw that same 403
    // for a credential that is not actually lost.
    await _keepCredential(ledger, credential);
    if (_closed) return;
    _failures = 0;
    _present(credential);
  }

  /// Persists a credential the server will never hand over again — retried on its own,
  /// never by asking `_room` for another one.
  Future<void> _keepCredential(LinkedTeam ledger, String credential) async {
    try {
      await ledger.rememberCredential(credential);
    } on VaultUnavailable {
      _tryAgainLater(() => _keepCredential(ledger, credential));
    }
  }

  /// Everything the tablet knew about being itself, dropped at once, and a fresh code
  /// asked for.
  ///
  /// Two answers end here. The credential is spent and that row will never hand one out
  /// again; or the server does not know the device at all. Either way the id can prove
  /// nothing, and a team kept beside it leaves the tablet believing in a vínculo no
  /// request of its will be let into — believing it hard enough that the next opening
  /// walks into the room instead of showing the code that would fix it.
  Future<void> _startOver(LinkedTeam ledger) async {
    _deviceId = null;
    await ledger.forgetTheLink();
    if (_closed) return;
    _present(null);
    await _showACode();
  }

  /// Told to everything that speaks to the room. The hand keeps a client and a header of
  /// its own, so a credential that reached only the room would leave the team's questions
  /// as the one thing still arriving unnamed.
  void _present(String? credential) {
    _credential = credential;
    _room.presents(credential);
    _inbox.presents(credential);
  }

  Future<void> _showACode() async {
    if (_closed) return;
    try {
      final code = await _room.askForACode(_deviceId);
      if (_closed) return;
      _deviceId = code.deviceId;
      _failures = 0;
      await _ledger.rememberDevice(code.deviceId);
      state = DeviceLink(code: code);
      _lookAgainLater();
    } on Exception {
      _tryAgainLater(_showACode);
    }
  }

  Future<void> _lookForTheTeam() async {
    if (_closed) return;
    final deviceId = _deviceId;
    if (deviceId == null) return _showACode();
    try {
      final team = await _room.readTheLink(deviceId);
      if (_closed) return;
      _failures = 0;
      if (team != null) {
        await _ledger.rememberTeam(team);
        if (_closed) return;
        state = DeviceLink(team: team);
        return _collectTheCredential();
      }
      final showing = state.code;
      if (showing == null || showing.ranOutBy(DateTime.now())) return _showACode();
      _lookAgainLater();
    } on SessionGone {
      _deviceId = null;
      await _showACode();
    } on Exception {
      _tryAgainLater(_lookForTheTeam);
    }
  }

  void _lookAgainLater() {
    if (_closed) return;
    final every = ref.read(linkPollIntervalProvider);
    if (every != null) _ask(every, _lookForTheTeam);
  }

  void _tryAgainLater(Future<void> Function() again) {
    if (_closed) return;
    final backoff = ref.read(roomRetryBackoffProvider);
    _ask(backoff[min(_failures, backoff.length - 1)], again);
    _failures++;
  }

  void _ask(Duration delay, Future<void> Function() what) {
    _next?.cancel();
    _next = Timer(delay, () => unawaited(what()));
  }
}

final deviceLinkProvider = NotifierProvider<DeviceLinkNotifier, DeviceLink>(
  DeviceLinkNotifier.new,
);
