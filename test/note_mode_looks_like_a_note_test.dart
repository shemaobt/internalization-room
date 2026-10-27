import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/presentation/widgets/bead_styles.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/hand_reply.dart';
import 'package:internalization_room/features/sala/domain/moment.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/features/sala/presentation/widgets/hand_button.dart';
import 'package:internalization_room/features/sala/presentation/widgets/moment_label.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart';

const _reply = HandReply(id: 'r1', audioUrl: '/resposta/r1');
const _panorama = Passagem(
  pericope: 'panorama',
  audioUrl: '/voice/panorama',
  kind: PassagemKind.panorama,
);

class _Room {
  final WidgetTester tester;
  final SalaHarness harness;
  final ProviderContainer container;
  final String language;

  _Room(this.tester, this.harness, this.container, this.language);

  SalaSessionNotifier get sala => container.read(salaSessionProvider.notifier);

  SalaSessionState get estado => container.read(salaSessionProvider);

  Future<void> beat([int ms = 100]) => tester.pump(Duration(milliseconds: ms));

  Future<void> until(String what, bool Function() ready) async {
    await waitFor(what, ready, step: beat);
    await beat();
  }

  Finder get _hand => find.byType(HandButton);

  Finder get _circle => find.byType(FacilitatorCircle);

  String? _labelWithin(Finder of) => tester
      .widgetList<Semantics>(
        find.descendant(of: of, matching: find.byType(Semantics)),
      )
      .map((semantics) => semantics.properties.label)
      .firstWhere((label) => label != null, orElse: () => null);

  String? get handLabel => _labelWithin(_hand);

  bool get circleHoldsTheHand => find
      .descendant(of: _circle, matching: find.byIcon(LucideIcons.hand))
      .evaluate()
      .isNotEmpty;

  bool get circleIsBlueGreen => tester
      .widgetList<Container>(
        find.descendant(of: _circle, matching: find.byType(Container)),
      )
      .map((box) => box.decoration)
      .whereType<BoxDecoration>()
      .any((paint) => paint.gradient == BeadStyles.azul);

  bool isSeen(Finder what) {
    if (what.evaluate().isEmpty) return false;
    final fades = tester.widgetList<AnimatedOpacity>(
      find.ancestor(of: what, matching: find.byType(AnimatedOpacity)),
    );
    return fades.every((fade) => fade.opacity > 0);
  }

  Finder _labelled(String label) => byLabel(label);

  bool get hearAgainIsSeen =>
      isSeen(_labelled(roomLabelFor('hearAgain', language)));

  bool get momentLabelIsSeen => isSeen(find.byType(MomentLabel));

  bool get redMicrophoneIsSeen =>
      isSeen(_labelled(sceneRehearsalLabelFor('enter', language)));

  Finder get orangeDot => _labelled(roomLabelFor('recordEnsaio', language));

  bool get orangeDotIsSeen => isSeen(orangeDot);

  Future<void> raisesTheHand() async {
    sala.handTap();
    await beat();
  }

  Future<void> theKnotRecords() async {
    await raisesTheHand();
    sala.conversaTap();
    await until(
      'a pergunta abrir o microfone',
      () => estado.voice == VoiceState.listening,
    );
  }

  Future<void> nothingReachesTheFacilitator() async {
    await beat(600);
    expect(harness.inbox.questionsSent, isEmpty);
    closeTheRoom(container);
  }
}

Future<_Room> _inConversa(
  WidgetTester tester, {
  SalaHarness? given,
  String language = 'pt',
}) async {
  final harness = given ?? SalaHarness(lingua: language);
  final container = await pumpSala(tester, harness);
  addTearDown(() => closeTheRoom(container));
  final room = _Room(tester, harness, container, language);
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

Future<_Room> _atTheEndOfThePassage(WidgetTester tester) async {
  final room = await _inConversa(
    tester,
    given: SalaHarness(watchesWithoutAHalt: true),
  );
  room.harness.room.readsDone = true;
  await room.until('a passagem acabar', () => room.estado.endOfThePassage);
  await room.until(
    'a voz dizer que acabou',
    () => room.estado.voice == VoiceState.done,
  );
  return room;
}

Future<_Room> _inThePanorama(
  WidgetTester tester, {
  String language = 'pt',
}) async {
  final harness = SalaHarness(lingua: language);
  harness.room.passages = [_panorama, ...harness.room.passages];
  final container = await pumpSala(tester, harness);
  addTearDown(() => closeTheRoom(container));
  final room = _Room(tester, harness, container, language);
  await enterThePanorama(room.sala, () => room.estado, step: room.beat);
  await room.until('o panorama ser dito', () => room.estado.panoramaSaid);
  await room.until(
    'a sala voltar ao convite',
    () => room.estado.voice == VoiceState.invite,
  );
  await room.beat(300);
  return room;
}

void main() {
  testWidgets(
    'In a passage session a tap on the hand turns the circle blue-green with '
    'the hand inside, and the hear-again button, the moment label and the red '
    'microphone are not on screen',
    (tester) async {
      final room = await _inConversa(
        tester,
        given: SalaHarness()
          ..room.nextMoment = const Moment(
            at: MomentAt.familiarization,
            parts: 3,
          ),
      );
      await room.until(
        'a sala ter um momento',
        () => room.estado.moment != null,
      );
      expect(
        room.hearAgainIsSeen,
        isTrue,
        reason: 'o caso precisa começar com ela',
      );
      expect(room.momentLabelIsSeen, isTrue);
      expect(room.redMicrophoneIsSeen, isTrue);
      expect(room.circleIsBlueGreen, isFalse);

      await room.raisesTheHand();
      await room.beat(1000);

      expect(room.circleIsBlueGreen, isTrue);
      expect(room.circleHoldsTheHand, isTrue);
      expect(room.hearAgainIsSeen, isFalse);
      expect(room.momentLabelIsSeen, isFalse);
      expect(room.redMicrophoneIsSeen, isFalse);
    },
  );

  testWidgets('In the Panorama a tap on the hand gives the circle the same '
      'note look', (tester) async {
    final room = await _inThePanorama(tester);
    expect(room.circleIsBlueGreen, isFalse);
    expect(room.circleHoldsTheHand, isFalse);

    await room.raisesTheHand();
    await room.beat(1000);

    expect(room.circleIsBlueGreen, isTrue);
    expect(room.circleHoldsTheHand, isTrue);
  });

  testWidgets('In note mode the orange dot stays on screen, and tapping it '
      'abandons the question: nothing reaches the facilitator', (tester) async {
    final room = await _atTheEndOfThePassage(tester);
    expect(room.orangeDotIsSeen, isTrue, reason: 'o caso começa com o ponto');
    await room.raisesTheHand();
    await room.beat(1000);

    expect(room.orangeDotIsSeen, isTrue);

    await tester.tap(room.orangeDot);
    await room.until(
      'o ensaio abrir',
      () => room.estado.stage == SalaStage.ensaio,
    );

    await room.nothingReachesTheFacilitator();
  });

  testWidgets('While the question records, tapping the orange dot discards it: '
      'nothing reaches the facilitator', (tester) async {
    final room = await _atTheEndOfThePassage(tester);
    expect(room.orangeDotIsSeen, isTrue, reason: 'o caso começa com o ponto');
    await room.theKnotRecords();
    await room.beat(1000);

    expect(room.orangeDotIsSeen, isTrue);

    await tester.tap(room.orangeDot);
    await room.until(
      'o ensaio abrir',
      () => room.estado.stage == SalaStage.ensaio,
    );

    await room.nothingReachesTheFacilitator();
  });

  testWidgets('While the question records the hand stays drawn at its note '
      'look, not hidden as at the team\'s turn', (tester) async {
    final room = await _inConversa(tester);
    await room.theKnotRecords();
    await room.beat(300);

    expect(
      room._hand,
      findsOneWidget,
      reason: 'a mão sumia enquanto a pergunta gravava',
    );
    expect(
      tester.widget<HandButton>(room._hand).noteMode,
      isTrue,
      reason: 'a mão voltava ao ar apagado do convite',
    );
  });

  testWidgets('While the question records a tap on the hand throws it away: '
      'the microphone closes, nothing reaches the facilitator and nothing is '
      'said', (tester) async {
    final room = await _inConversa(tester);
    await room.theKnotRecords();
    await room.beat(300);
    final said = [...room.harness.voice.played];
    final lines = [...room.harness.voice.fixedLines];

    await tester.tap(room._hand);
    await room.until(
      'o microfone fechar',
      () => room.estado.voice == VoiceState.invite,
    );
    await room.beat(600);

    expect(
      room.harness.recorder.deleted,
      [room.harness.recorder.lastPath],
      reason: 'a pergunta pela metade ficava no aparelho',
    );
    expect(room.estado.noteMode, isFalse, reason: 'a mão seguia armada');
    expect(
      room.harness.inbox.questionsSent,
      isEmpty,
      reason: 'meia pergunta chegava ao facilitador',
    );
    expect(room.harness.voice.played, said);
    expect(room.harness.voice.fixedLines, lines);
    closeTheRoom(room.container);
  });

  testWidgets('In note mode tapping the menu abandons the question: nothing '
      'reaches the facilitator', (tester) async {
    final room = await _inConversa(tester);
    await room.raisesTheHand();

    await tester.tap(byLabel(roomLabelFor('leavePassage', 'pt')));
    await room.until(
      'a sala sair da passagem',
      () => room.estado.stage != SalaStage.conversa,
    );

    await room.nothingReachesTheFacilitator();
  });

  testWidgets('Leaving note mode brings back the hear-again button', (
    tester,
  ) async {
    final room = await _inConversa(tester);
    expect(
      room.hearAgainIsSeen,
      isTrue,
      reason: 'o caso precisa começar com ela',
    );
    await room.raisesTheHand();
    await room.beat(1000);
    expect(room.hearAgainIsSeen, isFalse);

    await room.raisesTheHand();
    await room.beat(1000);

    expect(room.hearAgainIsSeen, isTrue);
  });

  testWidgets('The hand reads «Deixar uma pergunta para o facilitador» at the '
      'idle turn, and still does while a question is armed', (tester) async {
    final room = await _inConversa(tester);

    expect(room.handLabel, 'Deixar uma pergunta para o facilitador');

    await room.raisesTheHand();

    expect(room.handLabel, 'Deixar uma pergunta para o facilitador');
  });

  testWidgets('With a reply waiting the hand reads «Ouvir a resposta do '
      'facilitador»', (tester) async {
    final room = await _inConversa(
      tester,
      given: SalaHarness(replies: const [_reply]),
    );
    await room.until('a resposta chegar', () => room.estado.hasUnheardReply);

    expect(room.handLabel, 'Ouvir a resposta do facilitador');
  });

  testWidgets('In an English session the hand reads "Leave a question for the '
      'facilitator"', (tester) async {
    final room = await _inConversa(tester, language: 'en');

    expect(room.handLabel, 'Leave a question for the facilitator');
  });

  testWidgets('In an English session with a reply waiting the hand reads "Hear '
      'the facilitator\'s answer"', (tester) async {
    final room = await _inConversa(
      tester,
      given: SalaHarness(lingua: 'en', replies: const [_reply]),
      language: 'en',
    );
    await room.until('a resposta chegar', () => room.estado.hasUnheardReply);

    expect(room.handLabel, 'Hear the facilitator\'s answer');
  });

  for (final (language, words) in [
    ('pt', 'Tocar ao terminar'),
    ('en', 'Tap when you are done'),
  ]) {
    testWidgets('While the question records the circle reads «$words» '
        '($language)', (tester) async {
      final room = await _inConversa(tester, language: language);
      await room.theKnotRecords();

      expect(byLabel(words), findsOneWidget);
    });
  }

  for (final (language, words) in [
    ('pt', 'Tocar para falar'),
    ('en', 'Tap to speak'),
  ]) {
    testWidgets('The Panorama\'s resting circle reads «$words» ($language), '
        'never a word for the facilitator', (tester) async {
      await _inThePanorama(tester, language: language);

      expect(byLabel(words), findsOneWidget);
    });
  }
}
