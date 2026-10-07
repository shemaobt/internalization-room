import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'session_notifier_test.dart' show inConversa;

const _theNetworkDrops = NetworkFailed('a rede caiu');

class _Take {
  final SalaHarness harness;
  final ProviderContainer container;
  final int repliesBefore;
  final List<String?> askedBefore;
  final List<SalaSessionState> seen = [];

  _Take(this.harness, this.container)
    : repliesBefore = _replies(harness),
      askedBefore = [...harness.room.turnIdsAsked];

  SalaSessionState get room => container.read(salaSessionProvider);

  int get repliesHeard => _replies(harness) - repliesBefore;

  bool get everOffline => seen.any((state) => state.offline);

  bool get offlineNoticeSpoken =>
      harness.voice.assets.contains(offlineNoticeAsset(testLanguage));

  String get takeTurnId => harness.room.turnIdsSent.single;
}

int _replies(SalaHarness harness) =>
    harness.voice.played.where((url) => url == turnoUrl).length;

/// One take in the conversa, on a fake clock that starts the moment the take is sent.
void _aTake(
  void Function(FakeRoom room) arrange,
  void Function(FakeAsync clock, _Take take) check, {
  SalaHarness? harness,
}) {
  fakeAsync((clock) {
    final room = harness ?? SalaHarness();
    ProviderContainer? container;
    unawaited(inConversa(room).then((opened) => container = opened));
    clock.elapse(const Duration(seconds: 1));
    addTearDown(() => container?.dispose());
    final take = _Take(room, container!);
    container!.listen(salaSessionProvider, (_, next) => take.seen.add(next));
    arrange(room.room);
    final sala = container!.read(salaSessionProvider.notifier);
    sala.conversaTap();
    clock.elapse(const Duration(milliseconds: 100));
    sala.conversaTap();
    clock.flushMicrotasks();
    check(clock, take);
  });
}

void _theReplyLandedAndTheNetworkDropped(FakeRoom room) => room
  ..failTurnsWith = _theNetworkDrops
  ..turnsLandBeforeTheyFail = true;

void _theServerNeverGotIt(FakeRoom room) =>
    room.failTurnsWith = _theNetworkDrops;

void _theTurnTakesLongAndLands(FakeRoom room) => room
  ..holdNextTurn()
  ..turnsLandBeforeTheyFail = true;

void _theTurnTakesLongAndNothingLands(FakeRoom room) => room.holdNextTurn();

Future<void> _keepARehearsalPart(SalaSessionNotifier sala) async {
  sala.goEnsaio();
  sala.ensaioTap();
  sala.ensaioTap();
  await Future<void>.delayed(const Duration(milliseconds: 120));
  sala.takeKeep();
}

void main() {
  test(
    'A turn whose reply was stored while the network dropped plays that reply when the tablet looks.',
    () {
      _aTake(_theReplyLandedAndTheNetworkDropped, (clock, take) {
        clock.elapse(const Duration(seconds: 2));

        expect(take.repliesHeard, 1);
        expect(take.room.needsPerson, isFalse);
        expect(take.everOffline, isFalse);
        expect(take.offlineNoticeSpoken, isFalse);
      });
    },
  );

  test(
    'A turn the server never received shows the person sign, never the offline face.',
    () {
      _aTake(_theServerNeverGotIt, (clock, take) {
        clock.elapse(const Duration(seconds: 2));

        expect(take.room.needsPerson, isTrue);
        expect(take.everOffline, isFalse);
        expect(take.offlineNoticeSpoken, isFalse);
        final recording = take.harness.room.recordingsSent.single;
        expect(File(recording).existsSync(), isTrue);
        expect(take.harness.recorder.deleted, isNot(contains(recording)));

        clock.elapse(const Duration(minutes: 1));

        expect(
          take.harness.room.turnsSent,
          1,
          reason: 'a take guardada não sai de novo sozinha',
        );
      });
    },
  );

  test('A turn that passed 305 seconds plays the reply that landed.', () {
    _aTake(_theTurnTakesLongAndLands, (clock, take) {
      clock.elapse(const Duration(seconds: 304));

      expect(take.harness.room.turnIdsLookedAt, isEmpty);
      expect(take.repliesHeard, 0);

      clock.elapse(const Duration(seconds: 2));

      expect(take.harness.room.turnIdsLookedAt, [take.takeTurnId]);
      expect(take.repliesHeard, 1);
      expect(take.room.needsPerson, isFalse);
      expect(take.everOffline, isFalse);
    });
  });

  test(
    'A turn that passed 305 seconds with nothing landed shows the person sign.',
    () {
      _aTake(_theTurnTakesLongAndNothingLands, (clock, take) {
        clock.elapse(const Duration(seconds: 304));

        expect(take.room.needsPerson, isFalse);

        clock.elapse(const Duration(seconds: 2));

        expect(take.harness.room.turnIdsLookedAt, [take.takeTurnId]);
        expect(take.room.needsPerson, isTrue);
        expect(take.everOffline, isFalse);
        expect(take.offlineNoticeSpoken, isFalse);
      });
    },
  );

  test('One take is never more than one turn on the session.', () {
    for (final arrange in [
      _theReplyLandedAndTheNetworkDropped,
      _theServerNeverGotIt,
      _theTurnTakesLongAndLands,
      _theTurnTakesLongAndNothingLands,
    ]) {
      _aTake(arrange, (clock, take) {
        clock.elapse(const Duration(minutes: 7));

        final room = take.harness.room;
        expect(room.turnIdsSent, hasLength(1));
        expect(room.turnIdsLookedAt, [take.takeTurnId]);
        expect(room.turnIdsAsked, take.askedBefore);
      });
    }
  });

  test(
    'A look that finds the turn still in flight, or fails itself, shows the person sign.',
    () {
      for (final theLook in <void Function(FakeRoom)>[
        (room) => room.looksFindTheTurnInFlight = true,
        (room) => room.failLooksWith = _theNetworkDrops,
      ]) {
        _aTake(
          (room) {
            _theServerNeverGotIt(room);
            theLook(room);
          },
          (clock, take) {
            clock.elapse(const Duration(seconds: 1));

            expect(take.harness.room.turnIdsLookedAt, [take.takeTurnId]);
            expect(take.room.needsPerson, isTrue);
            expect(take.everOffline, isFalse);
            expect(take.offlineNoticeSpoken, isFalse);
          },
        );
      }
    },
  );

  test('The watchdog\'s give-up is decided by the failure policy.', () {
    _aTake(
      _theTurnTakesLongAndLands,
      (clock, take) {
        clock.elapse(const Duration(seconds: 29));

        expect(take.harness.room.turnIdsLookedAt, isEmpty);

        clock.elapse(const Duration(seconds: 2));

        expect(take.harness.room.turnIdsLookedAt, [take.takeTurnId]);
        expect(take.repliesHeard, 1);
        expect(take.room.needsPerson, isFalse);

        clock.elapse(const Duration(seconds: 300));

        expect(
          take.harness.room.turnIdsLookedAt,
          hasLength(1),
          reason: 'quem desiste primeiro consome o turno',
        );
        expect(take.repliesHeard, 1);
      },
      harness: SalaHarness(busyCeiling: const Duration(seconds: 30)),
    );
  });

  test(
    'an opening the look finds under a standing halt is heard once when the halt lifts, and no second opening is asked',
    () async {
      final harness = SalaHarness();
      harness.room
        ..holdNextTurn()
        ..turnsLandBeforeTheyFail = true;
      final container = harness.container();
      addTearDown(container.dispose);
      final sala = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);

      unawaited(sala.goConversa(pericope: 'P01'));
      await waitFor(
        'a abertura sair',
        () => harness.room.turnIdsAsked.length == 1,
      );
      sala.haltForABrokenBuild();
      await waitFor('a sala parar', () => read().needsPerson);
      harness.room
        ..failHeldTurnWith = _theNetworkDrops
        ..finishHeldTurn();
      await waitFor(
        'a sala olhar a abertura',
        () => harness.room.turnIdsLookedAt.length == 1,
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));

      sala.resolveWithPerson();
      await waitFor('a parada sair', () => !read().needsPerson);
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(harness.room.turnIdsAsked, hasLength(1));
      expect(_replies(harness), 1);
    },
  );

  test(
    'an opening refused under a standing halt is let go, and the lift asks nothing',
    () async {
      final harness = SalaHarness()..room.holdNextTurn();
      final container = harness.container();
      addTearDown(container.dispose);
      final sala = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);

      unawaited(sala.goConversa(pericope: 'P01'));
      await waitFor(
        'a abertura sair',
        () => harness.room.turnIdsAsked.length == 1,
      );
      sala.haltForABrokenBuild();
      await waitFor('a sala parar', () => read().needsPerson);
      harness.room
        ..failHeldTurnWith = const Refused('BAD_REQUEST')
        ..finishHeldTurn();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      harness.room.theDeskAttended();
      sala.resolveWithPerson();
      await waitFor('a sala soltar', () => !read().needsPerson);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(harness.room.turnIdsAsked, hasLength(1));
      expect(_replies(harness), 0);
    },
  );

  test(
    'A door that is not a turn still falls out of reach as today.',
    () async {
      final harness = SalaHarness(
        retryBackoff: const [Duration(milliseconds: 20)],
      )..room.unreachableTake = 'ensaio/${KeptScope.parte(1)}';
      final container = await inConversa(harness);
      addTearDown(container.dispose);
      final sala = container.read(salaSessionProvider.notifier);

      await _keepARehearsalPart(sala);

      await waitFor(
        'a sala ficar fora de alcance pela Outbox',
        () => container.read(salaSessionProvider).unreachable,
      );
      expect(container.read(salaSessionProvider).voice, VoiceState.offline);
      await waitFor(
        'o aviso de fora do ar ser dito',
        () => harness.voice.assets.contains(offlineNoticeAsset(testLanguage)),
      );
      final checks = harness.network.checks;
      await waitFor(
        'a escada perguntar à sala de novo',
        () => harness.network.checks > checks,
      );
    },
  );
}
