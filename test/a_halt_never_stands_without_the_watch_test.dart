import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';
import 'session_notifier_test.dart' show inConversa;

const _period = Duration(milliseconds: 500);

ProviderContainer _inConversa(FakeAsync async, SalaHarness harness) {
  ProviderContainer? container;
  unawaited(inConversa(harness).then((opened) => container = opened));
  async.elapse(const Duration(seconds: 1));
  return container!;
}

SalaSessionState _read(ProviderContainer container) =>
    container.read(salaSessionProvider);

void _expectTheWatchBeats(FakeAsync async, SalaHarness harness) {
  final before = stateReads(harness);
  async.elapse(_period * 3);
  expect(
    stateReads(harness),
    greaterThanOrEqualTo(before + 2),
    reason: 'a vigia lê o estado a cada período enquanto a parada está de pé',
  );
}

void main() {
  test('a halt the room raised itself is watched from the start', () {
    fakeAsync((async) {
      final harness = SalaHarness(settleDelay: _period, filaEmMemoria: true);
      final container = _inConversa(async, harness);

      container.read(salaSessionProvider.notifier).haltForABrokenBuild();
      async.elapse(Duration.zero);

      expect(_read(container).needsPerson, isTrue);
      _expectTheWatchBeats(async, harness);
      container.dispose();
    });
  });

  test('a halt the room only read is watched', () {
    fakeAsync((async) {
      final harness = SalaHarness(settleDelay: _period, filaEmMemoria: true)
        ..room.serverStatus = 'needs_person'
        ..room.serverHalt = HaltKind.blocking;
      final container = _inConversa(async, harness);

      expect(_read(container).needsPerson, isTrue);
      _expectTheWatchBeats(async, harness);
      container.dispose();
    });
  });

  test('a halt with no session has nothing to read and the long press '
      'releases it', () {
    fakeAsync((async) {
      final harness = SalaHarness(settleDelay: _period, filaEmMemoria: true);
      final container = _inConversa(async, harness);
      final notifier = container.read(salaSessionProvider.notifier);

      harness.room.failWith = const SessionGone();
      notifier.conversaTap();
      async.elapse(const Duration(milliseconds: 200));
      notifier.conversaTap();
      async.elapse(const Duration(milliseconds: 200));
      harness.room.failWith = null;
      expect(_read(container).needsPerson, isTrue);
      expect(_read(container).sessionId, isNull);

      final before = stateReads(harness);
      async.elapse(_period * 3);
      expect(stateReads(harness), before, reason: 'não há sessão a ler');

      notifier.resolveWithPerson();
      async.elapse(Duration.zero);
      expect(_read(container).needsPerson, isFalse);
      container.dispose();
    });
  });

  test('a halt that goes offline and comes back is still standing and '
      'watched', () {
    fakeAsync((async) {
      final harness = SalaHarness(settleDelay: _period, filaEmMemoria: true);
      final container = _inConversa(async, harness);
      final notifier = container.read(salaSessionProvider.notifier);

      harness.room.holdNextTurn();
      notifier.conversaTap();
      async.elapse(const Duration(milliseconds: 200));
      notifier.conversaTap();
      async.elapse(const Duration(milliseconds: 200));
      harness.room
        ..serverStatus = 'needs_person'
        ..serverHalt = HaltKind.blocking;
      notifier.haltForABrokenBuild();
      async.elapse(Duration.zero);

      harness.network.reachable = false;
      harness.room.failHeldTurnWith = const NetworkFailed('sem rede');
      harness.room.finishHeldTurn();
      async.elapse(const Duration(milliseconds: 100));
      expect(_read(container).unreachable, isTrue);

      harness.network.reachable = true;
      async.elapse(const Duration(milliseconds: 200));
      expect(_read(container).unreachable, isFalse);

      expect(
        _read(container).needsPerson,
        isTrue,
        reason: 'a queda não levou a parada',
      );
      _expectTheWatchBeats(async, harness);
      container.dispose();
    });
  });

  test('a halt written by the server alone stops the room within the '
      'Watch\'s period, with no gesture', () {
    fakeAsync((async) {
      final harness = SalaHarness(
        settleDelay: _period,
        watchesWithoutAHalt: true,
        filaEmMemoria: true,
      );
      final container = _inConversa(async, harness);
      expect(_read(container).needsPerson, isFalse);

      harness.room
        ..serverStatus = 'needs_person'
        ..serverHalt = HaltKind.blocking;
      async.elapse(_period + const Duration(milliseconds: 50));

      expect(_read(container).needsPerson, isTrue);
      expect(
        harness.room.personsAsked,
        0,
        reason: 'uma parada lida não é um novo pedido de pessoa',
      );
      container.dispose();
    });
  });
}
