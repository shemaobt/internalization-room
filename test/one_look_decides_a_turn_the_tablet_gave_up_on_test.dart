import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
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

  bool get everNeededAPerson => seen.any((state) => state.needsPerson);

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
      });
    },
  );

  test('A turn the server never received shows the person sign.', () {
    _aTake(_theServerNeverGotIt, (clock, take) {
      clock.elapse(const Duration(seconds: 2));

      expect(take.room.needsPerson, isTrue);
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
  });

  test('A turn that passed 305 seconds plays the reply that landed.', () {
    _aTake(_theTurnTakesLongAndLands, (clock, take) {
      clock.elapse(const Duration(seconds: 304));

      expect(take.harness.room.turnIdsLookedAt, isEmpty);
      expect(take.repliesHeard, 0);

      clock.elapse(const Duration(seconds: 2));

      expect(take.harness.room.turnIdsLookedAt, [take.takeTurnId]);
      expect(take.repliesHeard, 1);
      expect(take.room.needsPerson, isFalse);
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
    'a turn the tablet gave up on whose look never answers lets the stuck wait go and calls nobody',
    () {
      _aTake(
        (room) => room
          ..holdNextTurn()
          ..holdTheLooks(),
        (clock, take) {
          clock.elapse(const Duration(seconds: 31));

          expect(take.harness.room.turnIdsLookedAt, [take.takeTurnId]);
          expect(take.room.needsPerson, isFalse);

          clock.elapse(const Duration(seconds: 30));

          expect(take.room.needsPerson, isFalse);
          expect(take.room.awaitingTheGuide, isFalse);
        },
        harness: SalaHarness(busyCeiling: const Duration(seconds: 30)),
      );
    },
  );

  test(
    'an opening given up under a standing halt is looked at after the tap and heard once, and no second opening is asked',
    () async {
      final harness = SalaHarness();
      harness.room
        ..holdNextTurn()
        ..turnsLandBeforeTheyFail = true;
      final container = harness.container();
      addTearDown(container.dispose);
      final sala = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);

      unawaited(sala.goConversa(book: 'Ruth', pericope: 'P01'));
      await waitFor(
        'a abertura sair',
        () => harness.room.turnIdsAsked.length == 1,
      );
      sala.haltForABrokenBuild();
      await waitFor('a sala parar', () => read().needsPerson);
      harness.room
        ..failHeldTurnWith = _theNetworkDrops
        ..finishHeldTurn();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(
        harness.room.turnIdsLookedAt,
        isEmpty,
        reason: 'nenhum look sai com a sala parada',
      );

      sala.teamTapped();
      await waitFor('a parada sair', () => !read().needsPerson);
      await waitFor(
        'a sala olhar a abertura',
        () => harness.room.turnIdsLookedAt.length == 1,
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(harness.room.turnIdsAsked, hasLength(1));
      expect(_replies(harness), 1);
    },
  );

  test(
    'an opening refused under a standing halt is let go, and the tap asks nothing',
    () async {
      final harness = SalaHarness()..room.holdNextTurn();
      final container = harness.container();
      addTearDown(container.dispose);
      final sala = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);

      unawaited(sala.goConversa(book: 'Ruth', pericope: 'P01'));
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

      sala.teamTapped();
      await waitFor('a sala soltar', () => !read().needsPerson);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(harness.room.turnIdsAsked, hasLength(1));
      expect(_replies(harness), 0);
    },
  );

  test('a look that fails over an Opening rests at the quiet invite', () async {
    final harness = SalaHarness();
    harness.room.holdNextTurn();
    final container = harness.container();
    addTearDown(container.dispose);
    final sala = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    unawaited(sala.goConversa(book: 'Ruth', pericope: 'P01'));
    await waitFor(
      'a abertura sair',
      () => harness.room.turnIdsAsked.length == 1,
    );
    harness.room
      ..failLooksWith = _theNetworkDrops
      ..failHeldTurnWith = _theNetworkDrops
      ..finishHeldTurn();
    await waitFor(
      'a sala olhar a abertura',
      () => harness.room.turnIdsLookedAt.length == 1,
    );
    await waitFor(
      'o convite descansar',
      () => read().voice == VoiceState.invite && !read().awaitingTheGuide,
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(read().needsPerson, isFalse);
    expect(read().voice, VoiceState.invite);
    expect(harness.room.calls, isNot(contains('askForAPerson')));
  });

  test('a look that fails over a spoken turn shows the sign', () {
    for (final failure in [
      const Refused(RefusalCode.unauthorized),
      _theNetworkDrops,
    ]) {
      _aTake(
        (room) => room
          ..failTurnsWith = _theNetworkDrops
          ..failLooksWith = failure,
        (clock, take) {
          clock.elapse(const Duration(seconds: 2));

          expect(take.harness.room.turnIdsLookedAt, [take.takeTurnId]);
          expect(take.room.needsPerson, isTrue, reason: '$failure');
          expect(
            take.harness.room.calls.where((call) => call == 'askForAPerson'),
            hasLength(1),
          );
        },
      );
    }
  });

  test('a look that fails while the room is still answering looks again', () {
    _aTake(
      (room) => room
        ..failTurnsWith = _theNetworkDrops
        ..looksStillAnswering = 1
        ..looksFailAfterwards.add(_theNetworkDrops),
      (clock, take) {
        clock.elapse(const Duration(seconds: 5));

        expect(take.harness.room.turnIdsLookedAt.length, greaterThan(2));
        expect(take.everNeededAPerson, isFalse);
      },
    );
  });

  test('a look the room answers 404 is still a turn nobody holds', () {
    _aTake(_theServerNeverGotIt, (clock, take) {
      clock.elapse(const Duration(seconds: 2));

      expect(take.harness.room.turnIdsLookedAt, [take.takeTurnId]);
      expect(take.room.needsPerson, isTrue);
    });
  });

  test('A door that is not a turn calls no person and leaves the circle at the '
      'invite.', () async {
    final harness = SalaHarness(
      retryBackoff: const [Duration(milliseconds: 20)],
    )..room.unreachableTake = 'ensaio/${KeptScope.parte(1)}';
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final sala = container.read(salaSessionProvider.notifier);

    await _keepARehearsalPart(sala);

    await waitFor(
      'a Outbox tentar subir a parte',
      () => harness.room.calls.contains('sendTake'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(container.read(salaSessionProvider).needsPerson, isFalse);
    expect(container.read(salaSessionProvider).voice, VoiceState.invite);
  });
}
