import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/halt.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show settle;
import 'session_notifier_test.dart' show inConversa;

const _theNetworkDrops = NetworkFailed('a rede caiu');

class _Room {
  final SalaHarness harness;
  final ProviderContainer container;
  _Room(this.harness, this.container);

  SalaSessionNotifier get sala => container.read(salaSessionProvider.notifier);

  SalaSessionState get state => container.read(salaSessionProvider);

  FakeRoom get room => harness.room;

  int get replies =>
      harness.voice.played.where((url) => url == turnoUrl).length;
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
    'a fail-safe Opening the room was still answering rests with «Ouvir de novo» saying that line',
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

          expect(it.harness.voice.played, contains(turnoUrl));
          expect(it.room.turnIdsAsked, hasLength(asked));
        },
      );
    },
  );

  group(
    'after the room said it is still answering, a look that fails or finds nothing looks again',
    () {
      for (final (failure, name) in [
        (_theNetworkDrops, 'the network drops'),
        (const Refused(RefusalCode.notFound), 'nothing is stored there'),
      ]) {
        test('over a team turn, when $name', () {
          _aTakeTheNetworkLoses(
            (room) {
              room
                ..turnsLandBeforeTheyFail = true
                ..looksStillAnswering = 1;
              room.looksFailAfterwards.add(failure);
            },
            (clock, it) {
              clock.elapse(const Duration(seconds: 6));

              expect(it.room.turnIdsLookedAt, hasLength(3));
              expect(it.replies, 2, reason: 'a resposta da tomada toca');
              expect(it.state.needsPerson, isFalse);
            },
          );
        });

        test('over an Opening, when $name', () {
          _anOpeningTheNetworkLoses(
            (room) {
              room
                ..turnsLandBeforeTheyFail = true
                ..looksStillAnswering = 1;
              room.looksFailAfterwards.add(failure);
            },
            (clock, it) {
              clock.elapse(const Duration(seconds: 6));

              expect(it.room.turnIdsLookedAt, hasLength(3));
              expect(it.harness.voice.played, isNot(contains(turnoUrl)));
              expect(it.state.canHearAgain, isTrue);
              expect(it.state.needsPerson, isFalse);
            },
          );
        });
      }
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

  group('an Opening the busy watchdog gave up on while the room still drafts '
      'it', () {
    void theTeamSpeaks(FakeAsync clock, _Room it) {
      it.sala.conversaTap();
      clock.elapse(const Duration(milliseconds: 100));
      it.sala.conversaTap();
      clock.flushMicrotasks();
    }

    test('lets the team\'s next tap record a turn whose reply plays', () {
      _anOpeningTheNetworkLoses(
        (room) => room.looksStillAnswering = 1000,
        (clock, it) {
          clock.elapse(const Duration(seconds: 31));
          expect(it.state.voice, VoiceState.invite);
          it.room.failTurnsWith = null;

          theTeamSpeaks(clock, it);
          clock.elapse(const Duration(seconds: 1));

          expect(it.room.turnsSent, 1);
          expect(it.room.turnIdsAsked, hasLength(1));
          expect(it.harness.voice.played, [turnoUrl]);
        },
        harness: SalaHarness(busyCeiling: const Duration(seconds: 30)),
      );
    });

    test('answers a team turn sent meanwhile with its own reply, and nothing '
        'plays before it', () {
      _anOpeningTheNetworkLoses(
        (room) => room.looksStillAnswering = 1000,
        (clock, it) {
          clock.elapse(const Duration(seconds: 31));
          it.room
            ..failTurnsWith = null
            ..holdNextTurn();

          theTeamSpeaks(clock, it);
          clock.elapse(const Duration(seconds: 20));

          expect(it.harness.voice.played, isEmpty);

          it.room.finishHeldTurn();
          clock.elapse(const Duration(seconds: 1));

          expect(it.harness.voice.played, [turnoUrl]);
          expect(it.state.needsPerson, isFalse);
        },
        harness: SalaHarness(busyCeiling: const Duration(seconds: 30)),
      );
    });
  });

  test(
    'the busy watchdog running out between two looks makes no further look',
    () {
      _anOpeningTheNetworkLoses(
        (room) => room.looksStillAnswering = 1000,
        (clock, it) {
          clock.elapse(const Duration(seconds: 31));

          expect(it.state.awaitingTheGuide, isFalse);
          final looks = it.room.turnIdsLookedAt.length;

          clock.elapse(const Duration(minutes: 2));

          expect(it.room.turnIdsLookedAt, hasLength(looks));
        },
        harness: SalaHarness(
          busyCeiling: const Duration(seconds: 30),
          lookAgain: const Duration(seconds: 7),
        ),
      );
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

  group('a halt suspends the look, and the team\'s tap resumes it', () {
    const ceiling = Duration(seconds: 30);
    void lift(_Room it) {
      it.sala.teamTapped();
    }

    test('over a team turn the room is still answering', () {
      _aTakeTheNetworkLoses(
        (room) => room.looksStillAnswering = 100000,
        (clock, it) {
          clock.elapse(const Duration(seconds: 3));
          it.sala.haltForABrokenBuild();
          clock.flushMicrotasks();
          final looks = it.room.turnIdsLookedAt.length;
          clock.elapse(const Duration(minutes: 10));

          expect(it.room.turnIdsLookedAt, hasLength(looks));

          lift(it);
          clock.elapse(const Duration(seconds: 10));

          expect(it.state.needsPerson, isFalse);
          expect(it.room.turnIdsLookedAt.length, greaterThan(looks + 2));

          clock.elapse(const Duration(seconds: 25));
          final decided = it.room.turnIdsLookedAt.length;

          expect(it.state.needsPerson, isTrue);
          clock.elapse(const Duration(minutes: 5));
          expect(it.room.turnIdsLookedAt, hasLength(decided));
        },
        harness: SalaHarness(busyCeiling: ceiling),
      );
    });

    test('over an Opening whose first look was in the air', () {
      _anOpeningTheNetworkLoses(
        (room) => room
          ..looksStillAnswering = 100000
          ..holdTheLooks(),
        (clock, it) {
          clock.elapse(const Duration(seconds: 1));
          it.sala.haltForABrokenBuild();
          clock.elapse(const Duration(seconds: 1));
          it.room.finishTheLooks();
          clock.elapse(const Duration(minutes: 10));

          expect(it.room.turnIdsLookedAt, hasLength(1));

          lift(it);
          clock.elapse(const Duration(seconds: 10));

          expect(it.room.turnIdsLookedAt.length, greaterThan(3));

          clock.elapse(const Duration(seconds: 25));
          final decided = it.room.turnIdsLookedAt.length;

          expect(it.state.needsPerson, isFalse);
          expect(it.state.voice, VoiceState.invite);
          expect(it.state.awaitingTheGuide, isFalse);
          clock.elapse(const Duration(minutes: 5));
          expect(it.room.turnIdsLookedAt, hasLength(decided));
        },
        harness: SalaHarness(busyCeiling: ceiling),
      );
    });

    group(
      'a turn given up under the halt makes its first look after the tap',
      () {
        void halted(
          void Function(FakeRoom) arrange,
          void Function(FakeAsync, _Room) after,
        ) => _aTakeTheNetworkLoses(
          (room) {
            room
              ..turnsLandBeforeTheyFail = true
              ..holdNextTurn();
            arrange(room);
          },
          (clock, it) {
            clock.elapse(const Duration(milliseconds: 500));
            it.sala.haltForABrokenBuild();
            clock.elapse(const Duration(seconds: 1));
            it.room.finishHeldTurn();
            clock.elapse(const Duration(minutes: 10));

            expect(it.room.turnIdsLookedAt, isEmpty);

            lift(it);
            after(clock, it);
          },
          harness: SalaHarness(busyCeiling: ceiling),
        );

        test('and a 202 that never ends is decided by the watchdog', () {
          halted((room) => room.looksStillAnswering = 100000, (clock, it) {
            clock.elapse(const Duration(seconds: 10));

            expect(it.room.turnIdsLookedAt.length, greaterThan(2));
            expect(it.state.needsPerson, isFalse);

            clock.elapse(const Duration(seconds: 25));
            final decided = it.room.turnIdsLookedAt.length;

            expect(it.state.needsPerson, isTrue);
            clock.elapse(const Duration(minutes: 5));
            expect(it.room.turnIdsLookedAt, hasLength(decided));
          });
        });

        test(
          'and looks that fail after a 202 still look again until the watchdog',
          () {
            halted(
              (room) {
                room.looksStillAnswering = 1;
                room.looksFailAfterwards.addAll(
                  List.filled(1000, _theNetworkDrops),
                );
              },
              (clock, it) {
                clock.elapse(const Duration(seconds: 10));

                expect(it.room.turnIdsLookedAt.length, greaterThan(2));
                expect(it.state.needsPerson, isFalse);

                clock.elapse(const Duration(seconds: 25));

                expect(it.state.needsPerson, isTrue);
              },
            );
          },
        );

        test('and the reply it finds then plays once', () {
          halted((room) => room.looksStillAnswering = 2, (clock, it) {
            clock.elapse(const Duration(seconds: 10));

            expect(it.replies, 2, reason: 'a resposta da tomada toca uma vez');
            expect(it.state.needsPerson, isFalse);
          });
        });
      },
    );

    test(
      'a team reply the first look found under the halt plays once after the tap',
      () {
        _aTakeTheNetworkLoses(
          (room) => room
            ..turnsLandBeforeTheyFail = true
            ..holdTheLooks(),
          (clock, it) {
            clock.elapse(const Duration(seconds: 1));
            it.sala.haltForABrokenBuild();
            clock.elapse(const Duration(seconds: 1));
            it.room.finishTheLooks();
            clock.elapse(const Duration(seconds: 5));

            expect(it.replies, 1);

            lift(it);
            clock.elapse(const Duration(seconds: 10));

            expect(it.replies, 2, reason: 'a resposta da tomada toca uma vez');
            expect(it.state.needsPerson, isFalse);
            expect(it.room.turnIdsLookedAt, hasLength(1));
          },
        );
      },
    );

    test(
      'an Opening the first look found under the halt is heard once after the tap',
      () {
        _anOpeningTheNetworkLoses(
          (room) => room
            ..turnsLandBeforeTheyFail = true
            ..holdTheLooks(),
          (clock, it) {
            clock.elapse(const Duration(seconds: 1));
            it.sala.haltForABrokenBuild();
            clock.elapse(const Duration(seconds: 1));
            it.room.finishTheLooks();
            clock.elapse(const Duration(seconds: 5));

            expect(it.replies, 0);

            it.room.failTurnsWith = null;
            lift(it);
            clock.elapse(const Duration(seconds: 10));

            expect(it.replies, 1);
            expect(it.room.turnIdsAsked, hasLength(1));
            expect(it.state.needsPerson, isFalse);
          },
        );
      },
    );
  });

  group(
    'a halt longer than the busy watchdog owns the wait, and the room rests after the tap',
    () {
      const ceiling = Duration(seconds: 30);
      void lift(_Room it) {
        it.sala.teamTapped();
      }

      void restsAndTakesATurn(FakeAsync clock, _Room it) {
        clock.elapse(const Duration(minutes: 10));

        expect(it.state.awaitingTheGuide, isFalse);
        expect(it.state.voice, VoiceState.invite);
        final sent = it.room.turnIdsSent.length;
        it.sala.conversaTap();
        clock.elapse(const Duration(milliseconds: 100));
        it.sala.conversaTap();
        clock.elapse(const Duration(seconds: 5));
        expect(it.room.turnIdsSent, hasLength(sent + 1));
      }

      test('a reply the first look found under the halt', () {
        _aTakeTheNetworkLoses(
          (room) => room
            ..turnsLandBeforeTheyFail = true
            ..holdTheLooks(),
          (clock, it) {
            clock.elapse(const Duration(seconds: 1));
            it.sala.haltForABrokenBuild();
            clock.elapse(const Duration(seconds: 1));
            it.room.finishTheLooks();
            clock.elapse(const Duration(seconds: 40));
            lift(it);
            clock.elapse(const Duration(seconds: 10));

            expect(it.replies, 2, reason: 'a resposta da tomada toca uma vez');
            restsAndTakesATurn(clock, it);
          },
          harness: SalaHarness(busyCeiling: ceiling),
        );
      });

      test('a turn in flight answered under the halt', () {
        _aTakeTheNetworkLoses(
          (room) => room
            ..failTurnsWith = null
            ..holdNextTurn(),
          (clock, it) {
            clock.elapse(const Duration(milliseconds: 500));
            it.sala.haltForABrokenBuild();
            clock.elapse(const Duration(seconds: 1));
            it.room.finishHeldTurn();
            clock.elapse(const Duration(minutes: 10));
            lift(it);
            clock.elapse(const Duration(seconds: 10));

            expect(it.replies, 2, reason: 'a resposta da tomada toca uma vez');
            restsAndTakesATurn(clock, it);
          },
          harness: SalaHarness(busyCeiling: ceiling),
        );
      });

      test('a resumed look found under a second halt', () {
        _aTakeTheNetworkLoses(
          (room) => room
            ..turnsLandBeforeTheyFail = true
            ..holdNextTurn(),
          (clock, it) {
            clock.elapse(const Duration(milliseconds: 500));
            it.sala.haltForABrokenBuild();
            clock.elapse(const Duration(seconds: 1));
            it.room.finishHeldTurn();
            clock.elapse(const Duration(seconds: 5));
            it.room.holdTheLooks();
            lift(it);
            clock.elapse(const Duration(seconds: 1));
            it.sala.haltForABrokenBuild();
            clock.elapse(const Duration(seconds: 1));
            it.room.finishTheLooks();
            clock.elapse(const Duration(minutes: 10));
            lift(it);
            clock.elapse(const Duration(seconds: 10));

            expect(it.replies, 2, reason: 'a resposta da tomada toca uma vez');
            restsAndTakesATurn(clock, it);
          },
          harness: SalaHarness(busyCeiling: ceiling),
        );
      });
    },
  );

  group('a look a halt held back', () {
    const turn = Turn('sessao-1', 'turno-7');
    const held = Machine(
      station: Canvas(),
      session: 'sessao-1',
      halt: Blocking(),
      look: TheLook(turn, asked: false, suspended: true),
    );

    test('goes out at the tap', () {
      final (_, effects) = reduce(held, const TeamTapped());

      expect(effects, contains(const LookAtTheSession(turn)));
    });
  });

  group('the resumed look', () {
    Future<(SalaHarness, SalaSessionState Function())> liftedUnderAHalt({
      required bool stored,
    }) async {
      final harness = SalaHarness();
      final container = await inConversa(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);

      harness.room
        ..holdNextTurn()
        ..turnsLandBeforeTheyFail = stored;
      notifier.conversaTap();
      await settle();
      notifier.conversaTap();
      await settle();
      notifier.haltForABrokenBuild();
      await waitFor('a parada chegar', () => read().needsPerson);
      harness.room.failHeldTurnWith = _theNetworkDrops;
      harness.room.finishHeldTurn();
      await settle();
      expect(harness.room.turnIdsLookedAt, isEmpty);

      notifier.teamTapped();
      return (harness, read);
    }

    test('goes out at the tap and plays the reply it finds', () async {
      final (harness, read) = await liftedUnderAHalt(stored: true);

      await waitFor(
        'a resposta tocar',
        () => harness.voice.played.where((url) => url == turnoUrl).length >= 2,
      );

      expect(harness.room.turnIdsLookedAt, hasLength(1));
      expect(read().needsPerson, isFalse);
    });

    test(
      'goes out at the tap and calls a person when it finds nothing',
      () async {
        final (harness, read) = await liftedUnderAHalt(stored: false);

        await waitFor('a pessoa ser chamada', () => read().needsPerson);

        expect(harness.room.turnIdsLookedAt, hasLength(1));
      },
    );
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
