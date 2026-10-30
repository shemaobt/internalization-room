import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/hand_reply.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart'
    show byLabel, intoTheRecordingHome, withDiskThatAnswersAtOnce;

const _panorama = Passagem(
  pericope: 'panorama',
  audioUrl: '/voice/panorama',
  kind: PassagemKind.panorama,
);
const _theBook = [
  _panorama,
  Passagem(
    pericope: 'P01',
    audioUrl: '/voice/p01',
    book: 'Ruth',
    reference: 'Ruth 1:1–5',
  ),
  Passagem(
    pericope: 'P02',
    audioUrl: '/voice/p02',
    book: 'Ruth',
    reference: 'Ruth 1:6–14',
  ),
];

const _leave = 'Choose another passage';
const _back = 'Back to the current passage';
const _backToRecording = 'Back to recording';
const _hearTheAnswer = "Hear your facilitator's reply";

class _Room {
  _Room(this.harness, this.container);

  final SalaHarness harness;
  final ProviderContainer container;

  SalaSessionNotifier get notifier =>
      container.read(salaSessionProvider.notifier);

  SalaSessionState get state => container.read(salaSessionProvider);
}

Future<_Room> _pump(
  WidgetTester tester, {
  String lingua = 'en',
  List<HandReply> replies = const [],
  bool memory = false,
  Set<String> cannotOpen = const {},
}) async {
  final harness = SalaHarness(
    lingua: lingua,
    replies: replies,
    filaEmMemoria: memory,
  );
  harness.room.passages = _theBook;
  harness.room.passagesThatCannotOpen = cannotOpen;
  return _Room(harness, await pumpSala(tester, harness));
}

Future<void> _passTime(WidgetTester tester, [int milliseconds = 400]) =>
    tester.pump(Duration(milliseconds: milliseconds));

Future<void> _readTheWheel(WidgetTester tester, _Room room) async {
  await room.notifier.abrirEscolha();
  await _passTime(tester, 300);
}

void _open(_Room room, String pericope) => room.notifier.openTheEntry(
  room.state.naRoda!.firstWhere((entry) => entry.pericope == pericope),
);

Future<void> _takeThePanorama(WidgetTester tester, _Room room) async {
  await _readTheWheel(tester, room);
  room.notifier.openTheEntry(room.state.naRoda!.first);
  await _passTime(tester);
}

Future<void> _takeThePassage(
  WidgetTester tester,
  _Room room,
  String pericope,
) async {
  if (room.state.naRoda == null) await _readTheWheel(tester, room);
  _open(room, pericope);
  await _passTime(tester);
  await _passTime(tester);
}

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.tap(byLabel(label), warnIfMissed: false);
  await _passTime(tester);
}

List<double> _opacities(WidgetTester tester, String label) => [
  for (final veil in tester.widgetList<AnimatedOpacity>(
    find.ancestor(of: byLabel(label), matching: find.byType(AnimatedOpacity)),
  ))
    veil.opacity,
];

bool _ignoring(WidgetTester tester, String label) => tester
    .widgetList<IgnorePointer>(
      find.ancestor(of: byLabel(label), matching: find.byType(IgnorePointer)),
    )
    .any((gate) => gate.ignoring);

bool _hidden(WidgetTester tester, String label) =>
    byLabel(label).evaluate().isNotEmpty &&
    _opacities(tester, label).contains(0.0) &&
    _ignoring(tester, label);

bool _live(WidgetTester tester, String label) =>
    byLabel(label).evaluate().isNotEmpty &&
    !_opacities(tester, label).contains(0.0) &&
    !_ignoring(tester, label);

int _voicedLines(SalaHarness harness) => harness.sounds
    .where(
      (sound) =>
          sound == 'voice:line' ||
          sound == 'voice:asset' ||
          sound == 'voice:fixed',
    )
    .length;

Future<void> _keepAPart(WidgetTester tester, _Room room) async {
  room.notifier.goEnsaio();
  await _passTime(tester, 300);
  await tester.pump(const Duration(seconds: 2));
  room.notifier.gravarACena(1);
  room.notifier.gravarACena(1);
  await _passTime(tester, 300);
  room.notifier.takeKeep();
  await theRoomNamesTheParts(tester, room.container, parts: 1);
}

void main() {
  testWidgets(
    'a kept part is named by the room before the team goes on, not after a clock',
    (tester) => withDiskThatAnswersAtOnce(() async {
      final room = await _pump(tester, memory: true);
      room.harness.room.takeLandsAfter = const Duration(milliseconds: 300);
      await _takeThePassage(tester, room, 'P01');
      await _keepAPart(tester, room);

      expect(
        room.state.partes.single.takeId,
        'gravacao-1',
        reason:
            'a equipe seguia com a parte ainda sem nome, e o que vinha '
            'depois contava com uma gravação que a sala não tinha dado',
      );
      closeTheRoom(room.container);
    }),
  );

  testWidgets(
    'on the Panorama with the voice silent, «Choose another passage» is there '
    'and leads to the Choice, which offers the way back',
    (tester) async {
      final room = await _pump(tester);
      await _takeThePanorama(tester, room);
      await tester.pump(const Duration(seconds: 1));

      expect(room.state.stage, SalaStage.panorama);
      expect(room.state.voice, VoiceState.invite);
      expect(_live(tester, _leave), isTrue);

      await _tap(tester, _leave);
      await tester.pump(const Duration(seconds: 1));

      expect(room.state.stage, SalaStage.escolha);
      expect(byLabel(_back), findsOneWidget);
    },
  );

  testWidgets(
    'the way back returns to the Panorama in silence once its line was said',
    (tester) async {
      final room = await _pump(tester);
      await _takeThePanorama(tester, room);
      await tester.pump(const Duration(seconds: 1));
      await _tap(tester, _leave);
      await tester.pump(const Duration(seconds: 1));
      expect(room.state.voice, VoiceState.invite);
      final asked = room.harness.room.calls.length;
      final voiced = _voicedLines(room.harness);

      await _tap(tester, _back);
      await tester.pump(const Duration(seconds: 1));

      expect(room.state.station, isA<Panorama>());
      expect(room.harness.room.calls.length, asked);
      expect(_voicedLines(room.harness), voiced);

      room.notifier.panoramaTap();
      await _passTime(tester, 300);

      expect(room.state.voice, VoiceState.listening);
    },
  );

  testWidgets(
    'a pending take sounding when the team leaves is dropped with the leave, '
    'and nothing is held on the way back',
    (tester) => withDiskThatAnswersAtOnce(() async {
      final room = await _pump(tester, memory: true);
      await _takeThePassage(tester, room, 'P01');
      await _keepAPart(tester, room);
      room.notifier.gravarACena(2);
      room.notifier.gravarACena(2);
      await _passTime(tester, 300);
      room.notifier.playTheRehearsal();
      await _passTime(tester, 200);
      room.harness.playback.finishPlayback();
      await _passTime(tester, 200);
      expect(room.state.playPing, isTrue);
      room.harness.playback.at = const Duration(seconds: 2);

      room.notifier.leaveThePassage();
      await _passTime(tester);
      await tester.pump(const Duration(seconds: 1));
      await _tap(tester, _back);
      await intoTheRecordingHome(
        room.notifier,
        () => room.state,
        step: () => letTheRehearsalReachTheRoom(tester),
      );

      expect(room.state.stage, SalaStage.ensaio);
      expect(room.state.takePaused, isFalse);
      expect(room.state.needsPerson, isFalse);
      final played = room.harness.playback.played.length;

      room.notifier.playTheRehearsal();
      await _passTime(tester, 200);

      final dropped = room.harness.recorder.deleted;
      expect(dropped, hasLength(1));
      expect(room.harness.playback.played.skip(played), isNotEmpty);
      expect(
        room.harness.playback.played.skip(played),
        everyElement(isNot(dropped.single)),
      );
      expect(room.state.needsPerson, isFalse);
    }),
  );

  testWidgets('«Choose another passage» is hidden while the voice speaks', (
    tester,
  ) async {
    final room = await _pump(tester);
    await _readTheWheel(tester, room);
    room.harness.voice.holdNextLine();
    room.notifier.openTheEntry(room.state.naRoda!.first);
    await _passTime(tester);

    expect(room.state.stage, SalaStage.panorama);
    expect(room.state.voice, VoiceState.speaking);
    expect(_hidden(tester, _leave), isTrue);

    await tester.tap(byLabel(_leave), warnIfMissed: false);
    await _passTime(tester, 300);

    expect(room.state.stage, SalaStage.panorama);

    room.harness.voice.finishHeldLine();
    await _passTime(tester);
  });

  testWidgets(
    '«Back to the current passage» is hidden while the team\'s take is recorded',
    (tester) async {
      final room = await _pump(tester, memory: true);
      await _takeThePassage(tester, room, 'P01');
      room.notifier.goEnsaio();
      await _passTime(tester, 300);
      await tester.pump(const Duration(seconds: 2));
      expect(_live(tester, _back), isTrue);

      room.notifier.gravarACena(1);
      await _passTime(tester, 300);

      expect(room.harness.sounds, contains('recorder:start'));
      expect(_hidden(tester, _back), isTrue);

      await tester.tap(byLabel(_back), warnIfMissed: false);
      await _passTime(tester, 300);

      expect(room.state.stage, SalaStage.ensaio);
      expect(room.harness.recorder.deleted, isEmpty);
    },
  );

  testWidgets('«Back to recording» is hidden while the back-translation\'s '
      'microphone is open', (tester) async {
    final room = await _pump(tester, memory: true);
    await _takeThePassage(tester, room, 'P01');
    await _keepAPart(tester, room);
    room.notifier.startRetro();
    await _passTime(tester, 300);
    room.harness.playback.at = const Duration(seconds: 2);
    room.notifier.retroTap();
    room.notifier.retroTap();
    await _passTime(tester, 300);

    expect(room.state.stage, SalaStage.retro);
    expect(room.state.voice, VoiceState.listening);
    expect(_hidden(tester, _backToRecording), isTrue);
  });

  testWidgets(
    'a raised-hand note being spoken leaves «Choose another passage» in reach, '
    'and a tap throws the note away',
    (tester) async {
      final room = await _pump(tester);
      await _takeThePassage(tester, room, 'P01');
      await tester.pump(const Duration(seconds: 1));
      room.notifier.handTap();
      room.notifier.conversaTap();
      await _passTime(tester, 300);

      expect(room.state.voice, VoiceState.listening);
      expect(room.state.noteMode, isTrue);
      expect(_live(tester, _leave), isTrue);

      await _tap(tester, _leave);

      expect(room.state.stage, SalaStage.escolha);
      expect(room.harness.recorder.deleted, hasLength(1));
      expect(room.harness.inbox.questionsSent, isEmpty);
    },
  );

  testWidgets('«Choose another passage» is ignored while a turn is underway', (
    tester,
  ) async {
    final room = await _pump(tester, memory: true);
    await _takeThePassage(tester, room, 'P01');
    await tester.pump(const Duration(seconds: 1));
    room.harness.room.holdNextTurn();
    room.notifier.conversaTap();
    await _passTime(tester, 300);
    room.notifier.conversaTap();
    await _passTime(tester, 300);

    expect(room.state.voice, VoiceState.thinking);
    expect(_hidden(tester, _leave), isTrue);
    final asked = room.harness.room.calls.length;

    await tester.tap(byLabel(_leave), warnIfMissed: false);
    await _passTime(tester, 300);

    expect(room.state.stage, SalaStage.conversa);
    expect(room.harness.room.calls.length, asked);

    room.harness.room.finishHeldTurn();
    await _passTime(tester);
  });

  testWidgets(
    'a facilitator reply that is playing stops when the team leaves, and the '
    'hand offers it again on the way back',
    (tester) async {
      final room = await _pump(
        tester,
        replies: const [HandReply(id: 'r1', audioUrl: '/voice/r1')],
      );
      await _takeThePassage(tester, room, 'P01');
      await tester.pump(const Duration(seconds: 1));
      room.harness.voice.holdNextLine();
      room.notifier.handTap();
      await _passTime(tester, 300);
      expect(room.state.playingReplyId, 'r1');
      final stops = room.harness.voice.stops;

      await _tap(tester, _leave);
      room.harness.voice.succeeds = false;
      room.harness.voice.finishHeldLine();
      room.harness.voice.succeeds = true;
      await tester.pump(const Duration(seconds: 1));

      expect(room.harness.voice.stops, greaterThan(stops));
      expect(room.harness.inbox.heard, isEmpty);

      await _tap(tester, _back);
      await tester.pump(const Duration(seconds: 1));

      expect(byLabel(_hearTheAnswer), findsOneWidget);
      room.notifier.handTap();
      await _passTime(tester, 300);

      expect(
        room.harness.voice.played.where((url) => url == '/voice/r1'),
        hasLength(2),
      );
    },
  );

  for (final (lingua, leave, back, other) in [
    (
      'pt',
      'Escolher outra passagem',
      'Voltar para a passagem atual',
      [_leave, _back],
    ),
    (
      'en',
      _leave,
      _back,
      ['Escolher outra passagem', 'Voltar para a passagem atual'],
    ),
  ]) {
    testWidgets(
      'the reader reads the two labels in the room\'s language ($lingua)',
      (tester) async {
        final room = await _pump(tester, lingua: lingua);
        await _takeThePassage(tester, room, 'P01');
        await tester.pump(const Duration(seconds: 1));

        expect(byLabel(leave), findsOneWidget);
        expect(byLabel(other.first), findsNothing);

        await _tap(tester, leave);
        await tester.pump(const Duration(seconds: 1));

        expect(byLabel(back), findsOneWidget);
        expect(byLabel(other.last), findsNothing);
      },
    );
  }

  testWidgets(
    'a passage that cannot open lays the one left back on its canvas',
    (tester) async {
      final room = await _pump(tester, cannotOpen: {'P02'});
      await _takeThePassage(tester, room, 'P01');
      await tester.pump(const Duration(seconds: 1));
      await _tap(tester, _leave);
      await tester.pump(const Duration(seconds: 1));
      expect(byLabel(_back), findsOneWidget);

      final p01 = room.state.leftEntry?.session;

      _open(room, 'P02');
      await tester.pump(const Duration(seconds: 2));

      expect(
        room.state.stage,
        SalaStage.conversa,
        reason:
            'a P02 que não abriu deixava a equipe na Escolha, a um toque da P01',
      );
      expect(room.state.sessionId, p01);
      expect(byLabel(_leave), findsOneWidget);
    },
  );

  testWidgets('a leave from the next passage returns to the next passage', (
    tester,
  ) async {
    final room = await _pump(tester);
    await _takeThePassage(tester, room, 'P01');
    await tester.pump(const Duration(seconds: 1));
    await _tap(tester, _leave);
    await tester.pump(const Duration(seconds: 1));
    await _takeThePassage(tester, room, 'P02');
    await tester.pump(const Duration(seconds: 1));
    final second = room.state.sessionId;
    expect(second, isNot(room.harness.room.sessionIds.first));

    await _tap(tester, _leave);
    await tester.pump(const Duration(seconds: 1));
    await _tap(tester, _back);
    await tester.pump(const Duration(seconds: 1));

    expect(room.state.station, isA<Canvas>());
    expect(room.state.sessionId, second);
  });

  testWidgets('a room that just opened offers no way back', (tester) async {
    final room = await _pump(tester);

    await room.notifier.openTheRoom();
    await tester.pump(const Duration(seconds: 1));

    expect(room.state.stage, SalaStage.escolha);
    expect(room.state.naRoda, isNotNull);
    expect(byLabel(_back), findsNothing);
  });

  testWidgets('the way back to a held passage shows before the Wheel is read', (
    tester,
  ) async {
    final room = await _pump(tester);
    await _takeThePassage(tester, room, 'P01');
    await tester.pump(const Duration(seconds: 1));
    final session = room.state.sessionId;
    room.harness.room.holdNextPassages();

    await _tap(tester, _leave);
    await tester.pump(const Duration(seconds: 1));
    final asked = room.harness.room.calls.length;

    expect(room.state.stage, SalaStage.escolha);
    expect(room.state.naRoda, isNull);
    expect(byLabel(_back), findsOneWidget);

    await _tap(tester, _back);
    await tester.pump(const Duration(seconds: 1));

    expect(room.state.station, isA<Canvas>());
    expect(room.state.pericope, 'P01');
    expect(room.state.sessionId, session);
    expect(room.harness.room.calls.skip(asked), isEmpty);
  });

  testWidgets('the way back returns to the passage left, in its own session', (
    tester,
  ) async {
    final room = await _pump(tester);
    await _takeThePassage(tester, room, 'P01');
    await tester.pump(const Duration(seconds: 1));
    final session = room.state.sessionId;
    final created = room.harness.room.pericopesAsked.length;
    expect(room.state.station, isA<Canvas>());

    await _tap(tester, _leave);
    await tester.pump(const Duration(seconds: 1));
    await _tap(tester, _back);
    await tester.pump(const Duration(seconds: 1));

    expect(room.state.station, isA<Canvas>());
    expect(room.state.sessionId, session);
    expect(room.harness.room.pericopesAsked, hasLength(created));
  });

  testWidgets('the Saved screen carries no «Back to recording», «Done» leaves '
      'for the conversation, and the Back-translation draws it again', (
    tester,
  ) async {
    final harness = SalaHarness(lingua: 'en', filaEmMemoria: true);
    harness.room.passages = _theBook;
    final room = _Room(harness, await pumpSala(tester, harness));
    await _takeThePassage(tester, room, 'P01');
    await _keepAPart(tester, room);
    room.notifier.startRetro();
    await _passTime(tester, 300);
    harness.playback.finishPlayback();
    await _passTime(tester, 300);
    await room.notifier.finishBackTranslation();
    await _passTime(tester, 400);
    await room.notifier.aprovarRascunhoFinal();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Rehearsal saved'), findsOneWidget);
    expect(byLabel(_backToRecording), findsNothing);

    await _tap(tester, 'Done');
    await tester.pump(const Duration(milliseconds: 400));

    expect(room.container.read(salaSessionProvider).stage, SalaStage.conversa);

    room.notifier.openTheEnsaioFinal();
    await _passTime(tester, 1000);
    room.notifier.startRetro();
    await _passTime(tester, 1000);

    expect(byLabel(_backToRecording), findsOneWidget);
    closeTheRoom(room.container);
  });
}
