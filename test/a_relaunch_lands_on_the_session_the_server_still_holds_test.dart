import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/device_link_notifier.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/ensaio_final_plan.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/ports.dart';
import 'package:internalization_room/features/sala/domain/station.dart';
import 'package:internalization_room/features/sala/domain/device_link.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/scene_question.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';
import 'um_ensaio_de_tres_partes.dart';

class _Tablet {
  final SalaHarness harness;
  final ProviderContainer container;

  _Tablet(this.harness, this.container);

  SalaSessionNotifier get notifier =>
      container.read(salaSessionProvider.notifier);

  SalaSessionState get state => container.read(salaSessionProvider);

  List<String> get said => [
    ...harness.voice.played,
    ...harness.voice.assets,
    for (final (line, _) in harness.voice.fixedLines) line,
  ];

  int asked(String call) =>
      harness.room.calls.where((asked) => asked == call).length;
}

Future<_Tablet> _aTablet({
  String lingua = testLanguage,
  bool watching = false,
}) async {
  final home = Directory.systemTemp.createTempSync('sala-sessao-atual');
  addTearDown(() => home.deleteSync(recursive: true));
  final harness = SalaHarness(
    lingua: lingua,
    watchesWithoutAHalt: watching,
    currentSession: LedgerThatReadsLate(home: () async => home),
  );
  final container = harness.container();
  addTearDown(container.dispose);
  return _Tablet(harness, container);
}

Future<_Tablet> _inP01({bool watching = false}) async {
  final tablet = await _aTablet(watching: watching);
  await enterThePassage(tablet.notifier, () => tablet.state, 'P01');
  await waitFor(
    'the opening to be said',
    () =>
        tablet.harness.voice.played.contains(turnoUrl) &&
        tablet.state.voice == VoiceState.invite,
  );
  await settle();
  return tablet;
}

Future<void> _takeATurn(_Tablet tablet) async {
  final sent = tablet.asked('sendTurn');
  tablet.notifier.conversaTap();
  await settle();
  tablet.notifier.conversaTap();
  await waitFor(
    'the turn to be answered',
    () =>
        tablet.asked('sendTurn') == sent + 1 &&
        tablet.state.voice == VoiceState.invite,
  );
  await settle();
}

Future<_Tablet> _relaunch(
  _Tablet tablet, {
  String? lingua,
  Duration? linkPoll,
}) async {
  final (harness, container) = await relaunch(
    tablet.harness,
    tablet.container,
    lingua: lingua,
    linkPoll: linkPoll,
  );
  return _Tablet(harness, container);
}

Future<void> _theChoiceShowsItsWheel(_Tablet tablet) => waitFor(
  'the Choice to show its Wheel',
  () => tablet.state.station is Menu && tablet.state.naRoda != null,
);

Future<void> _landsOn(_Tablet tablet, String session) async {
  await waitFor(
    'the team to land on the session',
    () =>
        tablet.state.sessionId == session &&
        !tablet.state.awaitingTheGuide &&
        tablet.state.voice == VoiceState.invite,
  );
  await settle();
}

Future<void> _intoThePanorama(_Tablet tablet) async {
  tablet.harness.room.passages = [
    const Passagem(
      pericope: 'OV-Ruth',
      audioUrl: '/voice/panorama',
      kind: PassagemKind.panorama,
      book: 'Ruth',
    ),
    ...tablet.harness.room.passages.where((entry) => !entry.isPanorama),
  ];
  await enterThePanorama(tablet.notifier, () => tablet.state);
  await waitFor(
    'the Panorama to be said',
    () =>
        tablet.state.station is Panorama &&
        tablet.state.panoramaSaid &&
        tablet.state.voice == VoiceState.invite,
  );
  await settle();
}

const _held = 'sessao-guardada';

_Tablet _aTabletHolding(SalaStage stage, {List<KeptTake> takes = const []}) {
  final harness = SalaHarness();
  (harness.currentSession as FakeCurrentSessionLedger).held =
      const CurrentSession(
        sessionId: _held,
        book: 'Ruth',
        pericope: 'P01',
        language: testLanguage,
      );
  harness.emAberto.rows['Ruth/P01/$testLanguage'] = ResumePoint(
    sessionId: _held,
    stage: stage,
    takes: takes,
  );
  harness.room.openedSessions.add(_held);
  final container = harness.container();
  addTearDown(container.dispose);
  return _Tablet(harness, container);
}

KeptTake _aPartHere() {
  final home = Directory.systemTemp.createTempSync('sala-parte-aqui');
  addTearDown(() => home.deleteSync(recursive: true));
  return KeptTake(
    scopeId: KeptScope.parte(1),
    path: (File('${home.path}/p1.m4a')..writeAsBytesSync([1])).path,
    takeId: 'gravacao-1',
  );
}

Future<void> _afterARelaunchTheClipIsReplayedFromTheTablet(
  _Tablet tablet,
  String session,
) async {
  final again = await _relaunch(tablet);
  await again.notifier.openTheRoom();
  await _landsOn(again, session);

  expect(again.state.canHearAgain, isTrue);
  await again.notifier.hearAgain();
  await waitFor(
    'the clip to be played again',
    () => again.harness.voice.played.isNotEmpty,
  );
  expect(again.harness.voice.played, [turnoUrl]);
  expect(again.harness.room.sessionsSaidAgain, isEmpty);
}

void main() {
  test(
    'a relaunch asks the room for the session the tablet holds before anything else',
    () async {
      final first = await _inP01();
      await _takeATurn(first);
      final session = first.state.sessionId!;

      final again = await _relaunch(first);
      final before = again.harness.room.calls.length;
      await again.notifier.openTheRoom();
      await _landsOn(again, session);

      expect(again.harness.room.calls.skip(before).first, 'fetchState');
      expect(
        again.harness.room.calls.skip(before),
        isNot(contains('passagesOf')),
      );
    },
  );

  group('a relaunch mid-conversation', () {
    late _Tablet again;
    late String session;
    late int before;

    setUp(() async {
      final first = await _inP01();
      await _takeATurn(first);
      session = first.state.sessionId!;
      again = await _relaunch(first);
      before = again.harness.room.calls.length;
      await again.notifier.openTheRoom();
      await _landsOn(again, session);
    });

    test('lands on that passage\'s Canvas in silence', () {
      expect(again.state.station, isA<Canvas>());
      expect(again.state.sessionId, session);
      expect(again.said, isEmpty);
      final asked = again.harness.room.calls.skip(before);
      expect(asked, isNot(contains('openSession')));
      expect(asked, isNot(contains('createSession')));
    });

    test(
      'offers «Ouvir de novo», which plays the clip held on the tablet, asking '
      'the room for nothing',
      () async {
        expect(again.state.canHearAgain, isTrue);

        await again.notifier.hearAgain();
        await waitFor(
          'the last clip to be played again',
          () => again.harness.voice.played.isNotEmpty,
        );

        expect(again.harness.voice.played, [turnoUrl]);
        expect(again.harness.room.sessionsSaidAgain, isEmpty);
        expect(
          again.harness.room.calls.skip(before),
          isNot(contains('openSession')),
        );
      },
    );

    test('«Ouvir de novo» asks the room to say it again when the clip is no '
        'longer on the tablet', () async {
      again.harness.voice.missing.add(turnoUrl);

      await again.notifier.hearAgain();
      await waitFor(
        'the last line to be said again',
        () => again.harness.voice.played.contains(deNovoUrl),
      );

      expect(again.harness.room.sessionsSaidAgain, [session]);
    });
  });

  test('«Ouvir de novo» live plays the clip already held, asking the room for '
      'nothing', () async {
    final tablet = await _inP01();
    await _takeATurn(tablet);
    final before = tablet.harness.room.calls.length;
    final played = tablet.harness.voice.played.length;

    await tablet.notifier.hearAgain();
    await waitFor(
      'the clip to be played again',
      () => tablet.harness.voice.played.length == played + 1,
    );

    expect(tablet.harness.voice.played.last, turnoUrl);
    expect(tablet.harness.room.calls.skip(before), isEmpty);
  });

  test(
    '«Ouvir de novo» is pinned to a line when it starts to speak, not when it '
    'has been heard',
    () async {
      const speaking = '/voice/still-speaking';
      final tablet = await _inP01();
      tablet.harness.room
        ..replyUrl = speaking
        ..holdNextTurn();
      tablet.notifier.conversaTap();
      await settle();
      tablet.notifier.conversaTap();
      await waitFor('the turn to be sent', () => tablet.asked('sendTurn') == 1);
      tablet.harness.voice.holdNextLine();
      tablet.harness.room.finishHeldTurn();
      await waitFor(
        'the reply to start',
        () => tablet.harness.voice.played.contains(speaking),
      );

      expect(tablet.state.lastSpoken?.url, speaking);

      tablet.harness.voice.finishHeldLine();
      await settle();
      await tablet.notifier.hearAgain();
      await settle();

      expect(tablet.harness.voice.played.last, speaking);
    },
  );

  test(
    'a relaunch after a turn of the team\'s, whose answer never came, offers '
    'no «Ouvir de novo», as hers',
    () async {
      final first = await _inP01();
      final session = first.state.sessionId!;
      first.harness.room.holdNextTurn();
      first.notifier.conversaTap();
      await settle();
      first.notifier.conversaTap();
      await waitFor('the turn to be sent', () => first.asked('sendTurn') == 1);

      final again = await _relaunch(first);
      await again.notifier.openTheRoom();
      await _landsOn(again, session);

      expect(again.state.canHearAgain, isFalse);
      expect(again.harness.room.sessionsSaidAgain, isEmpty);
    },
  );

  test('a team turn the room refused leaves the conversation ending on the '
      'Guide: a relaunch still replays the clip', () async {
    final first = await _inP01();
    final session = first.state.sessionId!;
    first.harness.room.failTurnsWith = const Refused('BAD_REQUEST');
    first.notifier.conversaTap();
    await settle();
    first.notifier.conversaTap();
    await waitFor('the turn to be sent', () => first.asked('sendTurn') == 1);
    await settle();
    first.harness.room.failTurnsWith = null;

    await _afterARelaunchTheClipIsReplayedFromTheTablet(first, session);
  });

  test('a team turn the room never took leaves the conversation ending on the '
      'Guide: a relaunch still replays the clip', () async {
    final first = await _inP01();
    final session = first.state.sessionId!;
    first.harness.room.failTurnsWith = const NetworkFailed('sem rede');
    first.notifier.conversaTap();
    await settle();
    first.notifier.conversaTap();
    await waitFor('the turn to be sent', () => first.asked('sendTurn') == 1);
    await settle();
    first.harness.room.failTurnsWith = null;

    await _afterARelaunchTheClipIsReplayedFromTheTablet(first, session);
  });

  test(
    'a passage switched back to, whose conversation ends on a Guide turn, '
    'offers «Ouvir de novo» and plays that clip, asking the room nothing',
    () async {
      final tablet = await _inP01();
      final session = tablet.state.sessionId!;
      tablet.notifier.leaveThePassage();
      await enterThePassage(tablet.notifier, () => tablet.state, 'P02');
      await waitFor(
        'P02 to open',
        () =>
            tablet.state.sessionId != null &&
            tablet.state.sessionId != session &&
            tablet.state.voice == VoiceState.invite,
      );
      tablet.notifier.leaveThePassage();
      await enterThePassage(tablet.notifier, () => tablet.state, 'P01');
      await _landsOn(tablet, session);
      final played = tablet.harness.voice.played.length;

      expect(tablet.state.canHearAgain, isTrue);
      await tablet.notifier.hearAgain();
      await waitFor(
        'the clip to be played again',
        () => tablet.harness.voice.played.length > played,
      );

      expect(tablet.harness.voice.played.last, turnoUrl);
      expect(tablet.harness.room.sessionsSaidAgain, isEmpty);
    },
  );

  test('a passage switched back to, whose last turn of the team\'s the room '
      'refused, still ends on the Guide: it plays that clip', () async {
    final tablet = await _inP01();
    final session = tablet.state.sessionId!;
    tablet.harness.room.failTurnsWith = const Refused('BAD_REQUEST');
    tablet.notifier.conversaTap();
    await settle();
    tablet.notifier.conversaTap();
    await waitFor('the turn to be sent', () => tablet.asked('sendTurn') == 1);
    await settle();
    tablet.harness.room.failTurnsWith = null;
    tablet.notifier.leaveThePassage();
    await enterThePassage(tablet.notifier, () => tablet.state, 'P02');
    await waitFor(
      'P02 to open',
      () =>
          tablet.state.sessionId != null &&
          tablet.state.sessionId != session &&
          tablet.state.voice == VoiceState.invite,
    );
    tablet.notifier.leaveThePassage();
    await enterThePassage(tablet.notifier, () => tablet.state, 'P01');
    await _landsOn(tablet, session);
    final played = tablet.harness.voice.played.length;

    expect(tablet.state.canHearAgain, isTrue);
    await tablet.notifier.hearAgain();
    await waitFor(
      'the clip to be played again',
      () => tablet.harness.voice.played.length > played,
    );

    expect(tablet.harness.voice.played.last, turnoUrl);
    expect(tablet.harness.room.sessionsSaidAgain, isEmpty);
  });

  test('a passage switched back to after a relaunch plays the clip its '
      'conversation ended on, asking the room nothing', () async {
    final first = await _inP01();
    final session = first.state.sessionId!;
    first.notifier.leaveThePassage();
    await enterThePassage(first.notifier, () => first.state, 'P02');
    await waitFor(
      'P02 to open',
      () =>
          first.state.sessionId != null &&
          first.state.sessionId != session &&
          first.state.voice == VoiceState.invite,
    );
    final again = await _relaunch(first);
    await again.notifier.openTheRoom();
    await _landsOn(again, again.state.sessionId ?? '');
    again.notifier.leaveThePassage();
    await enterThePassage(again.notifier, () => again.state, 'P01');
    await _landsOn(again, session);
    final played = again.harness.voice.played.length;

    expect(again.state.canHearAgain, isTrue);
    await again.notifier.hearAgain();
    await waitFor(
      'the clip to be played again',
      () => again.harness.voice.played.length > played,
    );

    expect(again.harness.voice.played.last, turnoUrl);
    expect(again.harness.room.sessionsSaidAgain, isEmpty);
  });

  test('a session whose resume the room refuses twice is forgotten with its '
      'end', () async {
    final tablet = await _inP01();
    final session = tablet.state.sessionId!;
    expect(await tablet.harness.currentSession.endOf(session), isNotNull);
    tablet.notifier.leaveThePassage();
    for (var refusal = 0; refusal < 2; refusal++) {
      tablet.harness.room.failCreateOnceWith = const Refused('RECUSADA');
      await enterThePassage(tablet.notifier, () => tablet.state, 'P01');
      await settle();
      tablet.notifier.leaveThePassage();
      await settle();
    }

    expect(await tablet.harness.currentSession.endOf(session), isNull);
  });

  test('the clip survives a round trip to the Panorama: a later relaunch still '
      'replays it from the tablet', () async {
    final first = await _inP01();
    final session = first.state.sessionId!;
    await _intoThePanorama(first);
    await enterThePassage(first.notifier, () => first.state, 'P01');
    await _landsOn(first, session);

    await _afterARelaunchTheClipIsReplayedFromTheTablet(first, session);
  });

  test('the clip survives a relaunch whose read failed and the same passage '
      'opened after it', () async {
    final first = await _inP01();
    final session = first.state.sessionId!;
    final offline = await _relaunch(first);
    offline.harness.room.reachable = false;
    await offline.notifier.openTheRoom();
    await settle();
    offline.harness.room.reachable = true;
    offline.notifier.escolhaTap();
    await _theChoiceShowsItsWheel(offline);
    await enterThePassage(offline.notifier, () => offline.state, 'P01');
    await _landsOn(offline, session);

    await _afterARelaunchTheClipIsReplayedFromTheTablet(offline, session);
  });

  test(
    'a relaunch while the conversation\'s microphone is open loses that take and says nothing',
    () async {
      final first = await _inP01();
      final session = first.state.sessionId!;
      final sent = first.harness.room.turnsSent;
      first.notifier.conversaTap();
      await waitFor(
        'the microphone to open',
        () => first.harness.recorder.captures == 1,
      );

      final again = await _relaunch(first);
      await again.notifier.openTheRoom();
      await _landsOn(again, session);
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(again.state.sessionId, session);
      expect(again.harness.room.turnsSent, sent);
      expect(await again.harness.takes.entries(), isEmpty);
      expect(again.said, isEmpty);
    },
  );

  test(
    'a relaunch into a session whose Opening never landed asks nothing',
    () async {
      final first = await _aTablet();
      first.harness.room.holdNextTurn();
      await enterThePassage(first.notifier, () => first.state, 'P01');
      await waitFor(
        'the Opening to be asked',
        () => first.asked('openSession') == 1,
      );
      final session = first.state.sessionId!;
      await settle();

      final again = await _relaunch(first);
      final before = again.harness.room.calls.length;
      await again.notifier.openTheRoom();
      await _landsOn(again, session);

      expect(again.state.station, isA<Canvas>());
      expect(
        again.harness.room.calls.skip(before),
        isNot(contains('openSession')),
      );
      expect(again.said, isEmpty);
    },
  );

  test(
    'a relaunch in the Rehearsal lands on its conversation at rest, never on '
    'the recording home',
    () async {
      final first = await _aTablet();
      final it = Sala(first.harness, first.container);
      await enterThePassage(first.notifier, () => first.state, 'P01');
      await waitFor(
        'the opening to be said',
        () =>
            first.state.sessionId != null &&
            first.state.voice == VoiceState.invite,
      );
      final session = first.state.sessionId!;
      it.sala.goEnsaio();
      await gravarUmaParteDoEnsaio(it, 1);
      await settle();

      final again = await _relaunch(first);
      final before = again.harness.room.calls.length;
      await again.notifier.openTheRoom();
      await _landsOn(again, session);

      expect(
        again.state.station,
        isA<Canvas>(),
        reason: 'o relançamento voltava para a casa das gravações',
      );
      expect(again.state.lastSpoken, isNotNull);
      expect(
        again.harness.room.calls.skip(before),
        isNot(contains('openSession')),
      );
      expect(again.said, isEmpty);
    },
  );

  group(
    'a passage picked on the Choice lands on its conversation, as hers',
    () {
      Future<_Tablet> pickedOnTheChoice(
        SalaStage stage, {
        bool done = false,
      }) async {
        final harness = SalaHarness();
        harness.emAberto.rows['Ruth/P01/$testLanguage'] = ResumePoint(
          sessionId: _held,
          stage: stage,
          takes: [_aPartHere()],
        );
        harness.room
          ..openedSessions.add(_held)
          ..done = done;
        final container = harness.container();
        addTearDown(container.dispose);
        final tablet = _Tablet(harness, container);
        await tablet.notifier.openTheRoom();
        await _theChoiceShowsItsWheel(tablet);
        await enterThePassage(tablet.notifier, () => tablet.state, 'P01');
        await waitFor(
          'the team to land on the session',
          () =>
              tablet.state.sessionId == _held && !tablet.state.awaitingTheGuide,
        );
        await settle();
        return tablet;
      }

      for (final stage in [SalaStage.ensaio, SalaStage.retro]) {
        test('from a stored ${stage.name} row, at rest', () async {
          final tablet = await pickedOnTheChoice(stage);

          expect(
            tablet.state.station,
            isA<Canvas>(),
            reason:
                'a escolha caía direto na estação guardada, e a dela cai '
                'na conversa',
          );
          expect(tablet.state.roomSaysItAgain, isTrue);
          expect(tablet.said, isEmpty);
          expect(tablet.harness.playback.played, isEmpty);
        });
      }

      test('with the room\'s phase: a done passage reads done', () async {
        final tablet = await pickedOnTheChoice(SalaStage.ensaio, done: true);

        expect(tablet.state.station, isA<Canvas>());
        expect(
          tablet.state.endOfThePassage,
          isTrue,
          reason: 'a passagem acabada voltava sem o ponto aceso',
        );
        expect(tablet.state.orangeDotLook, OrangeDotLook.bright);
      });

      test('the dot stays shut while the room is read, and the room\'s phase '
          'lands when it answers', () async {
        final harness = SalaHarness();
        harness.emAberto.rows['Ruth/P01/$testLanguage'] = ResumePoint(
          sessionId: _held,
          stage: SalaStage.ensaio,
          takes: [_aPartHere()],
        );
        harness.room
          ..openedSessions.add(_held)
          ..done = true;
        final container = harness.container();
        addTearDown(container.dispose);
        final tablet = _Tablet(harness, container);
        await tablet.notifier.openTheRoom();
        await _theChoiceShowsItsWheel(tablet);
        harness.room.holdNextCreate();
        await enterThePassage(tablet.notifier, () => tablet.state, 'P01');
        await waitFor(
          'the room to be asked',
          () => harness.room.calls.contains('createSession'),
        );
        await settle();

        tablet.notifier.openTheEnsaioFinal();
        await settle();

        expect(
          tablet.state.station,
          isA<Canvas>(),
          reason:
              'o ponto laranja abria a casa com a leitura da sala ainda no ar, '
              'e a leitura era abandonada',
        );
        harness.room.finishHeldCreate();
        await waitFor('the read to land', () => !tablet.state.awaitingTheGuide);
        expect(tablet.state.sessionId, _held);
        expect(tablet.state.endOfThePassage, isTrue);
        expect(tablet.state.orangeDotLook, OrangeDotLook.bright);
      });
    },
  );

  test('a relaunch whose row names another session than the one held reads '
      'the row\'s session, not the launch\'s', () async {
    final tablet = _aTabletHolding(SalaStage.ensaio, takes: [_aPartHere()]);
    tablet.harness.emAberto.rows['Ruth/P01/$testLanguage'] = ResumePoint(
      sessionId: 'sessao-da-linha',
      stage: SalaStage.ensaio,
      takes: [_aPartHere()],
    );
    tablet.harness.room.forgottenSessions.add('sessao-da-linha');

    await tablet.notifier.openTheRoom();
    await waitFor(
      'the row\'s session to be read',
      () => tablet.harness.room.askedOfTheForgotten.contains('fetchState'),
    );
    await settle();

    expect(
      tablet.harness.room.askedOfTheForgotten,
      contains('fetchState'),
      reason: 'a sessão da linha nunca era lida, só a guardada',
    );
    expect(
      tablet.state.station,
      isA<Menu>(),
      reason:
          'a linha de uma sessão que a sala esqueceu pousava na conversa com a '
          'leitura de outra sessão',
    );
    expect(tablet.state.sessionId, isNull);
  });

  test('a relaunch lands on the read its launch made, and reads the room '
      'only once', () async {
    final tablet = _aTabletHolding(SalaStage.ensaio, takes: [_aPartHere()]);
    tablet.harness.room.holdNextState();
    unawaited(tablet.notifier.openTheRoom());
    await waitFor(
      'the launch read to be in the air',
      () => tablet.asked('fetchState') == 1,
    );
    tablet.harness.room
      ..failStateOnceWith = const NetworkFailed('sem rede')
      ..finishHeldState();
    await _landsOn(tablet, _held);

    expect(tablet.state.station, isA<Canvas>());
    expect(tablet.state.needsPerson, isFalse);
    expect(
      tablet.asked('fetchState'),
      1,
      reason:
          'o relançamento lia a sessão de novo depois da leitura da '
          'abertura, e essa segunda leitura podia falhar o pouso',
    );
  });

  test(
    'a relaunch in the Back-translation lands on its conversation at rest and '
    'plays nothing',
    () async {
      final tablet = _aTabletHolding(SalaStage.retro, takes: [_aPartHere()]);

      await tablet.notifier.openTheRoom();
      await _landsOn(tablet, _held);

      expect(
        tablet.state.station,
        isA<Canvas>(),
        reason: 'o relançamento voltava para a retrotradução',
      );
      expect(tablet.state.roomSaysItAgain, isTrue);
      expect(tablet.harness.playback.played, isEmpty);
      expect(tablet.said, isEmpty);
    },
  );

  test(
    'a relaunch onto a checked Back-translation the room holds no parts for '
    'lands on its conversation with «Ouvir de novo», not on the check',
    () async {
      final tablet = _aTabletHolding(SalaStage.retro);
      tablet.harness.room.retroSoFar = const BackTranslationProgress(
        segments: [
          SegmentView(
            segmentId: 'trecho-1',
            takeId: 'gravacao-1',
            startsMs: 0,
            endsMs: 12000,
          ),
        ],
        checked: true,
      );

      await tablet.notifier.openTheRoom();
      await waitFor(
        'the team to stop on the session',
        () => tablet.state.sessionId == _held && !tablet.state.awaitingTheGuide,
      );
      await settle();

      expect(
        tablet.state.station,
        isA<Canvas>(),
        reason: 'o relançamento abria a retrotradução conferida',
      );
      expect(tablet.state.roomSaysItAgain, isTrue);
      expect(tablet.said, isEmpty);
    },
  );

  test(
    'a relaunch onto a Rehearsal with no part yet lands on its conversation',
    () async {
      final tablet = _aTabletHolding(SalaStage.ensaio);

      await tablet.notifier.openTheRoom();
      await _landsOn(tablet, _held);

      expect(
        tablet.state.station,
        isA<Canvas>(),
        reason: 'o relançamento abria o ensaio vazio',
      );
      expect(tablet.state.roomSaysItAgain, isTrue);
    },
  );

  test(
    'a relaunch onto a Rehearsal whose parts left the tablet lands on its '
    'conversation without fetching them, and the place still names them',
    () async {
      const gone = KeptTake(
        scopeId: 'parte-1',
        path: '/nao/existe/p1.m4a',
        takeId: 'gravacao-1',
      );
      final tablet = _aTabletHolding(SalaStage.ensaio, takes: [gone]);
      tablet.harness.room
        ..takes.add(
          const TakeView(
            takeId: 'gravacao-1',
            kind: 'ensaio',
            scope: 'parte-1',
            ordinal: 1,
          ),
        )
        ..takeAudio['gravacao-1'] = Uint8List.fromList([7, 7]);

      await tablet.notifier.openTheRoom();
      await _landsOn(tablet, _held);
      await settle(const Duration(milliseconds: 500));

      expect(tablet.state.station, isA<Canvas>());
      expect(
        tablet.asked('fetchClip'),
        0,
        reason: 'o relançamento baixava as partes atrás da conversa',
      );
      final row = tablet.harness.emAberto.rows['Ruth/P01/$testLanguage'];
      expect(
        row?.stage,
        SalaStage.ensaio,
        reason: 'a parte baixada reescrevia o lugar como conversa',
      );
      expect(row?.takes.map((take) => take.takeId), ['gravacao-1']);
    },
  );

  test(
    'after a relaunch the orange dot opens the recording home with the parts '
    'the tablet kept, and the place stands there with them',
    () async {
      final part = _aPartHere();
      final tablet = _aTabletHolding(SalaStage.ensaio, takes: [part]);
      await tablet.notifier.openTheRoom();
      await _landsOn(tablet, _held);

      tablet.notifier.openTheEnsaioFinal();
      await waitFor(
        'the recording home to open',
        () => tablet.state.station == const Ensaio(),
      );
      await settle();

      expect(tablet.state.station, const Ensaio());
      expect(
        tablet.state.partes.map((take) => take.path),
        [part.path],
        reason: 'a casa abria sem a parte guardada no tablet',
      );
      final row = tablet.harness.emAberto.rows['Ruth/P01/$testLanguage'];
      expect(row?.stage, SalaStage.ensaio);
      expect(row?.takes.map((take) => take.path), [part.path]);
    },
  );

  test('after a relaunch a part the room never received does not open the '
      'recording home, the room listing nothing opens the plan', () async {
    final here = _aPartHere();
    final unsent = KeptTake(scopeId: here.scopeId, path: here.path);
    final tablet = _aTabletHolding(SalaStage.ensaio, takes: [unsent]);
    tablet.harness.room.passageScenes = const [
      Scene(sceneId: 'S1', title: 'A fome em Belém'),
    ];
    await tablet.notifier.openTheRoom();
    await _landsOn(tablet, _held);

    tablet.notifier.openTheEnsaioFinal();
    await waitFor(
      'the plan to be read',
      () => tablet.state.ensaioFinalPlan is! PlanAwaited,
    );

    expect(
      tablet.state.station,
      const Ensaio(step: EnsaioStep.plan),
      reason:
          'a parte que só o tablet guardava abria a casa de gravação de '
          'uma vez, e a dela abre o plano',
    );
    expect(tablet.state.ensaioFinalPlan, isA<PlanRead>());
  });

  group('a relaunch into a session the room no longer knows', () {
    late _Tablet again;

    setUp(() async {
      final first = await _inP01();
      first.harness.emAberto.forgetsTheSessionAfter = const Duration(
        milliseconds: 500,
      );
      final session = first.state.sessionId!;
      again = await _relaunch(first);
      again.harness.room.forgetTheSession(session);
      await again.notifier.openTheRoom();
      await _theChoiceShowsItsWheel(again);
      await settle();
    });

    test('lands on the Choice with no person sign and nothing said', () {
      expect(again.state.station, isA<Menu>());
      expect(again.state.naRoda, isNotNull);
      expect(again.state.needsPerson, isFalse);
      expect(
        again.said,
        everyElement(isIn([for (final p in again.state.naRoda!) p.audioUrl])),
        reason: 'only the Wheel offering its passages',
      );
    });

    test('lets the session go', () async {
      await waitFor(
        'the place of the lost session to leave the tablet',
        () async => !(await again.harness.emAbertoNoDisco!.startedIn(
          'Ruth',
          'pt',
        )).contains('P01'),
      );
      expect(
        await again.harness.emAbertoNoDisco!.startedIn('Ruth', 'pt'),
        isNot(contains('P01')),
      );

      final third = await _relaunch(again);
      final reads = third.asked('fetchState');
      await third.notifier.openTheRoom();
      await _theChoiceShowsItsWheel(third);

      expect(third.asked('fetchState'), reads);
    });
  });

  test(
    'a relaunch after the facilitator reset the passage lands on the Choice',
    () async {
      final first = await _inP01();
      final session = first.state.sessionId!;
      first.harness.room.forgetTheSession(session);

      final again = await _relaunch(first);
      final created = again.asked('createSession');
      await again.notifier.openTheRoom();
      await _theChoiceShowsItsWheel(again);
      await settle();

      expect(again.state.station, isA<Menu>());
      expect(again.asked('createSession'), created);
      expect(again.state.sessionId, isNull);
    },
  );

  test('a relaunch with no reach never shows the old Canvas', () async {
    final first = await _inP01();
    final session = first.state.sessionId!;

    final again = await _relaunch(first);
    final stations = <Station>[];
    again.container.listen(
      salaSessionProvider,
      (_, next) => stations.add(next.station),
    );
    again.harness.room.reachable = false;
    await again.notifier.openTheRoom();
    await settle();

    expect(stations, everyElement(isA<Menu>()));
    expect(again.state.station, isA<Menu>());

    again.harness.room.reachable = true;
    again.notifier.escolhaTap();
    await _theChoiceShowsItsWheel(again);

    final later = await _relaunch(again);
    await later.notifier.openTheRoom();
    await _landsOn(later, session);

    expect(later.state.station, isA<Canvas>());
  });

  test('a relaunch holding nothing opens the Choice', () async {
    final tablet = await _aTablet();

    await tablet.notifier.openTheRoom();
    await _theChoiceShowsItsWheel(tablet);

    expect(tablet.asked('passagesOf'), 1);
    expect(tablet.asked('fetchState'), 0);
  });

  group('a relaunch lands on the Choice and asks for no session', () {
    Future<void> relaunchedOnTheChoice(_Tablet left) async {
      final again = await _relaunch(left);
      final reads = again.asked('fetchState');
      await again.notifier.openTheRoom();
      await _theChoiceShowsItsWheel(again);
      await settle();

      expect(again.state.station, isA<Menu>());
      expect(again.asked('fetchState'), reads);
    }

    test('in a passage the team left', () async {
      final tablet = await _inP01();
      tablet.notifier.leaveThePassage();
      await _theChoiceShowsItsWheel(tablet);
      await settle();

      await relaunchedOnTheChoice(tablet);
    });

    test('after the session went away mid-passage', () async {
      final tablet = await _inP01(watching: true);
      tablet.harness.room.forgetTheSession(tablet.state.sessionId!);
      await waitFor(
        'the room to go to the Choice',
        () => tablet.state.station is Menu && tablet.state.naRoda != null,
      );
      await settle();

      await relaunchedOnTheChoice(tablet);
    });
  });

  test(
    'a relaunch with another language chosen lands on the session in its own language',
    () async {
      final tablet = await _inP01();
      final session = tablet.state.sessionId!;
      final again = await _relaunch(tablet, lingua: 'en');

      await again.notifier.openTheRoom();
      await _landsOn(again, session);

      expect(again.harness.room.languagesSent, isNot(contains('en')));
    },
  );

  test(
    'opening the room again while the relaunch\'s read is in the air changes nothing',
    () async {
      final first = await _inP01();
      final session = first.state.sessionId!;

      final again = await _relaunch(first);
      final ledger = again.harness.currentSession as LedgerThatReadsLate;
      ledger.readsAfter = const Duration(milliseconds: 500);
      final before = again.harness.room.calls.length;
      again.harness.room.holdNextState();
      final launched = again.notifier.openTheRoom();
      await waitFor(
        'the first read of the session to reach the room',
        () => again.harness.room.calls.skip(before).contains('fetchState'),
      );
      ledger.readsAfter = null;
      final twice = again.notifier.openTheRoom();
      await settle();

      expect(
        again.harness.room.calls.skip(before).where((c) => c == 'fetchState'),
        hasLength(1),
      );

      again.harness.room.finishHeldState();
      await Future.wait([launched, twice]);
      await _landsOn(again, session);

      expect(
        again.harness.room.calls.skip(before),
        isNot(contains('passagesOf')),
      );
      expect(again.said, isEmpty);
    },
  );

  test('a tablet linked again to another team opens the Choice', () async {
    final first = await _inP01();

    final again = await _relaunch(
      first,
      linkPoll: const Duration(milliseconds: 50),
    );
    again.harness.room.refuseCredentialWith = const Refused(
      RefusalCode.credentialTaken,
    );
    final link = again.container.read(deviceLinkProvider.notifier);
    await link.findTheTeam();
    await waitFor(
      'the link to start over',
      () => again.container.read(deviceLinkProvider).code != null,
    );
    again.harness.room
      ..refuseCredentialWith = null
      ..linkedTo = const TeamLink(projectId: 'outra-equipe');
    await waitFor(
      'the tablet to be linked again',
      () => again.container.read(deviceLinkProvider).linked,
    );
    await settle();

    final later = await _relaunch(again);
    final reads = later.asked('fetchState');
    await later.notifier.openTheRoom();
    await _theChoiceShowsItsWheel(later);

    expect(later.state.station, isA<Menu>());
    expect(later.asked('fetchState'), reads);
  });

  test(
    'the room resumed after a launch that lost the network stays on the Choice',
    () async {
      final first = await _inP01();
      final session = first.state.sessionId!;

      final again = await _relaunch(first);
      again.harness.room.reachable = false;
      await again.notifier.openTheRoom();
      again.harness.room.reachable = true;
      final reads = again.asked('fetchState');

      await again.notifier.openTheRoom();
      await _theChoiceShowsItsWheel(again);
      await settle();

      expect(again.state.station, isA<Menu>());
      expect(again.state.sessionId, isNull);
      expect(again.asked('fetchState'), reads);

      final later = await _relaunch(again);
      await later.notifier.openTheRoom();
      await _landsOn(later, session);
    },
  );

  test(
    'a relaunch in a passage and then the Panorama opens the Panorama, not the '
    'passage',
    () async {
      final first = await _inP01();
      final passage = first.state.sessionId!;
      final again = await _relaunch(first);
      await again.notifier.openTheRoom();
      await _landsOn(again, passage);

      again.notifier.leaveThePassage();
      await _theChoiceShowsItsWheel(again);
      await _intoThePanorama(again);

      expect(again.harness.room.pericopesAsked.last, 'OV-Ruth');
      expect(again.state.station, isA<Panorama>());
      expect(again.harness.room.sessionIds.last, isNot(passage));
      expect(
        again.harness.room.sessionsSpokenTo.last,
        again.harness.room.sessionIds.last,
      );
    },
  );

  group('the Panorama is the current session', () {
    test('entering it stores its session', () async {
      final tablet = await _aTablet();
      await _intoThePanorama(tablet);

      final held = await tablet.harness.currentSession.read();

      expect(held?.sessionId, tablet.state.panoramaSessionId);
      expect(held?.panorama, isTrue);
      expect(held?.pericope, 'OV-Ruth');
    });

    test('a relaunch resumes it silent, with «ouvir de novo»', () async {
      final tablet = await _aTablet();
      await _intoThePanorama(tablet);
      final panorama = tablet.state.panoramaSessionId;
      final again = await _relaunch(tablet);
      final opened = again.asked('openSession');

      await again.notifier.openTheRoom();
      await waitFor(
        'the team to land on the Panorama',
        () =>
            again.state.station is Panorama &&
            again.state.panoramaSaid &&
            again.state.voice == VoiceState.invite,
      );
      await settle();

      expect(again.state.panoramaSessionId, panorama);
      expect(again.asked('openSession'), opened);
      expect(again.said, isEmpty);
      expect(again.state.roomSaysItAgain, isTrue);
    });

    test('leaving it for a passage replaces it', () async {
      final tablet = await _aTablet();
      await _intoThePanorama(tablet);
      await enterThePassage(tablet.notifier, () => tablet.state, 'P01');
      await waitFor(
        'the passage to open',
        () => tablet.state.station is Canvas && tablet.state.sessionId != null,
      );
      await settle();

      final held = await tablet.harness.currentSession.read();

      expect(held?.sessionId, tablet.state.sessionId);
      expect(held?.panorama, isFalse);
    });

    test(
      'a relaunch before its opening reached the room asks for it',
      () async {
        final tablet = await _aTablet();
        await _intoThePanorama(tablet);
        tablet.harness.room.openedSessions.clear();
        final again = await _relaunch(tablet);
        final opened = again.asked('openSession');

        await again.notifier.openTheRoom();
        await waitFor(
          'the opening to be asked',
          () => again.asked('openSession') == opened + 1,
        );
      },
    );

    test('the way back to it holds it again', () async {
      final tablet = await _aTablet();
      await _intoThePanorama(tablet);
      final panorama = tablet.state.panoramaSessionId;
      tablet.notifier.leaveThePassage();
      await _theChoiceShowsItsWheel(tablet);
      await settle();
      expect(await tablet.harness.currentSession.read(), isNull);

      await tablet.notifier.returnToTheLeftEntry();
      await settle();

      final held = await tablet.harness.currentSession.read();
      expect(held?.sessionId, panorama);
      expect(held?.panorama, isTrue);
    });

    test('after a launch that lost the network, entering it still lets a '
        'relaunch resume it', () async {
      final first = await _inP01();
      final offline = await _relaunch(first);
      offline.harness.room.reachable = false;
      await offline.notifier.openTheRoom();
      offline.harness.room.reachable = true;
      await offline.notifier.openTheRoom();
      await _theChoiceShowsItsWheel(offline);
      await _intoThePanorama(offline);
      final panorama = offline.state.panoramaSessionId;
      final again = await _relaunch(offline);

      await again.notifier.openTheRoom();
      await waitFor(
        'the team to land on the Panorama',
        () => again.state.station is Panorama && again.state.panoramaSaid,
      );

      expect(again.state.panoramaSessionId, panorama);
    });
  });
}
