import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../dev/dev_skip_bar.dart';
import '../domain/device_link.dart';
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
    try {
      final credential = await _room.collectTheCredential(deviceId);
      if (_closed) return;
      _failures = 0;
      await _ledger.rememberCredential(credential);
      if (_closed) return;
      _present(credential);
    } on CredentialNotYet {
      // Not claimed yet, or out of service — both may change. Going on asking whose the
      // tablet is is the answer, and the next cycle tries to collect again.
      _lookAgainLater();
    } on CredentialTaken {
      await _startOver();
    } on SessionGone {
      _deviceId = null;
      await _showACode();
    } on Exception {
      _tryAgainLater(_collectTheCredential);
    }
  }

  /// The credential is spent, and the device id is spent with it: that row will never
  /// hand one out again. Everything the tablet knew about being itself goes at once —
  /// keeping the team beside a device it can no longer prove leaves it linked to a room
  /// no request of its will be let into.
  Future<void> _startOver() async {
    _deviceId = null;
    _present(null);
    await _ledger.forgetTheLink();
    if (_closed) return;
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
