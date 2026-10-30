import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/halt.dart';
import 'package:internalization_room/features/sala/domain/left_entry.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/moment.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';

typedef _Tablet = ({
  SalaHarness harness,
  ProviderContainer container,
  SalaSessionNotifier notifier,
  SalaSessionState Function() read,
  String p01,
});

Future<_Tablet> _onTheChoiceFromP01([SalaHarness? given]) async {
  final harness = given ?? SalaHarness();
  harness.room.nextCoverage = coverage(engaged: 2, surfaced: 3);
  harness.room.nextMoment = const Moment(
    at: MomentAt.internalization,
    part: 1,
    parts: 3,
  );
  final container = harness.container();
  addTearDown(container.dispose);
  final notifier = container.read(salaSessionProvider.notifier);
  SalaSessionState read() => container.read(salaSessionProvider);
  await enterThePassage(notifier, read, 'P01');
  await waitFor(
    'P01 to open',
    () => read().sessionId != null && read().voice == VoiceState.invite,
  );
  final p01 = read().sessionId!;
  notifier.leaveThePassage();
  await waitFor(
    'the way back to P01 to be live',
    () => read().entriesOpen && read().theWayBackIsLive,
  );
  return (
    harness: harness,
    container: container,
    notifier: notifier,
    read: read,
    p01: p01,
  );
}

void main() {
  test('the way back with no network lands on the passage left as it was, '
      'asking the room for nothing', () async {
    final tablet = await _onTheChoiceFromP01();
    final harness = tablet.harness;
    final read = tablet.read;
    final asked = harness.room.calls.length;
    final checks = harness.inbox.checks;
    harness.room.reachable = false;

    await tablet.notifier.returnToTheLeftEntry();
    await settle();
    await settle();

    expect(
      read().station,
      isA<Canvas>(),
      reason: 'sem rede, a volta relia a sala e caía na Escolha sem roda',
    );
    expect(read().sessionId, tablet.p01);
    expect(read().pericope, 'P01');
    expect(read().coverage.engaged, 2);
    expect(read().coverage.surfaced, 3);
    expect(read().moment?.at, MomentAt.internalization);
    expect(read().moment?.part, 1);
    expect(read().moment?.parts, 3);
    expect(read().voice, VoiceState.invite);
    expect(
      harness.room.calls.skip(asked),
      isEmpty,
      reason: 'a volta lia as cenas, o estado da sessão e a roda',
    );
    expect(harness.inbox.checks, checks);
  });

  test('a pill whose resume cannot be read with no network lays the passage '
      'left back on its canvas', () async {
    final harness = SalaHarness();
    harness.emAberto.rows['Ruth/P02/pt'] = const ResumePoint(
      sessionId: 'sessao-da-p02',
      stage: SalaStage.conversa,
    );
    final tablet = await _onTheChoiceFromP01(harness);
    final read = tablet.read;
    final p02 = read().naRoda!.firstWhere((entry) => entry.pericope == 'P02');
    final asked = harness.room.calls.length;
    harness.room.reachable = false;

    tablet.notifier.openTheEntry(p02);
    await waitFor(
      'the room to be asked for P02',
      () => harness.room.calls.skip(asked).contains('createSession'),
    );
    await settle();
    await settle();

    expect(
      read().station,
      isA<Canvas>(),
      reason:
          'a retomada da P02 sem rede refazia a Escolha sem roda e sem a P01',
    );
    expect(read().sessionId, tablet.p01);
    expect(read().pericope, 'P01');
    expect(read().coverage.engaged, 2);
  });

  test('the pill of the passage left asks the room as any pill, and with no '
      'network lays that passage back instead of losing it', () async {
    final tablet = await _onTheChoiceFromP01();
    final harness = tablet.harness;
    final read = tablet.read;
    final p01 = read().naRoda!.firstWhere((entry) => entry.pericope == 'P01');
    final asked = harness.room.calls.length;
    harness.room.reachable = false;

    tablet.notifier.openTheEntry(p01);
    await waitFor(
      'the room to be asked for P01',
      () => harness.room.calls.skip(asked).contains('createSession'),
    );
    await settle();
    await settle();

    expect(
      harness.room.calls.skip(asked),
      contains('createSession'),
      reason: 'a pílula da passagem deixada não perguntava à sala',
    );
    expect(
      read().station,
      isA<Canvas>(),
      reason:
          'sem rede, a pílula da P01 deixada caía na Escolha sem roda e '
          'sem volta',
    );
    expect(read().sessionId, tablet.p01);
    expect(read().pericope, 'P01');
    expect(read().coverage.engaged, 2);
  });

  test('the pill of the passage left whose resume the room refuses lays that '
      'passage back, never an empty Choice', () async {
    final tablet = await _onTheChoiceFromP01();
    final harness = tablet.harness;
    final read = tablet.read;
    final p01 = read().naRoda!.firstWhere((entry) => entry.pericope == 'P01');
    final asked = harness.room.calls.length;
    harness.room.failCreateOnceWith = Refused(RefusalCode.unnamed(400));

    tablet.notifier.openTheEntry(p01);
    await waitFor(
      'the room to be asked for P01',
      () => harness.room.calls.skip(asked).contains('createSession'),
    );
    await settle();
    await settle();

    expect(
      read().station,
      isA<Canvas>(),
      reason:
          'a retomada recusada da P01 deixada refazia a Escolha e perdia a '
          'passagem',
    );
    expect(read().sessionId, tablet.p01);
    expect(read().pericope, 'P01');
    expect(read().coverage.engaged, 2);
  });

  test(
    'the pill of the passage left whose session the facilitator reset '
    'opens on the session the room returns, never on the canvas left',
    () async {
      final tablet = await _onTheChoiceFromP01();
      final harness = tablet.harness;
      final read = tablet.read;
      final p01 = read().naRoda!.firstWhere((entry) => entry.pericope == 'P01');
      harness.room.forgetTheSession(tablet.p01);
      harness.room.nextCoverage = coverage(engaged: 0, surfaced: 3);

      tablet.notifier.openTheEntry(p01);
      await waitFor(
        'P01 to open on the room\'s new session',
        () =>
            read().sessionId != null &&
            read().sessionId != tablet.p01 &&
            read().voice == VoiceState.invite,
      );

      expect(read().sessionId, harness.room.sessionIds.last);
      expect(read().pericope, 'P01');
      expect(
        read().coverage.engaged,
        0,
        reason: 'a tela da P01 deixada voltava sobre a sessão zerada',
      );
      expect(read().passageLeft, isNull);
      expect(read().leftEntry, isNull);
    },
  );

  test('the pill of a passage left with no session that cannot open rests on '
      'the Choice with the way back still there', () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);
    await notifier.abrirEscolha();
    await waitFor('the Choice to list its entries', () => read().entriesOpen);
    harness.room.failCreateOnceWith = const NetworkFailed('sem rede');
    await notifier.goConversa(book: 'Ruth', pericope: 'P01');
    await waitFor(
      'P01 to rest with no session',
      () =>
          read().station is Canvas &&
          read().sessionId == null &&
          !read().awaitingTheGuide,
    );
    notifier.leaveThePassage();
    await waitFor(
      'the way back to P01 to be live',
      () => read().entriesOpen && read().theWayBackIsLive,
    );
    final p01 = read().naRoda!.firstWhere((entry) => entry.pericope == 'P01');
    final asked = harness.room.calls.length;
    harness.room.failCreateOnceWith = const NetworkFailed('sem rede');

    notifier.openTheEntry(p01);
    await waitFor(
      'the room to be asked for P01',
      () => harness.room.calls.skip(asked).contains('createSession'),
    );
    await settle();
    await settle();

    expect(
      read().station,
      isA<Menu>(),
      reason:
          'a pílula da P01 deixada sem sessão prendia a equipe num círculo '
          'sem sessão',
    );
    expect(read().sessionId, isNull);
    expect(
      read().isTheEntryLeft(p01),
      isTrue,
      reason: 'a P01 deixada perdia a marca e a volta',
    );
    expect(read().theWayBackIsLive, isTrue);
  });

  test('a passage left whose session the room lets go is not laid back by a '
      'pill that cannot open', () async {
    final tablet = await _onTheChoiceFromP01();
    final harness = tablet.harness;
    final read = tablet.read;
    final row = await harness.takes.enqueue(
      harness.recorder.aFile('parte-da-p01'),
      sessionId: tablet.p01,
      kind: 'ensaio',
      scope: 'parte-1',
      passNumber: 1,
      chunkIndex: 1,
    );
    harness.room.forgetTheSession(tablet.p01);
    await harness.takes.dueAgain(row.id);
    await harness.takes.flush();
    await waitFor('the room to let P01 go', () => read().leftEntry == null);
    final p02 = read().naRoda!.firstWhere((entry) => entry.pericope == 'P02');
    final asked = harness.room.calls.length;
    harness.room.reachable = false;

    tablet.notifier.openTheEntry(p02);
    await waitFor(
      'the room to be asked for P02',
      () => harness.room.calls.skip(asked).contains('createSession'),
    );
    await settle();
    await settle();

    expect(
      read().station,
      isA<Menu>(),
      reason: 'a sessão que a sala largou voltava como a passagem deixada',
    );
    expect(read().sessionId, isNull);
  });

  test(
    'a warning the passage left stood under comes back with its canvas',
    () async {
      final harness = SalaHarness()
        ..room.serverStatus = 'needs_person'
        ..room.serverHalt = HaltKind.warning;
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);
      await enterThePassage(notifier, read, 'P01');
      await waitFor(
        'P01 to stand under the warning',
        () => read().sessionId != null && read().warning,
      );
      notifier.leaveThePassage();
      await waitFor(
        'the way back to P01 to be live',
        () => read().entriesOpen && read().theWayBackIsLive,
      );
      harness.room.reachable = false;

      await notifier.returnToTheLeftEntry();
      await settle();

      expect(read().station, isA<Canvas>());
      expect(
        read().warning,
        isTrue,
        reason: 'a P01 voltava sem a marca do aviso que ainda estava de pé',
      );
    },
  );

  test('a passage resumed from the Choice lets the one left before it go, so '
      'its session going away lands on the Choice', () async {
    final harness = SalaHarness();
    harness.emAberto.rows['Ruth/P02/pt'] = const ResumePoint(
      sessionId: 'sessao-da-p02',
      stage: SalaStage.conversa,
    );
    final tablet = await _onTheChoiceFromP01(harness);
    final read = tablet.read;
    final notifier = tablet.notifier;
    final p02 = read().naRoda!.firstWhere((entry) => entry.pericope == 'P02');
    notifier.openTheEntry(p02);
    await waitFor(
      'P02 to resume',
      () =>
          read().sessionId == 'sessao-da-p02' &&
          read().voice == VoiceState.invite,
    );
    await settle();
    harness.room.forgetTheSession('sessao-da-p02');

    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await waitFor(
      'the Choice to come back',
      () => read().station is Menu || read().sessionId == tablet.p01,
    );
    await settle();

    expect(
      read().station,
      isA<Menu>(),
      reason:
          'a P02 que a sala perdeu trazia de volta a P01 deixada antes dela',
    );
    expect(read().sessionId, isNull);
  });

  test('a leave from a passage resumed any other way lands on the Choice, '
      'never on the passage left before it', () async {
    final harness = SalaHarness();
    harness.emAberto.rows['Ruth/P02/pt'] = const ResumePoint(
      sessionId: 'sessao-da-p02',
      stage: SalaStage.conversa,
    );
    final tablet = await _onTheChoiceFromP01(harness);
    final read = tablet.read;
    final notifier = tablet.notifier;
    await notifier.goConversa(book: 'Ruth', pericope: 'P02', language: 'pt');
    await waitFor(
      'P02 to resume',
      () =>
          read().sessionId == 'sessao-da-p02' &&
          read().voice == VoiceState.invite,
    );

    notifier.leaveThePassage();
    await settle();

    expect(
      read().station,
      isA<Menu>(),
      reason: 'sair da P02 caía na P01 deixada antes dela',
    );
  });

  test('a room rebuilt after a leave keeps nothing of the passage left, so a '
      'pill that cannot open rests on the Choice', () async {
    final tablet = await _onTheChoiceFromP01();
    final harness = tablet.harness;
    final container = tablet.container;
    SalaSessionState read() => container.read(salaSessionProvider);

    container.invalidate(salaSessionProvider);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.openTheRoom();
    await waitFor('the Choice to list its entries', () => read().entriesOpen);
    final p02 = read().naRoda!.firstWhere((entry) => entry.pericope == 'P02');
    final asked = harness.room.calls.length;
    harness.room.reachable = false;

    notifier.openTheEntry(p02);
    await waitFor(
      'the room to be asked for P02',
      () => harness.room.calls.skip(asked).contains('createSession'),
    );
    await settle();
    await settle();

    expect(
      read().station,
      isA<Menu>(),
      reason: 'a sala refeita trazia de volta a P01 da vida anterior',
    );
    expect(read().sessionId, isNull);
  });

  test('«hear again» on the passage laid back with no network plays its last '
      'line again, asking the room for nothing', () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);
    await enterThePassage(notifier, read, 'P01');
    await waitFor(
      'P01 to speak its opening',
      () =>
          read().voice == VoiceState.invite && harness.voice.played.isNotEmpty,
    );
    final opening = harness.voice.played.last;
    notifier.leaveThePassage();
    await waitFor(
      'the way back to P01 to be live',
      () => read().entriesOpen && read().theWayBackIsLive,
    );
    harness.room.reachable = false;
    await notifier.returnToTheLeftEntry();
    await settle();
    final heard = harness.voice.played.length;
    final asked = harness.room.calls.length;

    await notifier.hearAgain();
    await settle();

    expect(
      harness.voice.played.skip(heard),
      [opening],
      reason:
          'a P01 voltava sem a sua última fala e pedia à sala para repeti-la',
    );
    expect(harness.room.calls.skip(asked), isEmpty);
  });

  test('a passage created from the Choice lets the one left before it go, so '
      'its session going away lands on the Choice', () async {
    final tablet = await _onTheChoiceFromP01();
    final harness = tablet.harness;
    final read = tablet.read;
    final notifier = tablet.notifier;
    final p02 = read().naRoda!.firstWhere((entry) => entry.pericope == 'P02');
    notifier.openTheEntry(p02);
    await waitFor(
      'P02 to open',
      () =>
          read().sessionId != null &&
          read().sessionId != tablet.p01 &&
          read().voice == VoiceState.invite,
    );
    await settle();
    harness.room.forgetTheSession(read().sessionId!);

    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await waitFor(
      'the Choice to come back',
      () => read().station is Menu || read().sessionId == tablet.p01,
    );
    await settle();

    expect(
      read().station,
      isA<Menu>(),
      reason: 'a P02 criada que a sala perdeu trazia de volta a P01',
    );
    expect(read().sessionId, isNull);
  });

  test('The passage left comes back on its Canvas with its session and the '
      'warning it stood under, and arms the Watch', () {
    final (machine, effects) = reduce(
      const Machine(station: Canvas(), generation: 4),
      const TheLeftPassageReturns('s2', warned: true),
    );

    expect(machine.session, 's2');
    expect(machine.halt, isA<Warning>());
    expect(machine.station, const Canvas());
    expect(effects, contains(const ArmTheWatch()));
  });

  test('The passage left with no warning comes back with none', () {
    final (machine, _) = reduce(
      const Machine(station: Canvas(), generation: 4),
      const TheLeftPassageReturns('s2'),
    );

    expect(machine.session, 's2');
    expect(machine.halt, isA<NoHalt>());
  });

  test('What waits under the Choice is the machine\'s: a failed resume, a pill '
      'that cannot open and an open that brings no session return to it', () {
    const left = LeftEntry(
      book: 'Ruth',
      pericope: 'P01',
      session: 's1',
      language: 'pt',
    );
    final (waiting, _) = reduce(
      const Machine(generation: 4),
      const TheEntryWaits(left),
    );

    for (final failed in const <MachineEvent>[
      TheResumeFailed(),
      ThePassageCannotOpen(),
      TheOpenBroughtNoSession(),
    ]) {
      final (machine, effects) = reduce(
        waiting.copyWith(station: const Canvas()),
        failed,
      );
      expect(effects, contains(const ReturnToTheEntryLeft(left)));
      expect(effects, isNot(contains(const OpenTheChoice())));
      expect(effects, isNot(contains(const RefuseThePassage())));
      expect(machine.waiting, isNull);
    }
    for (final (failed, toTheChoice) in const <(MachineEvent, Effect)>[
      (TheResumeFailed(), OpenTheChoice()),
      (ThePassageCannotOpen(), RefuseThePassage()),
      (TheOpenBroughtNoSession(), RestOnTheChoice()),
    ]) {
      final (_, effects) = reduce(
        const Machine(station: Canvas(), generation: 4),
        failed,
      );
      expect(effects, contains(toTheChoice));
    }
  });

  test('What waits goes when the room lets its session go, and when the team '
      'takes the way back to it', () {
    const left = LeftEntry(book: 'Ruth', pericope: 'P01', session: 's1');
    final waiting = const Machine(generation: 4).copyWith(waiting: left);

    for (final gone in const <MachineEvent>[
      TheSessionLetGo('s1'),
      TheWayBackTaken(left),
      TheLeftPassageReturns('s1'),
    ]) {
      expect(reduce(waiting, gone).$1.waiting, isNull);
    }
    expect(reduce(waiting, const TheSessionLetGo('s2')).$1.waiting, left);
  });

  test(
    'the chevron tapped while a pill\'s open is in flight still lands on '
    'the passage that opened, as hers adopts what the open answers',
    () async {
      final tablet = await _onTheChoiceFromP01();
      final harness = tablet.harness;
      final read = tablet.read;
      final p02 = read().naRoda!.firstWhere((entry) => entry.pericope == 'P02');
      harness.room.holdNextCreate();

      tablet.notifier.openTheEntry(p02);
      await waitFor('the open to be in flight', () => harness.room.createHeld);
      await tablet.notifier.returnToTheLeftEntry();
      harness.room.finishHeldCreate();
      await waitFor(
        'P02 to open',
        () => read().pericope == 'P02' && read().voice == VoiceState.invite,
      );

      expect(read().station, isA<Canvas>());
      expect(read().sessionId, isNot(tablet.p01));
      expect(read().sessionId, harness.room.sessionIds.last);
    },
  );

  test(
    'an Error thrown in the open raises no person sign and frees the '
    'flight, resting on the new passage as hers does after a failed kickoff',
    () async {
      final tablet = await _onTheChoiceFromP01();
      final harness = tablet.harness;
      final read = tablet.read;
      final p02 = read().naRoda!.firstWhere((entry) => entry.pericope == 'P02');
      harness.room.throwOn['openSession'] = StateError('the player broke');

      tablet.notifier.openTheEntry(p02);
      await waitFor(
        'the open to rest on P02',
        () =>
            read().pericope == 'P02' &&
            read().voice == VoiceState.invite &&
            read().machine.inFlight == null,
      );

      expect(read().needsPerson, isFalse);
      expect(read().openingEntry, isNull);
      expect(harness.room.calls, isNot(contains('lookAtTheTurn')));
    },
  );

  test('an Error thrown in a spoken turn still raises the person sign and '
      'looks at nothing', () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);
    await enterThePassage(notifier, read, 'P01');
    await waitFor(
      'P01 to open',
      () => read().sessionId != null && read().voice == VoiceState.invite,
    );
    harness.room.throwOn['sendTurn'] = StateError('the build broke');

    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await waitFor('the person sign', () => read().needsPerson);

    expect(harness.room.calls, isNot(contains('lookAtTheTurn')));
  });

  group('the way back from the Choice', () {
    const held = LeftEntry(pericope: 'P01', book: 'Ruth', session: 's1');
    const noSession = LeftEntry(pericope: 'P01', book: 'Ruth');

    SalaSessionState choice({
      LeftEntry entry = held,
      bool holding = true,
      bool wheelRead = false,
      bool voiceBusy = false,
      Halt halt = const NoHalt(),
    }) => SalaSessionState(
      leftEntry: entry,
      awaitingTheGuide: voiceBusy,
      naRoda: wheelRead
          ? const [Passagem(pericope: 'P01', audioUrl: '/voice/p01')]
          : null,
      machine: Machine(waiting: holding ? entry : null, halt: halt),
    );

    test('a held passage shows it at once and keeps it live while the voice '
        'is busy', () {
      for (final busy in [false, true]) {
        final state = choice(voiceBusy: busy);

        expect(state.theWayBackIsOffered, isTrue);
        expect(state.theWayBackIsLive, isTrue, reason: 'voiceBusy: $busy');
      }
    });

    test('the person sign hides it, held or not', () {
      for (final holding in [true, false]) {
        final state = choice(
          entry: holding ? held : noSession,
          holding: holding,
          wheelRead: true,
          halt: const Blocking(),
        );

        expect(state.theWayBackIsOffered, isFalse, reason: 'held: $holding');
        expect(state.theWayBackIsLive, isFalse, reason: 'held: $holding');
      }
    });

    test('an entry left with no session waits for the Wheel, then for the '
        'voice at rest', () {
      final unread = choice(entry: noSession, holding: false);
      final busy = choice(
        entry: noSession,
        holding: false,
        wheelRead: true,
        voiceBusy: true,
      );
      final quiet = choice(entry: noSession, holding: false, wheelRead: true);

      expect(unread.theWayBackIsOffered, isFalse);
      expect(busy.theWayBackIsOffered, isTrue);
      expect(busy.theWayBackIsLive, isFalse);
      expect(quiet.theWayBackIsLive, isTrue);
    });
  });
}
