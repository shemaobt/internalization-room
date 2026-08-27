import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/device_link.dart';
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
  int _failures = 0;
  bool _closed = false;

  RoomRepository get _room => ref.read(roomRepositoryProvider);

  LinkedTeam get _ledger => ref.read(linkedTeamProvider);

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
    final remembered = await _ledger.read();
    if (_closed) return;
    _deviceId = remembered.deviceId;
    final team = remembered.team;
    if (team != null) {
      state = DeviceLink(team: team);
      return;
    }
    await _showACode();
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
    if (state.code?.ranOutBy(DateTime.now()) ?? false) return _showACode();
    try {
      final team = await _room.readTheLink(deviceId);
      if (_closed) return;
      _failures = 0;
      if (team == null) return _lookAgainLater();
      await _ledger.rememberTeam(team);
      state = DeviceLink(team: team);
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
