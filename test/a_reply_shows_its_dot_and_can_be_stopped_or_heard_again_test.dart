import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/hand_reply.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/hand_button.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;

const _reply = HandReply(id: 'r1', audioUrl: '/resposta/r1');
const _terracotta = Color(0xFFBE4A01);
const _dotSize = 13.0;

final _aDotOnTheHand = find.descendant(
  of: find.byType(HandButton),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is DecoratedBox &&
        widget.decoration is BoxDecoration &&
        (widget.decoration as BoxDecoration).shape == BoxShape.circle,
  ),
);

final _dot = find.descendant(
  of: find.byType(HandButton),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is DecoratedBox &&
        widget.decoration is BoxDecoration &&
        (widget.decoration as BoxDecoration).color == _terracotta,
  ),
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

  Future<void> waits(Duration span) async {
    for (var gone = Duration.zero; gone < span; gone += _step) {
      await tester.pump(_step);
    }
  }

  static const _step = Duration(milliseconds: 500);

  int get timesTheReplyPlayed =>
      harness.voice.played.where((url) => url == _reply.audioUrl).length;

  bool get theDotShows => _aDotOnTheHand.evaluate().any(
    (dot) => tester.getRect(find.byWidget(dot.widget)).width < 20,
  );

  void theFacilitatorReplies() => harness.inbox.replies = const [_reply];

  Future<void> atTheInvite() => until(
    'a sala voltar ao convite',
    () => estado.voice == VoiceState.invite,
  );

  Future<void> theTeamSendsATurn() async {
    final before = harness.room.turnsSent;
    sala.conversaTap();
    await until(
      'o microfone abrir',
      () => estado.voice == VoiceState.listening,
    );
    sala.conversaTap();
    await until('a vez sair', () => harness.room.turnsSent > before);
    await atTheInvite();
  }

  Future<void> theReplyIsPlaying() async {
    harness.voice.holdNextLine();
    final before = timesTheReplyPlayed;
    sala.handTap();
    await until('a resposta tocar', () => timesTheReplyPlayed > before);
  }

  Future<void> theReplyStaysUnheard() async {
    expect(harness.inbox.heard, isEmpty, reason: 'a mesa não ouviu marca');
    await atTheInvite();
    await beat(300);
    expect(theDotShows, isTrue, reason: 'o ponto segue na mão');
  }
}

Future<_Room> _atTheInvite(WidgetTester tester, [SalaHarness? given]) async {
  final harness = given ?? SalaHarness();
  final container = await pumpSala(tester, harness);
  addTearDown(() => closeTheRoom(container));
  final room = _Room(tester, harness, container);
  unawaited(room.sala.goConversa());
  await room.until(
    'a conversa abrir no convite',
    () =>
        room.estado.sessionId != null && room.estado.voice == VoiceState.invite,
  );
  await room.beat(300);
  return room;
}

Future<_Room> _withAReplyWaiting(WidgetTester tester) async {
  final room = await _atTheInvite(tester, SalaHarness(replies: const [_reply]));
  await room.until('a resposta chegar', () => room.estado.hasUnheardReply);
  return room;
}

Future<List<double>> _dotWidthsOver(WidgetTester tester, Duration span) async {
  final widths = <double>[];
  for (var gone = Duration.zero; gone <= span; gone += _frame) {
    await tester.pump(_frame);
    widths.add(tester.getRect(_dot).width);
  }
  return widths;
}

const _frame = Duration(milliseconds: 50);

void _turnAway(WidgetTester tester) {
  for (final away in const [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(away);
  }
}

void _comeBack(WidgetTester tester) {
  for (final back in const [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(back);
  }
}

void main() {
  testWidgets(
    'A reply sent while the room rests on the invitation shows its dot within '
    '15 seconds, without a turn',
    (tester) async {
      final room = await _atTheInvite(tester);
      final turns = room.harness.room.turnsSent;
      expect(room.theDotShows, isFalse);

      room.theFacilitatorReplies();
      await room.waits(const Duration(seconds: 15));

      expect(room.theDotShows, isTrue, reason: 'o ponto aparece na mão');
      expect(room.harness.room.turnsSent, turns, reason: 'sem nenhuma vez');
    },
  );

  testWidgets(
    'The room looks for replies again every 15 seconds while it is open in the '
    'foreground',
    (tester) async {
      final room = await _atTheInvite(tester);
      await room.waits(const Duration(seconds: 1));
      final before = room.harness.inbox.checks;

      await room.waits(const Duration(seconds: 45));

      expect(room.harness.inbox.checks, before + 3);
    },
  );

  testWidgets(
    'The room stops looking while the app is in the background, and looks at '
    'once when it returns',
    (tester) async {
      final room = await _atTheInvite(tester);
      await room.waits(const Duration(seconds: 1));
      final before = room.harness.inbox.checks;

      _turnAway(tester);
      await room.waits(const Duration(seconds: 60));
      expect(
        room.harness.inbox.checks,
        before,
        reason: 'na gaveta o tablet não pergunta à mesa',
      );

      room.theFacilitatorReplies();
      _comeBack(tester);
      await room.beat();
      expect(room.harness.inbox.checks, before + 1, reason: 'pergunta já');
      await room.beat(300);
      expect(room.theDotShows, isTrue);
    },
  );

  testWidgets(
    'A reply still shows its dot 30 seconds after a turn, as before',
    (tester) async {
      final room = await _atTheInvite(
        tester,
        SalaHarness(
          settleDelay: const Duration(seconds: 30),
          inboxWatch: const Duration(hours: 1),
        ),
      );
      await room.theTeamSendsATurn();
      room.theFacilitatorReplies();

      await room.waits(const Duration(seconds: 31));

      expect(room.theDotShows, isTrue);
    },
  );

  testWidgets('The dot is terracotta with a white halo, and pulses', (
    tester,
  ) async {
    final room = await _withAReplyWaiting(tester);
    await room.beat(300);

    final dot = tester.widget<DecoratedBox>(_dot);
    final look = dot.decoration as BoxDecoration;
    expect(look.shape, BoxShape.circle);
    expect(look.boxShadow, [
      BoxShadow(
        color: const Color(0xFFFFFFFF).withValues(alpha: 0.9),
        spreadRadius: 3,
      ),
    ]);

    final widths = await _dotWidthsOver(
      tester,
      const Duration(milliseconds: 2400),
    );
    final narrowest = widths.reduce((a, b) => a < b ? a : b);
    final widest = widths.reduce((a, b) => a > b ? a : b);
    expect(
      narrowest,
      closeTo(_dotSize, 0.3),
      reason: 'o ponto volta ao seu tamanho',
    );
    expect(
      widest,
      closeTo(_dotSize * 1.35, 0.3),
      reason: 'e cresce a 1,35 no meio do pulso',
    );
    final halfAPulse =
        _frame * (widths.indexOf(widest) - widths.indexOf(narrowest)).abs();
    expect(
      halfAPulse.inMilliseconds,
      closeTo(1200, 100),
      reason: 'meio pulso de 2,4 s',
    );
  });

  testWidgets('With reduce-motion on, the dot holds still', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final room = await _withAReplyWaiting(tester);
    await room.beat(300);

    final widths = await _dotWidthsOver(
      tester,
      const Duration(milliseconds: 2400),
    );

    expect(widths.toSet(), {_dotSize});
  });

  testWidgets(
    'Tapping the hand plays the reply, and nothing else sounds over it',
    (tester) async {
      final room = await _withAReplyWaiting(tester);

      await room.theReplyIsPlaying();
      final heardSoFar = [...room.harness.sounds];
      await room.waits(const Duration(seconds: 40));

      expect(room.timesTheReplyPlayed, 1);
      expect(
        room.harness.sounds,
        heardSoFar,
        reason: 'nada mais soa nem para enquanto a resposta toca',
      );
    },
  );

  testWidgets(
    'Tapping the circle during a reply stops it, starts the team\'s turn, and '
    'the reply stays unheard with its dot',
    (tester) async {
      final room = await _withAReplyWaiting(tester);
      await room.theReplyIsPlaying();
      final stops = room.harness.voice.stops;

      room.sala.conversaTap();
      await room.until(
        'o microfone abrir',
        () => room.estado.voice == VoiceState.listening,
      );

      expect(room.harness.voice.stops, greaterThan(stops), reason: 'parou');
      final turns = room.harness.room.turnsSent;
      room.sala.conversaTap();
      await room.until('a vez sair', () => room.harness.room.turnsSent > turns);
      await room.theReplyStaysUnheard();
    },
  );

  testWidgets(
    'Tapping the hand again during a reply plays it again from the start, and '
    'only a play to the end marks it heard',
    (tester) async {
      final room = await _withAReplyWaiting(tester);
      await room.theReplyIsPlaying();
      final stops = room.harness.voice.stops;

      await room.theReplyIsPlaying();
      await room.beat(300);
      await room.theReplyIsPlaying();

      expect(room.timesTheReplyPlayed, 3, reason: 'tocou de novo, e de novo');
      expect(room.harness.voice.stops, greaterThan(stops), reason: 'parou');
      expect(room.harness.inbox.heard, isEmpty);

      room.harness.voice.finishHeldLine();
      await room.until(
        'a resposta ser ouvida',
        () => !room.estado.hasUnheardReply,
      );
      await room.beat(300);
      expect(room.harness.inbox.heard, [_reply.id]);
      expect(room.theDotShows, isFalse);
    },
  );

  testWidgets(
    'When the voice starts speaking (hear again included), a playing reply '
    'stops and stays unheard',
    (tester) async {
      final room = await _withAReplyWaiting(tester);
      await room.theTeamSendsATurn();
      final herLine = room.harness.voice.played.last;
      await room.theReplyIsPlaying();
      final stops = room.harness.voice.stops;

      unawaited(room.sala.hearAgain());
      await room.beat(300);

      expect(room.harness.voice.stops, greaterThan(stops), reason: 'parou');
      expect(room.harness.voice.played.last, herLine, reason: 'ela fala');
      await room.theReplyStaysUnheard();
    },
  );

  test(
    'When the voice starts speaking, a playing reply stops and her line takes '
    'the channel',
    () {
      const reply = Line(LineKind.reply, 1, source: Source.reply('r1'));
      for (final kind in LineKind.values.where((k) => k != LineKind.reply)) {
        final hers = Line(kind, 2);

        final (machine, effects) = reduce(
          const Machine(channel: GuideSpeaking(reply)),
          LineArrived(hers),
        );

        expect(machine.channel, GuideSpeaking(hers), reason: '$kind');
        expect(effects, [
          const StopTheLine(reply),
          PlayLine(hers),
        ], reason: '$kind');
      }
    },
  );

  testWidgets(
    'Leaving for the passage choice during a reply stops it, and it stays '
    'unheard',
    (tester) async {
      final room = await _withAReplyWaiting(tester);
      await room.theReplyIsPlaying();
      final stops = room.harness.voice.stops;

      unawaited(room.sala.abrirEscolha());
      await room.until(
        'a Escolha abrir',
        () => room.estado.stage == SalaStage.escolha,
      );

      expect(room.harness.voice.stops, greaterThan(stops), reason: 'parou');
      expect(room.harness.inbox.heard, isEmpty);
      expect(room.estado.oldestUnheardReply?.id, _reply.id);
    },
  );

  testWidgets(
    'A reply is never played by itself and never announced: the dot is the only '
    'sign',
    (tester) async {
      final room = await _atTheInvite(tester);
      final heardSoFar = [...room.harness.sounds];

      room.theFacilitatorReplies();
      await room.waits(const Duration(seconds: 60));

      expect(room.theDotShows, isTrue);
      expect(room.timesTheReplyPlayed, 0);
      expect(room.harness.sounds, heardSoFar, reason: 'nada soou');
    },
  );
}
