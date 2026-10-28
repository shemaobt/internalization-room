import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/book_names.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/domain/station.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show byLabel, settle, theChoiceOffersAPassage;

const _aPanorama = Passagem(
  pericope: 'OV-Ruth',
  audioUrl: '/voice/panorama',
  kind: PassagemKind.panorama,
  book: 'Ruth',
);

final _theSign = byLabel(circleLabelFor('needsPerson', testLanguage));
final _theChoicesCircle = byLabel(
  escolhaLabelFor('readTheWheel', testLanguage),
);

Future<ProviderContainer> _aBrokenBuild(
  WidgetTester tester,
  SalaHarness harness,
) async {
  final container = harness.container();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const SalaApp(built: false),
    ),
  );
  await tester.pump();
  return container;
}

Future<void> _theSignIsTappedAway(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 1700));
  await tester.tap(_theSign);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1700));
  await tester.pump();
}

void main() {
  group('a build that cannot reach the room', () {
    testWidgets(
      'a broken build shows the person sign from its first frame and asks the room nothing',
      (tester) async {
        final harness = SalaHarness(filaEmMemoria: true);
        final container = await _aBrokenBuild(tester, harness);

        expect(_theSign, findsOneWidget);
        expect(
          byLabel(codigoLabelFor('preparing', testLanguage)),
          findsNothing,
        );
        expect(harness.room.calls, isEmpty);

        await tester.pump(const Duration(seconds: 2));
        expect(_theSign, findsOneWidget);
        expect(harness.room.personsAsked, 0);
        closeTheRoom(container);
      },
    );

    testWidgets(
      'a tap clears the broken build\'s sign and the Choice shows nothing to open',
      (tester) async {
        final harness = SalaHarness(filaEmMemoria: true);
        final container = await _aBrokenBuild(tester, harness);

        await _theSignIsTappedAway(tester);

        expect(_theSign, findsNothing);
        expect(find.text('Escolha a passagem'), findsOneWidget);
        expect(_theChoicesCircle, findsOneWidget);
        expect(find.text(bookNameFor('Ruth', testLanguage)), findsNothing);
        expect(harness.room.calls, isNot(contains('servedBooks')));
        closeTheRoom(container);
      },
    );

    testWidgets(
      'on a broken build the Choice\'s tap brings the sign back before any wait',
      (tester) async {
        final harness = SalaHarness(filaEmMemoria: true);
        final container = await _aBrokenBuild(tester, harness);
        await _theSignIsTappedAway(tester);
        harness.room.throwOn['servedBooks'] = StateError(
          'BACKEND_URL is missing',
        );

        await tester.tap(_theChoicesCircle);
        await tester.pump();

        expect(_theSign, findsOneWidget);
        expect(container.read(salaSessionProvider).awaitingTheGuide, isFalse);
        closeTheRoom(container);
      },
    );
  });

  group('an Error in anything the room hands off', () {
    test(
      'a notifier whose build has no address shows the sign at the Wheel read, with no wait',
      () async {
        dotenv.testLoad(fileInput: '');
        addTearDown(dotenv.clean);
        final sent = <http.BaseRequest>[];
        final repository = RoomRepository(
          client: MockClient((request) async {
            sent.add(request);
            return http.Response('{}', 200);
          }),
        );
        final harness = SalaHarness();
        final container = ProviderContainer(
          overrides: [
            ...harness.overrides,
            roomRepositoryProvider.overrideWithValue(repository),
          ],
        );
        addTearDown(container.dispose);

        container.read(salaSessionProvider.notifier).escolhaTap();
        await settle(Duration.zero);

        final state = container.read(salaSessionProvider);
        expect(state.needsPerson, isTrue);
        expect(state.awaitingTheGuide, isFalse);
        expect(sent, isEmpty);
      },
    );

    test(
      'a hand-off whose body throws a StateError shows the sign and calls nobody',
      () async {
        final harness = SalaHarness();
        harness.room.throwOn['servedBooks'] = StateError('x');
        final container = harness.container();
        addTearDown(container.dispose);

        container.read(salaSessionProvider.notifier).escolhaTap();
        await settle();

        final state = container.read(salaSessionProvider);
        expect(state.needsPerson, isTrue);
        expect(state.awaitingTheGuide, isFalse);
        expect(harness.room.personsAsked, 0);
      },
    );

    test(
      'a Panorama pill whose create throws leaves the team on the Choice, not on the sign, and its pill asks again',
      () async {
        final harness = SalaHarness()..room.passages = const [_aPanorama];
        final container = harness.container();
        addTearDown(container.dispose);
        final notifier = container.read(salaSessionProvider.notifier);
        SalaSessionState read() => container.read(salaSessionProvider);
        int said() =>
            harness.voice.played.length +
            harness.voice.assets.length +
            harness.voice.fixedLines.length;
        await notifier.abrirEscolha();
        await theChoiceOffersAPassage(container);
        final quiet = said();
        harness.room.throwOn['createSession'] = StateError('x');

        notifier.openTheEntry(read().naRoda!.first);
        await settle();

        expect(
          read().needsPerson,
          isFalse,
          reason: 'o create do Panorama que lançava um erro levantava o sinal',
        );
        expect(
          read().station,
          isA<Menu>(),
          reason: 'a equipe ficava no Panorama sem sessão',
        );
        expect(read().entriesOpen, isTrue);
        expect(read().awaitingTheGuide, isFalse);
        expect(said(), quiet);
        expect(harness.room.personsAsked, 0);

        harness.room.throwOn.remove('createSession');
        notifier.openTheEntry(read().naRoda!.first);
        await waitFor(
          'the Panorama to open',
          () => read().panoramaSessionId != null,
        );

        expect(read().station, isA<Panorama>());
      },
    );

    test(
      'a passage pill whose create throws leaves the team on the Choice, not on the sign, and its pill asks again',
      () async {
        final harness = SalaHarness();
        final container = harness.container();
        addTearDown(container.dispose);
        final notifier = container.read(salaSessionProvider.notifier);
        SalaSessionState read() => container.read(salaSessionProvider);
        int said() =>
            harness.voice.played.length +
            harness.voice.assets.length +
            harness.voice.fixedLines.length;
        await notifier.abrirEscolha();
        await theChoiceOffersAPassage(container);
        final p01 = read().naRoda!.firstWhere(
          (entry) => entry.pericope == 'P01',
        );
        final quiet = said();
        harness.room.throwOn['createSession'] = StateError('x');

        notifier.openTheEntry(p01);
        await settle();

        expect(
          read().needsPerson,
          isFalse,
          reason: 'o create que lançava um erro levantava o sinal da pessoa',
        );
        expect(
          read().station,
          isA<Menu>(),
          reason: 'a equipe ficava na tela de uma passagem sem sessão',
        );
        expect(read().entriesOpen, isTrue);
        expect(read().awaitingTheGuide, isFalse);
        expect(said(), quiet);

        harness.room.throwOn.remove('createSession');
        notifier.openTheEntry(p01);
        await waitFor('P01 to open', () => read().sessionId != null);

        expect(read().station, isA<Canvas>());
      },
    );

    test(
      'a gesture awaited directly whose body throws a StateError shows the sign and the await does not throw',
      () async {
        final harness = SalaHarness();
        harness.room.throwOn['servedBooks'] = StateError('x');
        final container = harness.container();
        addTearDown(container.dispose);

        await expectLater(
          container.read(salaSessionProvider.notifier).abrirEscolha(),
          completes,
        );

        expect(container.read(salaSessionProvider).needsPerson, isTrue);
      },
    );

    test(
      'an Error handed off inside a gesture of its own is reported once',
      () async {
        final logged = <String>[];
        final print = debugPrint;
        debugPrint = (message, {wrapWidth}) => logged.add(message ?? '');
        addTearDown(() => debugPrint = print);
        final harness = SalaHarness();
        harness.room.throwOn['servedBooks'] = StateError('one defect');
        final container = harness.container();
        addTearDown(container.dispose);

        container.read(salaSessionProvider.notifier).escolhaTap();
        await settle();

        expect(
          logged.where((line) => line.contains('one defect')),
          hasLength(1),
        );
      },
    );

    test(
      'a hand-off whose body throws an Exception keeps today\'s path',
      () async {
        final harness = SalaHarness(
          busyCeiling: const Duration(milliseconds: 200),
        );
        harness.room.throwOn['servedBooks'] = const FormatException('x');
        final container = harness.container();
        addTearDown(container.dispose);

        container.read(salaSessionProvider.notifier).escolhaTap();
        await settle(Duration.zero);
        expect(container.read(salaSessionProvider).needsPerson, isFalse);

        await settle(const Duration(milliseconds: 300));
        final state = container.read(salaSessionProvider);
        expect(state.needsPerson, isFalse);
        expect(state.awaitingTheGuide, isFalse);
      },
    );

    test('a RoomFailure thrown by a hand-off never raises the sign', () async {
      final harness = SalaHarness(
        busyCeiling: const Duration(milliseconds: 200),
      );
      harness.room.throwOn['servedBooks'] = const Refused(
        RefusalCode.forbidden,
      );
      final container = harness.container();
      addTearDown(container.dispose);

      container.read(salaSessionProvider.notifier).escolhaTap();
      await settle(const Duration(milliseconds: 300));

      expect(container.read(salaSessionProvider).needsPerson, isFalse);
    });

    test(
      'a container disposed under a hand-off that throws an Error dispatches nothing',
      () async {
        final logged = <String>[];
        final print = debugPrint;
        debugPrint = (message, {wrapWidth}) => logged.add(message ?? '');
        addTearDown(() => debugPrint = print);
        final harness = SalaHarness();
        harness.room.throwOn['servedBooks'] = StateError('a late defect');
        final container = harness.container();

        container.read(salaSessionProvider.notifier).escolhaTap();
        container.dispose();
        await settle();

        expect(logged.where((line) => line.contains('a late defect')), isEmpty);
      },
    );

    test(
      'an Error that lands after its Life ended raises nothing in the next one',
      () async {
        final logged = <String>[];
        final print = debugPrint;
        debugPrint = (message, {wrapWidth}) => logged.add(message ?? '');
        addTearDown(() => debugPrint = print);
        final harness = SalaHarness();
        final container = harness.container();
        addTearDown(container.dispose);
        harness.voice
          ..holdNextFetch()
          ..readyThrows = StateError('of the life before');
        unawaited(
          container.read(salaSessionProvider.notifier).goConversa(book: 'Ruth'),
        );
        await waitFor(
          'a abertura pedir a sua fala',
          () => harness.voice.fetched.isNotEmpty,
        );

        container.invalidate(salaSessionProvider);
        container.read(salaSessionProvider);
        await settle();
        harness.voice.finishHeldFetch();
        await settle(const Duration(milliseconds: 300));

        expect(container.read(salaSessionProvider).needsPerson, isFalse);
        expect(
          logged.where((line) => line.contains('of the life before')),
          isEmpty,
        );
      },
    );
  });
}
