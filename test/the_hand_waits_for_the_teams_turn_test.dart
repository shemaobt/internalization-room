import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/capture_guard.dart';
import 'package:internalization_room/features/sala/domain/hand_reply.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/domain/station.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/presentation/widgets/circle_glyph.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/features/sala/presentation/widgets/hand_button.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart';
import 'the_circle_glyphs_are_hers_test.dart' show paintedGlyph;

const _raise = 'Deixar uma pergunta para o facilitador';
const _hearTheAnswer = 'Ouvir a resposta do facilitador';
const _tapToSpeak = 'Toque para falar';
const _reply = HandReply(id: 'r1', audioUrl: '/resposta/r1');
const _panorama = Passagem(
  pericope: 'panorama',
  audioUrl: '/voice/panorama',
  kind: PassagemKind.panorama,
);

bool _reachableBy(Element hand, bool Function(Widget) stops) {
  var reached = false;
  void visit(Element element) {
    final widget = element.widget;
    if (stops(widget)) return;
    if (widget is Semantics && (widget.properties.button ?? false)) {
      reached = true;
    }
    element.visitChildren(visit);
  }

  hand.visitChildElements(visit);
  return reached;
}

bool _reachable(Element hand) =>
    _reachableBy(
      hand,
      (widget) => widget is IgnorePointer && widget.ignoring,
    ) ||
    _reachableBy(
      hand,
      (widget) => widget is ExcludeSemantics && widget.excluding,
    );

final _hand = find.byElementPredicate(
  (element) => element.widget is HandButton && _reachable(element),
);

final _handInTheCircle = find.descendant(
  of: find.byType(FacilitatorCircle),
  matching: paintedGlyph(CircleGlyph.hand),
);

class _Room {
  final WidgetTester tester;
  final SalaHarness harness;
  final ProviderContainer container;

  _Room(this.tester, this.harness, this.container);

  SalaSessionNotifier get sala => container.read(salaSessionProvider.notifier);

  SalaSessionState get estado => container.read(salaSessionProvider);

  Future<void> beat([int ms = 100]) => tester.pump(Duration(milliseconds: ms));

  Future<void> until(String what, bool Function() ready) async {
    await waitFor(what, ready, step: beat);
    await beat();
  }

  String? get handLabel => tester
      .widgetList<Semantics>(
        find.descendant(of: _hand, matching: find.byType(Semantics)),
      )
      .map((semantics) => semantics.properties.label)
      .firstWhere((label) => label != null, orElse: () => null);

  List<Type> get lookOfTheHand => find
      .descendant(of: _hand, matching: find.byWidgetPredicate((_) => true))
      .evaluate()
      .map((element) => element.widget.runtimeType)
      .toList();

  List<Type> get lookOfTheRoom => find
      .byWidgetPredicate((_) => true)
      .evaluate()
      .map((element) => element.widget.runtimeType)
      .toList();

  Future<void> aTapOnTheHiddenHandPlaysNothing() async {
    sala.handTap();
    await beat(300);
    expect(harness.voice.played, isNot(contains(_reply.audioUrl)));
  }

  Future<void> theReplyStillWaitsOnTheHand() async {
    await beat(300);
    expect(harness.voice.played, isNot(contains(_reply.audioUrl)));
    expect(handLabel, _hearTheAnswer);
  }

  Future<void> theNextCircleTapIsATurnNotAKnot() async {
    await theTeamSendsATurn();
    expect(harness.inbox.questionsSent, isEmpty);
  }

  Future<void> theVoiceSpeaksAfterATurn() async {
    harness.room.holdNextTurn();
    await theTeamSendsATurn();
    harness.voice.holdNextLine();
    harness.room.finishHeldTurn();
    await until('a voz falar', () => estado.voice == VoiceState.speaking);
  }

  Future<void> theTeamSendsATurn() async {
    final before = harness.room.turnsSent;
    sala.conversaTap();
    await until(
      'o microfone abrir',
      () => estado.voice == VoiceState.listening,
    );
    sala.conversaTap();
    await until('a vez sair', () => harness.room.turnsSent > before);
  }

  void tapsTheCircle() => estado.stage == SalaStage.panorama
      ? sala.panoramaTap()
      : sala.conversaTap();

  Future<void> raisesAKnot() async {
    final before = harness.inbox.questionsSent.length;
    sala.handTap();
    await beat();
    tapsTheCircle();
    await until(
      'a pergunta abrir o microfone',
      () => estado.voice == VoiceState.listening,
    );
    tapsTheCircle();
    await until(
      'a pergunta chegar',
      () => harness.inbox.questionsSent.length > before,
    );
  }

  Future<void> atTheInvite() => until(
    'a sala voltar ao convite',
    () => estado.voice == VoiceState.invite,
  );
}

Future<_Room> _inConversaWithAReply(
  WidgetTester tester, {
  bool watching = false,
}) async {
  final room = await _inConversa(
    tester,
    SalaHarness(replies: const [_reply], watchesWithoutAHalt: watching),
  );
  await room.until('a resposta chegar', () => room.estado.hasUnheardReply);
  return room;
}

Future<_Room> _inConversa(WidgetTester tester, [SalaHarness? given]) async {
  final harness = given ?? SalaHarness();
  final container = await pumpSala(tester, harness);
  addTearDown(() => closeTheRoom(container));
  final room = _Room(tester, harness, container);
  unawaited(room.sala.goConversa(book: 'Ruth'));
  await room.until(
    'a conversa abrir no convite',
    () =>
        room.estado.sessionId != null &&
        room.estado.stage == SalaStage.conversa &&
        room.estado.voice == VoiceState.invite,
  );
  await room.beat(300);
  return room;
}

Future<_Room> _inThePanorama(
  WidgetTester tester, {
  bool heldOnItsLine = false,
}) async {
  final harness = SalaHarness();
  harness.room.passages = [_panorama, ...harness.room.passages];
  final container = await pumpSala(tester, harness);
  addTearDown(() => closeTheRoom(container));
  final room = _Room(tester, harness, container);
  if (heldOnItsLine) harness.voice.holdNextFetch();
  await enterThePanorama(room.sala, () => room.estado, step: room.beat);
  if (heldOnItsLine) {
    harness.voice.holdNextLine();
    harness.voice.finishHeldFetch();
    await room.until(
      'o panorama falar',
      () => room.estado.voice == VoiceState.speaking,
    );
  } else {
    await room.until('o panorama ser dito', () => room.estado.panoramaSaid);
    await room.atTheInvite();
    await room.beat(300);
  }
  return room;
}

void main() {
  testWidgets(
    'While the voice speaks the hand is not drawn and a tap where it was does '
    'nothing',
    (tester) async {
      final room = await _inConversa(tester);
      await room.theVoiceSpeaksAfterATurn();
      await room.beat();

      expect(_hand, findsNothing);

      room.sala.handTap();
      await room.beat();

      expect(room.estado.voice, VoiceState.speaking, reason: 'ela segue');
      room.harness.voice.finishHeldLine();
      await room.atTheInvite();
      await room.theNextCircleTapIsATurnNotAKnot();
    },
  );

  testWidgets(
    'While the microphone is open for the team\'s turn the hand is hidden and '
    'the next tap on the circle closes the turn, never starts a Knot',
    (tester) async {
      final room = await _inConversa(tester);
      final turns = room.harness.room.turnsSent;
      room.sala.conversaTap();
      await room.until(
        'o microfone abrir',
        () => room.estado.voice == VoiceState.listening,
      );

      expect(_hand, findsNothing);

      room.sala.handTap();
      await room.beat();
      room.sala.conversaTap();
      await room.until(
        'a vez ir ao Guia',
        () => room.harness.room.turnsSent > turns,
      );
      await room.beat(300);

      expect(room.harness.inbox.questionsSent, isEmpty);
    },
  );

  testWidgets('While the voice is thinking after a turn the hand is hidden', (
    tester,
  ) async {
    final room = await _inConversaWithAReply(tester);
    room.harness.room.holdNextTurn();
    await room.theTeamSendsATurn();
    await room.until(
      'a voz pensar',
      () => room.estado.voice == VoiceState.thinking,
    );

    expect(_hand, findsNothing);

    await room.aTapOnTheHiddenHandPlaysNothing();
    room.harness.room.finishHeldTurn();
    await room.atTheInvite();
    await room.theReplyStillWaitsOnTheHand();
    await room.theNextCircleTapIsATurnNotAKnot();
  });

  testWidgets('While a take is still being sent the hand is hidden', (
    tester,
  ) async {
    final room = await _inConversaWithAReply(tester);
    room.harness.room.holdNextTurn();
    await room.theTeamSendsATurn();
    await room.beat();

    expect(_hand, findsNothing);

    await room.aTapOnTheHiddenHandPlaysNothing();
    room.harness.room.finishHeldTurn();
    await room.atTheInvite();
    await room.theReplyStillWaitsOnTheHand();
    await room.theNextCircleTapIsATurnNotAKnot();
  });

  testWidgets('While the needs-a-person screen is up the hand is hidden', (
    tester,
  ) async {
    final room = await _inConversaWithAReply(tester);
    room.sala.haltForABrokenBuild();
    await room.until('a sala chamar alguém', () => room.estado.needsPerson);

    expect(_hand, findsNothing);

    await room.aTapOnTheHiddenHandPlaysNothing();
    room.sala.teamTapped();
    await room.until('a parada sair', () => !room.estado.needsPerson);
    await room.atTheInvite();
    await room.theReplyStillWaitsOnTheHand();
    await room.theNextCircleTapIsATurnNotAKnot();
    closeTheRoom(room.container);
  });

  testWidgets('At the invite a Knot is sent and the room says nothing', (
    tester,
  ) async {
    final room = await _inConversa(tester);
    final look = room.lookOfTheHand;
    await room.beat(1500);
    final roomBefore = room.lookOfTheRoom;
    room.sala.handTap();
    await room.beat();
    room.sala.conversaTap();
    await room.until(
      'a pergunta abrir o microfone',
      () => room.estado.voice == VoiceState.listening,
    );
    room.harness.inbox.holdNextQuestion();
    room.sala.conversaTap();

    void nothingIsSaid() {
      expect(room.estado.voice, VoiceState.invite, reason: 'nada pensa');
      expect(byLabel(_tapToSpeak), findsOneWidget, reason: 'o círculo espera');
      expect(room.lookOfTheRoom, roomBefore, reason: 'nenhuma marca');
      expect(room.lookOfTheHand, look, reason: 'nenhum ponto na mão');
      expect(room.handLabel, _raise, reason: 'nada escrito na mão');
      expect(_handInTheCircle, findsNothing, reason: 'a mão saiu do círculo');
    }

    await room.until(
      'o microfone fechar',
      () => room.estado.voice != VoiceState.listening,
    );
    await room.beat(1400);
    nothingIsSaid();
    room.harness.inbox.finishHeldQuestion();
    await room.until(
      'a pergunta chegar',
      () => room.harness.inbox.questionsSent.isNotEmpty,
    );
    for (var beat = 0; beat < 40; beat++) {
      await room.beat();
      nothingIsSaid();
    }
  });

  testWidgets('After a Knot is sent the hand looks exactly as it did before', (
    tester,
  ) async {
    final room = await _inConversa(tester);
    final label = room.handLabel;
    final look = room.lookOfTheHand;

    await room.raisesAKnot();
    await room.beat(500);

    expect(room.handLabel, label);
    expect(room.lookOfTheHand, look);
  });

  testWidgets(
    'A stray double tap that records almost nothing reaches nobody and shows '
    'nothing',
    (tester) async {
      final room = await _inConversa(
        tester,
        SalaHarness(captureGuard: const CaptureGuard()),
      );
      final look = room.lookOfTheHand;
      await room.beat(1500);
      final roomBefore = room.lookOfTheRoom;
      room.sala.handTap();
      await room.beat();
      room.sala.conversaTap();
      await room.until(
        'a pergunta abrir o microfone',
        () => room.estado.voice == VoiceState.listening,
      );
      await room.beat(800);
      room.sala.conversaTap();
      await room.until(
        'o microfone fechar',
        () => room.harness.recorder.lastPath != null,
      );
      await room.beat(1500);

      expect(room.harness.inbox.questionsSent, isEmpty);
      expect(room.harness.recorder.deleted, [room.harness.recorder.lastPath]);
      expect(room.lookOfTheRoom, roomBefore);
      expect(room.lookOfTheHand, look);
      expect(room.handLabel, _raise);
    },
  );

  testWidgets(
    'A Knot that reaches the facilitator after the team has left the passage '
    'leaves no recording behind',
    (tester) async {
      final room = await _inConversa(tester);
      room.sala.handTap();
      await room.beat();
      room.sala.conversaTap();
      await room.until(
        'a pergunta abrir o microfone',
        () => room.estado.voice == VoiceState.listening,
      );
      room.harness.inbox.holdNextQuestion();
      room.sala.conversaTap();
      await room.until(
        'o microfone fechar',
        () => room.harness.recorder.lastPath != null,
      );
      final knot = room.harness.recorder.lastPath;

      room.sala.leaveThePassage();
      await room.beat(300);
      room.harness.inbox.finishHeldQuestion();
      await room.until(
        'a pergunta chegar',
        () => room.harness.inbox.questionsSent.isNotEmpty,
      );
      await room.beat(300);

      expect(room.harness.recorder.deleted, contains(knot));
      closeTheRoom(room.container);
    },
  );

  testWidgets(
    'A Knot that reaches the facilitator after the room has closed leaves no '
    'recording behind',
    (tester) async {
      final room = await _inConversa(tester);
      room.sala.handTap();
      await room.beat();
      room.sala.conversaTap();
      await room.until(
        'a pergunta abrir o microfone',
        () => room.estado.voice == VoiceState.listening,
      );
      room.harness.inbox.holdNextQuestion();
      room.sala.conversaTap();
      await room.until(
        'o microfone fechar',
        () => room.harness.recorder.lastPath != null,
      );
      final knot = room.harness.recorder.lastPath;

      closeTheRoom(room.container);
      room.harness.inbox.finishHeldQuestion();
      await room.beat(300);

      expect(room.harness.inbox.questionsSent, isNotEmpty);
      expect(room.harness.recorder.deleted, contains(knot));
    },
  );

  testWidgets(
    'After every element of the passage has been worked with the hand is '
    'shown and a Knot can be sent',
    (tester) async {
      final room = await _inConversa(
        tester,
        SalaHarness(watchesWithoutAHalt: true),
      );
      room.harness.room.readsDone = true;
      await room.until('a passagem acabar', () => room.estado.endOfThePassage);
      await room.until(
        'a voz dizer que acabou',
        () => room.estado.voice == VoiceState.done,
      );

      expect(_hand, findsOneWidget);

      await room.raisesAKnot();

      expect(room.harness.inbox.questionsSent, hasLength(1));
      closeTheRoom(room.container);
    },
  );

  testWidgets(
    'In a Panorama session at the team\'s idle turn the hand is shown and a '
    'Knot can be sent',
    (tester) async {
      final room = await _inThePanorama(tester);

      expect(_hand, findsOneWidget);

      await room.raisesAKnot();

      expect(room.harness.inbox.questionsSent, hasLength(1));
    },
  );

  testWidgets(
    'In a Panorama session while the voice speaks the hand is hidden',
    (tester) async {
      final room = await _inThePanorama(tester, heldOnItsLine: true);
      await room.beat();

      expect(_hand, findsNothing);
      room.harness.voice.finishHeldLine();
    },
  );

  testWidgets('An unheard reply waits for the team\'s idle turn', (
    tester,
  ) async {
    final room = await _inConversa(
      tester,
      SalaHarness(replies: const [_reply]),
    );
    await room.until('a resposta chegar', () => room.estado.hasUnheardReply);
    await room.theVoiceSpeaksAfterATurn();
    await room.beat();

    expect(_hand, findsNothing);

    room.sala.handTap();
    await room.beat();

    expect(room.harness.voice.played, isNot(contains(_reply.audioUrl)));

    room.harness.voice.finishHeldLine();
    await room.atTheInvite();
    await room.beat(300);

    expect(room.handLabel, _hearTheAnswer);

    room.sala.handTap();
    await room.until(
      'a resposta tocar',
      () => room.harness.voice.played.contains(_reply.audioUrl),
    );
  });

  testWidgets(
    'While a reply plays that the desk no longer lists as unheard the hand is '
    'named for a question, not for the reply',
    (tester) async {
      final room = await _inConversaWithAReply(tester);
      room.harness.voice.holdNextLine();
      room.sala.handTap();
      await room.until(
        'a resposta tocar',
        () => room.estado.playingReplyId != null,
      );
      room.harness.inbox.replies = const [];
      room.sala.lookForReplies();
      await room.until('a lista esvaziar', () => !room.estado.hasUnheardReply);

      expect(room.estado.playingReplyId, isNotNull);
      expect(room.handLabel, _raise);
      room.harness.voice.finishHeldLine();
    },
  );

  testWidgets(
    'A tap on the hand while a sent question is still going out arms nothing',
    (tester) async {
      final room = await _inConversa(tester);
      room.harness.inbox.holdNextQuestion();
      room.sala.handTap();
      await room.beat(300);
      room.sala.conversaTap();
      await room.until(
        'o microfone abrir',
        () => room.estado.voice == VoiceState.listening,
      );
      await room.beat(2000);
      room.sala.conversaTap();
      await room.beat(300);

      room.sala.handTap();
      await room.beat(300);

      expect(room.estado.noteMode, isFalse);
      room.harness.inbox.finishHeldQuestion();
      await room.beat(300);
      expect(room.harness.inbox.questionsSent, hasLength(1));
    },
  );

  testWidgets('While a reply plays the hand stays drawn', (tester) async {
    final room = await _inConversa(
      tester,
      SalaHarness(replies: const [_reply]),
    );
    await room.until('a resposta chegar', () => room.estado.hasUnheardReply);
    room.harness.voice.holdNextLine();
    room.sala.handTap();
    await room.until(
      'a resposta tocar',
      () => room.estado.playingReplyId != null,
    );
    await room.beat();

    expect(_hand, findsOneWidget);
    room.harness.voice.finishHeldLine();
  });

  testWidgets(
    'A Watch read that falls on the network leaves the reply waiting on the '
    'hand',
    (tester) async {
      final room = await _inConversaWithAReply(tester, watching: true);
      room.harness.room.failStateOnceWith = const NetworkFailed('sem rede');
      await room.until(
        'a leitura da vigia cair',
        () => room.harness.room.failStateOnceWith == null,
      );
      await room.beat(300);

      expect(_hand, findsOneWidget);

      await room.atTheInvite();
      await room.theReplyStillWaitsOnTheHand();
      closeTheRoom(room.container);
    },
  );

  testWidgets(
    'While a line of the room\'s own plays at the invite the hand is hidden',
    (tester) async {
      final room = await _inConversaWithAReply(tester);
      room.harness.voice.holdNextLine();
      unawaited(room.sala.hearAgain());
      await room.until(
        'a linha tocar',
        () => room.estado.channel is GuideSpeaking,
      );

      expect(_hand, findsNothing);

      await room.aTapOnTheHiddenHandPlaysNothing();
      room.harness.voice.finishHeldLine();
      await room.atTheInvite();
      await room.theReplyStillWaitsOnTheHand();
      await room.theNextCircleTapIsATurnNotAKnot();
    },
  );

  testWidgets(
    'A tap on the hear-again button is not possible while a Knot is armed: the '
    'voice stays quiet and the Knot stays armed',
    (tester) async {
      final room = await _inConversa(tester);
      room.sala.handTap();
      await room.beat();
      final played = [...room.harness.voice.played];

      unawaited(room.sala.hearAgain());
      await room.beat(600);

      expect(room.estado.voice, VoiceState.invite);
      expect(room.harness.voice.played, played);
      expect(_handInTheCircle, findsOneWidget);
    },
  );

  testWidgets(
    'An armed Knot is abandoned when the room calls for a person, and after '
    'the halt the circle opens the team\'s turn',
    (tester) async {
      final room = await _inConversa(tester);
      room.sala.handTap();
      await room.beat();

      room.sala.haltForABrokenBuild();
      await room.until('a sala chamar alguém', () => room.estado.needsPerson);
      room.sala.teamTapped();
      await room.until('a parada sair', () => !room.estado.needsPerson);
      await room.atTheInvite();

      expect(room.handLabel, _raise);
      await room.beat(1000);
      expect(_handInTheCircle, findsNothing);
      await room.theNextCircleTapIsATurnNotAKnot();
      closeTheRoom(room.container);
    },
  );

  testWidgets('A Knot stopped before the guard\'s window is sent even when the '
      'recorder is slow to stop: a question is held to no time floor', (
    tester,
  ) async {
    final room = await _inConversa(
      tester,
      SalaHarness(captureGuard: const CaptureGuard(minBytes: 1)),
    );
    room.sala.handTap();
    await room.beat();
    room.sala.conversaTap();
    await room.until(
      'a pergunta abrir o microfone',
      () => room.estado.voice == VoiceState.listening,
    );
    await room.beat(450);
    room.harness.recorder.holdNextStop();
    room.sala.conversaTap();
    await room.beat(300);
    room.harness.recorder.finishStop();
    await room.until(
      'a pergunta chegar à mesa',
      () => room.harness.inbox.questionsSent.isNotEmpty,
    );

    expect(
      room.harness.inbox.questionsSent,
      ['sessao-1'],
      reason:
          'uma pergunta parada antes dos 0,7 s era apagada; a dela só cai '
          'abaixo de 800 bytes',
    );
    expect(room.harness.recorder.deleted, [room.harness.recorder.lastPath]);
  });

  testWidgets(
    'a Panorama the room could not open leaves the team on the Choice, with no '
    'hand',
    (tester) async {
      final harness = SalaHarness();
      harness.room.passages = [_panorama, ...harness.room.passages];
      final container = await pumpSala(tester, harness);
      addTearDown(() => closeTheRoom(container));
      final room = _Room(tester, harness, container);
      harness.room.failCreateOnceWith = const Refused('BAD_REQUEST');
      await enterThePanorama(room.sala, () => room.estado, step: room.beat);
      await room.beat(300);

      expect(room.estado.needsPerson, isFalse);

      expect(room.estado.stage, SalaStage.escolha);
      expect(_hand, findsNothing);
      closeTheRoom(container);
    },
  );

  test('A Conversation with no session to send to is not the team\'s idle '
      'turn', () {
    const atTheInvite = SalaSessionState(machine: Machine(station: Canvas()));

    expect(atTheInvite.voice, VoiceState.invite);
    expect(atTheInvite.atTheTeamsIdleTurn, isFalse);
    expect(
      atTheInvite
          .copyWith(machine: atTheInvite.machine.copyWith(session: 'sessao-1'))
          .atTheTeamsIdleTurn,
      isTrue,
    );
  });
}
