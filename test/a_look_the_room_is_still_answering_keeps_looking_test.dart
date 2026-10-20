import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'session_notifier_test.dart' show inConversa;

const _theNetworkDrops = NetworkFailed('a rede caiu');

class _Room {
  final SalaHarness harness;
  final ProviderContainer container;
  final List<SalaSessionState> seen = [];

  _Room(this.harness, this.container) {
    container.listen(salaSessionProvider, (_, next) => seen.add(next));
  }

  SalaSessionNotifier get sala => container.read(salaSessionProvider.notifier);

  SalaSessionState get state => container.read(salaSessionProvider);

  FakeRoom get room => harness.room;

  int get replies =>
      harness.voice.played.where((url) => url == turnoUrl).length;

  bool get everOffline => seen.any((state) => state.offline);

  bool get offlineNoticeSpoken =>
      harness.voice.assets.contains(offlineNoticeAsset(testLanguage));
}

/// One take in the conversa whose answer the network loses, on a fake clock that starts
/// the moment the take is sent.
void _aTakeTheNetworkLoses(
  void Function(FakeRoom room) arrange,
  void Function(FakeAsync clock, _Room it) check, {
  SalaHarness? harness,
}) {
  fakeAsync((clock) {
    final sala = harness ?? SalaHarness();
    ProviderContainer? container;
    unawaited(inConversa(sala).then((opened) => container = opened));
    clock.elapse(const Duration(seconds: 1));
    addTearDown(() => container?.dispose());
    final it = _Room(sala, container!);
    final repliesBefore = it.replies;
    it.room.failTurnsWith = _theNetworkDrops;
    arrange(it.room);
    it.sala.conversaTap();
    clock.elapse(const Duration(milliseconds: 100));
    it.sala.conversaTap();
    clock.flushMicrotasks();
    expect(repliesBefore, 1, reason: 'a abertura tocou antes da tomada');
    check(clock, it);
  });
}

/// A brand-new session whose Opening the network loses, on a fake clock that starts as
/// the team enters the passage.
void _anOpeningTheNetworkLoses(
  void Function(FakeRoom room) arrange,
  void Function(FakeAsync clock, _Room it) check, {
  SalaHarness? harness,
}) {
  fakeAsync((clock) {
    final sala = harness ?? SalaHarness();
    final container = sala.container();
    addTearDown(container.dispose);
    final it = _Room(sala, container);
    it.room.failTurnsWith = _theNetworkDrops;
    arrange(it.room);
    unawaited(it.sala.goConversa(book: 'Ruth'));
    clock.flushMicrotasks();
    check(clock, it);
  });
}

String _theTake(_Room it) => it.room.turnIdsSent.single;

void main() {
  test(
    'a team turn the room is still answering is looked at again until its reply lands, and plays with no person called',
    () {
      _aTakeTheNetworkLoses(
        (room) => room
          ..turnsLandBeforeTheyFail = true
          ..looksStillAnswering = 2,
        (clock, it) {
          clock.elapse(const Duration(seconds: 1));

          expect(it.room.turnIdsLookedAt, [_theTake(it)]);
          expect(it.replies, 1);

          clock.elapse(const Duration(seconds: 2));

          expect(it.room.turnIdsLookedAt, [_theTake(it), _theTake(it)]);
          expect(it.replies, 1);

          clock.elapse(const Duration(seconds: 2));

          expect(it.room.turnIdsLookedAt, [
            _theTake(it),
            _theTake(it),
            _theTake(it),
          ]);
          expect(it.replies, 2, reason: 'a resposta da tomada toca uma vez');
          expect(it.state.needsPerson, isFalse);
          expect(it.everOffline, isFalse);

          clock.elapse(const Duration(seconds: 10));

          expect(it.room.turnIdsLookedAt, hasLength(3));
          expect(it.replies, 2);
        },
      );
    },
  );

  test(
    'an Opening the room is still answering, once decided, rests silent with «Ouvir de novo» armed',
    () {
      _anOpeningTheNetworkLoses(
        (room) => room
          ..turnsLandBeforeTheyFail = true
          ..looksStillAnswering = 1,
        (clock, it) {
          clock.elapse(const Duration(seconds: 1));

          expect(it.room.turnIdsLookedAt, hasLength(1));

          clock.elapse(const Duration(seconds: 2));

          expect(it.room.turnIdsLookedAt, hasLength(2));
          expect(it.harness.voice.played, isNot(contains(turnoUrl)));
          expect(it.state.voice, VoiceState.invite);
          expect(it.state.awaitingTheGuide, isFalse);
          expect(it.state.needsPerson, isFalse);
          expect(it.state.canHearAgain, isTrue);

          final asked = [...it.room.turnIdsAsked];
          unawaited(it.sala.hearAgain());
          clock.elapse(const Duration(seconds: 1));

          expect(it.replies, 1, reason: 'a abertura toca uma vez, no toque');
          expect(it.room.turnIdsAsked, asked);
        },
      );
    },
  );

  test(
    'a fail-safe Opening the room was still answering rests with «Ouvir de novo» asking the room',
    () {
      _anOpeningTheNetworkLoses(
        (room) => room
          ..turnsLandBeforeTheyFail = true
          ..turnsAreCanned = true
          ..looksStillAnswering = 1,
        (clock, it) {
          clock.elapse(const Duration(seconds: 3));

          expect(it.room.turnIdsLookedAt, hasLength(2));
          expect(it.harness.voice.played, isNot(contains(turnoUrl)));
          expect(it.state.canHearAgain, isTrue);

          final asked = it.room.turnIdsAsked.length;
          it.room.failTurnsWith = null;
          unawaited(it.sala.hearAgain());
          clock.elapse(const Duration(seconds: 1));

          expect(it.room.turnIdsAsked, hasLength(asked + 1));
        },
      );
    },
  );

  test('a look that fails itself still calls a person', () {
    _aTakeTheNetworkLoses((room) => room.failLooksWith = _theNetworkDrops, (
      clock,
      it,
    ) {
      clock.elapse(const Duration(seconds: 1));

      expect(it.room.turnIdsLookedAt, [_theTake(it)]);
      expect(it.state.needsPerson, isTrue);
      expect(it.everOffline, isFalse);
      expect(it.offlineNoticeSpoken, isFalse);
    });
  });

  group(
    'a look the room is still answering when the busy watchdog runs out is decided as nothing found',
    () {
      test('over a team turn, a person is called and the looks stop', () {
        _aTakeTheNetworkLoses(
          (room) => room.looksStillAnswering = 1000,
          (clock, it) {
            clock.elapse(const Duration(seconds: 29));

            expect(it.state.needsPerson, isFalse);

            clock.elapse(const Duration(seconds: 2));

            expect(it.state.needsPerson, isTrue);
            expect(it.everOffline, isFalse);
            final looks = it.room.turnIdsLookedAt.length;
            expect(looks, greaterThanOrEqualTo(14));

            clock.elapse(const Duration(minutes: 2));

            expect(it.room.turnIdsLookedAt, hasLength(looks));
          },
          harness: SalaHarness(busyCeiling: const Duration(seconds: 30)),
        );
      });

      test('over an Opening, the room rests at the quiet invite', () {
        _anOpeningTheNetworkLoses(
          (room) => room.looksStillAnswering = 1000,
          (clock, it) {
            clock.elapse(const Duration(seconds: 31));

            expect(it.state.needsPerson, isFalse);
            expect(it.state.voice, VoiceState.invite);
            expect(it.state.awaitingTheGuide, isFalse);
            expect(it.everOffline, isFalse);
            final looks = it.room.turnIdsLookedAt.length;
            expect(looks, greaterThanOrEqualTo(14));

            clock.elapse(const Duration(minutes: 2));

            expect(it.room.turnIdsLookedAt, hasLength(looks));
          },
          harness: SalaHarness(busyCeiling: const Duration(seconds: 30)),
        );
      });
    },
  );

  test(
    'a look the room was asked again when the busy watchdog ran out is not looked at again',
    () {
      _anOpeningTheNetworkLoses(
        (room) => room.looksStillAnswering = 1000,
        (clock, it) {
          clock.elapse(const Duration(seconds: 27));
          it.room.holdTheLooks();
          clock.elapse(const Duration(seconds: 4));

          expect(it.state.awaitingTheGuide, isFalse);
          final looks = it.room.turnIdsLookedAt.length;

          it.room.finishTheLooks();
          clock.elapse(const Duration(minutes: 2));

          expect(it.room.turnIdsLookedAt, hasLength(looks));
          expect(it.state.needsPerson, isFalse);
          expect(it.state.voice, VoiceState.invite);
        },
        harness: SalaHarness(
          busyCeiling: const Duration(seconds: 30),
          lookAgain: const Duration(seconds: 7),
        ),
      );
    },
  );

  test('a halt raised while the room is still answering stops the looks', () {
    _anOpeningTheNetworkLoses((room) => room.looksStillAnswering = 1000, (
      clock,
      it,
    ) {
      clock.elapse(const Duration(seconds: 3));
      it.sala.haltForABrokenBuild();
      clock.elapse(const Duration(seconds: 3));
      final looks = it.room.turnIdsLookedAt.length;

      clock.elapse(const Duration(minutes: 10));

      expect(it.state.needsPerson, isTrue);
      expect(it.room.turnIdsLookedAt, hasLength(looks));
    });
  });

  group('a look answered after the passage was left changes nothing', () {
    test('a look still in the air when the team leaves', () {
      _aTakeTheNetworkLoses(
        (room) => room
          ..turnsLandBeforeTheyFail = true
          ..looksStillAnswering = 1,
        (clock, it) {
          clock.elapse(const Duration(seconds: 1));
          it.room.holdTheLooks();
          clock.elapse(const Duration(seconds: 2));

          expect(it.room.turnIdsLookedAt, hasLength(2));

          unawaited(it.sala.abrirEscolha());
          clock.elapse(const Duration(seconds: 1));
          it.room.finishTheLooks();
          clock.elapse(const Duration(seconds: 10));

          expect(it.replies, 1);
          expect(it.state.needsPerson, isFalse);
          expect(it.room.turnIdsLookedAt, hasLength(2));
        },
      );
    });

    test('a look the room was still answering when the team left', () {
      _aTakeTheNetworkLoses(
        (room) => room
          ..turnsLandBeforeTheyFail = true
          ..looksStillAnswering = 1,
        (clock, it) {
          clock.elapse(const Duration(seconds: 1));

          expect(it.room.turnIdsLookedAt, hasLength(1));

          unawaited(it.sala.abrirEscolha());
          clock.elapse(const Duration(seconds: 10));

          expect(it.replies, 1);
          expect(it.state.needsPerson, isFalse);
          expect(it.room.turnIdsLookedAt, hasLength(1));
        },
      );
    });
  });
}
