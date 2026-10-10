import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/failure_policy.dart';
import 'package:internalization_room/features/sala/domain/hand_reply.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

import 'fakes.dart';
import 'machine_generator.dart';
import 'scenario_helpers.dart' show settle;
import 'session_notifier_test.dart' show inConversa;

const _aLadderThatWaits = [Duration(hours: 1)];
const _reply = HandReply(id: 'r1', audioUrl: '/resposta/r1');

class _Room {
  final SalaHarness harness;
  final ProviderContainer container;
  final List<SalaSessionState> seen = [];

  _Room(this.harness, this.container) {
    container.listen(
      salaSessionProvider,
      (_, next) => seen.add(next),
      fireImmediately: true,
    );
  }

  SalaSessionNotifier get sala => container.read(salaSessionProvider.notifier);

  SalaSessionState get estado => container.read(salaSessionProvider);

  bool get everOutOfReach => seen.any((state) => state.unreachable);

  bool get everCalledForAPerson => seen.any((state) => state.needsPerson);

  int get voiceSounds => harness.voice.sounds
      .where((sound) => sound == 'voice:line' || sound == 'voice:asset')
      .length;

  bool get offlineNoticeSaid =>
      harness.voice.assets.contains(offlineNoticeAsset(testLanguage));

  int get turnsAnswered =>
      harness.voice.played.where((url) => url == turnoUrl).length;

  int get repliesPlayed =>
      harness.voice.played.where((url) => url == _reply.audioUrl).length;

  Future<void> raisesAKnot() async {
    await opensAKnot();
    await sendsTheKnot();
  }

  Future<void> opensAKnot() async {
    sala.handTap();
    sala.conversaTap();
    await waitFor(
      'a pergunta abrir o microfone',
      () => estado.channel is Microphone,
    );
  }

  Future<void> sendsTheKnot() async {
    sala.conversaTap();
    await waitFor(
      'a pergunta sair do microfone',
      () => estado.channel is! Microphone && !estado.noteMode,
    );
    await settle();
  }

  Future<void> talksToTheVoice() async {
    sala.conversaTap();
    await settle();
    sala.conversaTap();
  }
}

Future<_Room> _conversa({List<HandReply> replies = const []}) async {
  final harness = SalaHarness(
    retryBackoff: _aLadderThatWaits,
    replies: replies,
  );
  final container = await inConversa(harness);
  addTearDown(container.dispose);
  return _Room(harness, container);
}

void _theRoomIsAsItWas(_Room room) {
  expect(room.everOutOfReach, isFalse, reason: 'a mão não tira a sala do ar');
  expect(room.everCalledForAPerson, isFalse);
  expect(room.estado.stage, SalaStage.conversa);
}

void main() {
  test(
    'A Knot whose upload fails on the network leaves the room within reach and '
    'speaks no line.',
    () async {
      final room = await _conversa();
      room.harness.inbox.knotFailsWith = const NetworkFailed('sem rede');
      final sounds = room.voiceSounds;

      await room.raisesAKnot();

      _theRoomIsAsItWas(room);
      expect(room.voiceSounds, sounds, reason: 'nenhuma linha foi dita');
      expect(room.estado.awaitingTheGuide, isFalse);
      expect(room.estado.noteMode, isFalse);
      expect(room.estado.voice, VoiceState.invite);
    },
  );

  test(
    'After a Knot lost to the network, the next tap on the circle reaches the '
    'voice once the network is back.',
    () async {
      final room = await _conversa();
      room.harness.inbox.knotFailsWith = const NetworkFailed('sem rede');
      await room.raisesAKnot();
      room.harness.inbox.knotFailsWith = null;
      final answered = room.turnsAnswered;

      await room.talksToTheVoice();

      await waitFor(
        'a voz responder o turno',
        () => room.turnsAnswered > answered,
      );
      expect(room.harness.room.turnsSent, 1);
    },
  );

  test(
    'A Knot sent after the session was reset is lost without the session-gone '
    'path.',
    () async {
      final room = await _conversa();
      room.harness.inbox.knotFailsWith = const SessionGone();
      final session = room.estado.sessionId;
      final sounds = room.voiceSounds;
      await room.opensAKnot();
      final stops = room.harness.voice.stops;

      await room.sendsTheKnot();

      _theRoomIsAsItWas(room);
      expect(room.estado.sessionId, session);
      expect(room.harness.voice.stops, stops, reason: 'nenhum som foi parado');
      expect(room.voiceSounds, sounds, reason: 'nenhuma linha foi dita');
    },
  );

  test(
    'A Knot the disk cannot read leaves the room as it was and speaks no line.',
    () async {
      final room = await _conversa();
      room.harness.inbox.cannotReadTheKnot = true;
      final sounds = room.voiceSounds;

      await room.raisesAKnot();

      _theRoomIsAsItWas(room);
      expect(room.voiceSounds, sounds, reason: 'nenhuma linha foi dita');
      expect(room.estado.awaitingTheGuide, isFalse);
      expect(room.estado.voice, VoiceState.invite);
    },
  );

  test('A refused Knot does not count toward a Call for a person.', () async {
    final room = await _conversa();
    room.harness.inbox.knotFailsWith = const Refused('QUESTION_REFUSED');
    final sounds = room.voiceSounds;

    await room.raisesAKnot();
    await room.raisesAKnot();
    await room.raisesAKnot();

    _theRoomIsAsItWas(room);
    expect(room.voiceSounds, sounds, reason: 'nenhuma linha foi dita');
  });

  test(
    'A reply clip that fails to load keeps the dot and the room within reach.',
    () async {
      final room = await _conversa(replies: const [_reply]);
      await waitFor('a resposta chegar', () => room.estado.hasUnheardReply);
      room.harness.voice.roomFailsWith = const NetworkFailed('sem rede');
      final sounds = room.voiceSounds;

      room.sala.handTap();
      await settle();

      expect(room.repliesPlayed, 1, reason: 'a sala tentou tocar a resposta');
      expect(room.estado.hasUnheardReply, isTrue);
      _theRoomIsAsItWas(room);
      expect(room.voiceSounds, sounds, reason: 'nenhuma linha foi dita');
    },
  );

  test(
    'A later tap on the hand plays the reply once its clip loads.',
    () async {
      final room = await _conversa(replies: const [_reply]);
      await waitFor('a resposta chegar', () => room.estado.hasUnheardReply);
      room.harness.voice.roomFailsWith = const NetworkFailed('sem rede');
      room.sala.handTap();
      await settle();
      room.sala.handTap();
      await settle();
      room.harness.voice.roomFailsWith = null;

      room.sala.handTap();

      await waitFor(
        'a resposta ser ouvida',
        () => room.harness.inbox.heard.contains(_reply.id),
      );
      expect(room.repliesPlayed, 3);
    },
  );

  test(
    'A heard mark that fails to save keeps the dot and speaks no line.',
    () async {
      final room = await _conversa(replies: const [_reply]);
      await waitFor('a resposta chegar', () => room.estado.hasUnheardReply);
      room.harness.inbox.marksFailWith = const NetworkFailed('sem rede');
      final sounds = room.voiceSounds;

      room.sala.handTap();
      await waitFor('a resposta tocar', () => room.repliesPlayed == 1);
      await settle();

      expect(room.estado.hasUnheardReply, isTrue);
      _theRoomIsAsItWas(room);
      expect(room.voiceSounds, sounds + 1, reason: 'só a resposta soou');
      expect(room.offlineNoticeSaid, isFalse);
    },
  );

  test('A failed check for waiting replies changes nothing on screen or in the '
      'room.', () async {
    final room = await _conversa(replies: const [_reply]);
    await waitFor('a resposta chegar', () => room.estado.hasUnheardReply);
    room.harness.inbox.cannotBeAsked = true;
    final before = room.estado;
    final checks = room.harness.inbox.checks;

    await room.talksToTheVoice();
    await waitFor(
      'a sala olhar a caixa de respostas',
      () => room.harness.inbox.checks > checks,
    );
    await settle();

    _theRoomIsAsItWas(room);
    expect(room.estado.reach, before.reach);
    expect(room.estado.hasUnheardReply, isTrue);
    expect(room.estado.voice, before.voice);
    expect(room.offlineNoticeSaid, isFalse);
  });

  test(
    'A hand failure during a live turn leaves the turn untouched.',
    () async {
      final room = await _conversa();
      room.harness.inbox.cannotBeAsked = true;
      room.harness.voice.holdNextLine();
      final checks = room.harness.inbox.checks;
      final answered = room.turnsAnswered;
      room.sala.conversaTap();
      await settle();
      final stops = room.harness.voice.stops;

      room.sala.conversaTap();
      await waitFor(
        'a sala olhar a caixa de respostas com o turno no ar',
        () => room.harness.inbox.checks > checks,
      );
      await settle();
      room.harness.voice.finishHeldLine();
      await waitFor(
        'a voz responder o turno',
        () => room.turnsAnswered > answered,
      );
      await settle();

      expect(room.harness.voice.stops, stops, reason: 'a voz não foi cortada');
      expect(room.estado.awaitingTheGuide, isFalse, reason: 'o turno terminou');
      expect(room.estado.voice, VoiceState.invite);
      expect(room.offlineNoticeSaid, isFalse);
      _theRoomIsAsItWas(room);
    },
  );

  test('Every non-answer at a hand door is decided as the hand\'s no-change '
      'event, and the machine answers it with the same machine and no '
      'effect.', () {
    const handDoors = [Door.question, Door.inbox, Door.reply];
    final nonAnswers = <RoomResult>[
      const RoomNetworkFailed(),
      const RoomTimedOut(),
      const RoomRefused(RefusalCode.unreadable),
      const RoomRefused('QUESTION_REFUSED'),
      const RoomSessionGone(),
      for (final code in RefusalCode.stopsTheRoom) RoomRefused(code),
    ];
    for (final door in handDoors) {
      for (final rule in RefusalRule.values) {
        for (final result in nonAnswers) {
          final decided = FailurePolicy.decide(
            result,
            FailureContext(
              station: Station.stored(SalaStage.conversa),
              generation: 4,
              door: door,
              rule: rule,
              refusals: 2,
            ),
          );
          expect(
            decided,
            isA<TheHandFailed>().having((e) => e.generation, 'generation', 4),
            reason: '$result em $door ($rule)',
          );
        }
      }
    }

    for (final door in handDoors) {
      expect(
        FailurePolicy.decide(
          const RoomAnswered(),
          FailureContext(
            station: Station.stored(SalaStage.conversa),
            generation: 4,
            door: door,
          ),
        ),
        isA<TheRoomAnswered>(),
        reason: 'uma resposta em $door continua uma resposta',
      );
    }

    for (var seed = 0; seed < 50; seed++) {
      final random = Random(seed);
      var machine = const Machine();
      var world = const World();
      for (var step = 0; step < 40; step++) {
        final (after, effects) = reduce(
          machine,
          TheHandFailed(generation: machine.generation),
        );
        expect(
          identical(after, machine) && effects.isEmpty,
          isTrue,
          reason:
              'seed $seed, step $step: ${describeMachine(machine)} -> '
              '${describeMachine(after)} | '
              '${effects.map(describeEffect).join(', ')}',
        );
        final event = drawAnEvent(world, random);
        final (next, drawn) = reduce(machine, event);
        world = world.after(event, drawn);
        machine = next;
      }
    }
  });
}
