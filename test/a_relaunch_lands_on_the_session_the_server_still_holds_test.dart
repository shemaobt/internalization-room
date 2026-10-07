import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/current_session_ledger.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/station.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
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

  List<String> get said => [...harness.voice.played, ...harness.voice.assets];

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
    currentSession: CurrentSessionLedger(home: () async => home),
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

Future<_Tablet> _relaunch(_Tablet tablet, {String? lingua}) async {
  final (harness, container) = await relaunch(
    tablet.harness,
    tablet.container,
    lingua: lingua,
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
      pericope: 'panorama',
      audioUrl: '/voice/panorama',
      kind: PassagemKind.panorama,
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
      'offers «Ouvir de novo», which plays the room\'s line said again',
      () async {
        expect(again.state.canHearAgain, isTrue);

        await again.notifier.hearAgain();
        await waitFor(
          'the last line to be said again',
          () => again.harness.voice.played.contains(deNovoUrl),
        );

        expect(again.harness.room.sessionsSaidAgain, [session]);
      },
    );
  });

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

  test('a relaunch in the Rehearsal lands on the Rehearsal', () async {
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
    await gravarUmaParteDoEnsaio(it);
    await settle();

    final again = await _relaunch(first);
    await again.notifier.openTheRoom();
    await waitFor(
      'the team to land on the Rehearsal',
      () => again.state.sessionId == session && again.state.station is Ensaio,
    );
    await settle();

    expect(again.state.station, isA<Ensaio>());
    expect(again.said, isEmpty);
  });

  group('a relaunch into a session the room no longer knows', () {
    late _Tablet again;

    setUp(() async {
      final first = await _inP01();
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
      expect(
        await again.harness.emAbertoNoDisco!.startedIn('Ruth'),
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
    again.harness.network.reachable = false;
    again.harness.room.reachable = false;
    await again.notifier.openTheRoom();
    await waitFor('the room to be out of reach', () => again.state.offline);
    await settle();

    expect(stations, everyElement(isA<Menu>()));
    expect(again.state.station, isA<Menu>());

    again.harness.network.reachable = true;
    again.harness.room.reachable = true;
    again.notifier.retryNow();
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

    test('after the Closing, inside its linger', () async {
      final it = await umEnsaioDeTresPartesContadoInteiro();
      it.harness.room.verdictChecked = true;
      await pedirOVeredito(it);
      await it.sala.aprovarRascunhoFinal();
      await waitFor('the Closing', () => it.estado.station is Fim);
      await settle();

      await relaunchedOnTheChoice(_Tablet(it.harness, it.container));
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

    test('after the Panorama', () async {
      final tablet = await _aTablet();
      await _intoThePanorama(tablet);

      await relaunchedOnTheChoice(tablet);
    });

    test(
      'after a launch that lost the network and then the Panorama',
      () async {
        final first = await _inP01();
        final offline = await _relaunch(first);
        offline.harness.network.reachable = false;
        offline.harness.room.reachable = false;
        await offline.notifier.openTheRoom();
        await waitFor(
          'the room to be out of reach',
          () => offline.state.offline,
        );
        offline.harness.network.reachable = true;
        offline.harness.room.reachable = true;
        offline.notifier.retryNow();
        await _theChoiceShowsItsWheel(offline);
        await _intoThePanorama(offline);

        await relaunchedOnTheChoice(offline);
      },
    );

    test('in another language', () async {
      final tablet = await _inP01();
      final again = await _relaunch(tablet, lingua: 'en');
      final reads = again.asked('fetchState');
      await again.notifier.openTheRoom();
      await _theChoiceShowsItsWheel(again);
      await settle();

      expect(again.state.station, isA<Menu>());
      expect(again.asked('fetchState'), reads);
    });
  });

  test(
    'opening the room again while the relaunch\'s read is in the air changes nothing',
    () async {
      final first = await _inP01();
      final session = first.state.sessionId!;

      final again = await _relaunch(first);
      final before = again.harness.room.calls.length;
      again.harness.room.holdNextState();
      final launched = again.notifier.openTheRoom();
      await settle();
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
}
