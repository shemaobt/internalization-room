import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/linked_team.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/store_build_gate.dart';
import 'package:internalization_room/features/sala/domain/minimum_build.dart';
import 'package:internalization_room/features/sala/domain/ports.dart';
import 'package:internalization_room/features/sala/presentation/widgets/codigo_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/conversa_view.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';

const _line = 'Há uma versão nova do aplicativo. Toquem para atualizar.';
const _theChoice = 'Escolha a passagem';
const _button = 'Atualizar';
final _googlePlay = Uri.parse(
  'https://play.google.com/store/apps/details?id=com.shema.internalization_room',
);
final _appStore = Uri.parse('https://apps.apple.com/app/id6823303385');

MinimumBuilds _minimum({int ios = 0, int android = 0}) =>
    MinimumBuilds(ios: ios, android: android);

Future<ProviderContainer> _pumpWithBuild(
  WidgetTester tester,
  SalaHarness harness, {
  required int build,
  required List<Uri> opened,
}) async {
  final container = ProviderContainer(
    overrides: [
      ...harness.overrides,
      thisBuildProvider.overrideWithValue(build),
      openTheStoreProvider.overrideWithValue((uri) async => opened.add(uri)),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
  return container;
}

SalaHarness _roomWhoseMinimumIs(
  MinimumBuilds minimum, {
  String? lingua = testLanguage,
}) {
  final harness = SalaHarness(lingua: lingua);
  harness.room.minimumBuildsAnswer = Answered(minimum);
  return harness;
}

Future<void> _onAnIpad(Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

Future<void> _resume(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUpAll(() {
    dotenv.testLoad(fileInput: 'BACKEND_URL=http://sala.local');
  });

  group('a build below the minimum', () {
    testWidgets('an android build below the minimum shows the update screen '
        'at launch', (tester) async {
      final harness = _roomWhoseMinimumIs(_minimum(android: 7));

      await _pumpWithBuild(tester, harness, build: 6, opened: []);

      expect(find.text(_line), findsOneWidget);
      expect(find.text(_theChoice), findsNothing);
    });

    testWidgets("a tap on the update screen's button opens the app's Google "
        'Play listing', (tester) async {
      final opened = <Uri>[];
      final harness = _roomWhoseMinimumIs(_minimum(android: 7));
      await _pumpWithBuild(tester, harness, build: 6, opened: opened);

      await tester.tap(find.text(_button));
      await tester.pump();

      expect(opened, [_googlePlay]);
    });

    testWidgets('an iPad below the minimum opens the App Store listing', (
      tester,
    ) async {
      final opened = <Uri>[];
      await _onAnIpad(() async {
        final harness = _roomWhoseMinimumIs(_minimum(ios: 7));
        await _pumpWithBuild(tester, harness, build: 6, opened: opened);

        expect(find.text(_line), findsOneWidget);
        await tester.tap(find.text(_button));
        await tester.pump();
      });

      expect(opened, [_appStore]);
    });

    testWidgets("the minimum that counts is the tablet's own platform's", (
      tester,
    ) async {
      final androidHarness = _roomWhoseMinimumIs(_minimum(ios: 9, android: 5));
      await _pumpWithBuild(tester, androidHarness, build: 6, opened: []);
      expect(find.text(_theChoice), findsOneWidget);
      expect(find.text(_line), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await _onAnIpad(() async {
        final ipadHarness = _roomWhoseMinimumIs(_minimum(ios: 7, android: 5));
        await _pumpWithBuild(tester, ipadHarness, build: 6, opened: []);
        expect(find.text(_line), findsOneWidget);
      });
    });

    testWidgets('an unlinked tablet below the minimum shows the update screen '
        'instead of the claim code', (tester) async {
      final harness = SalaHarness(linkedAs: const RememberedLink());
      harness.room.minimumBuildsAnswer = Answered(_minimum(android: 7));

      await _pumpWithBuild(tester, harness, build: 6, opened: []);

      expect(find.text(_line), findsOneWidget);
      expect(find.byType(CodigoView), findsNothing);
    });

    testWidgets('the update screen speaks the room language', (tester) async {
      final harness = _roomWhoseMinimumIs(_minimum(android: 7), lingua: 'en');

      await _pumpWithBuild(tester, harness, build: 6, opened: []);

      expect(
        find.text('There is a new version of the app. Tap to update.'),
        findsOneWidget,
      );
      expect(find.text('Update'), findsOneWidget);
    });
  });

  group('a build at or above the minimum, or a read that fails', () {
    testWidgets('an app at the minimum opens normally', (tester) async {
      final harness = _roomWhoseMinimumIs(_minimum(android: 7));

      await _pumpWithBuild(tester, harness, build: 7, opened: []);

      expect(find.text(_theChoice), findsOneWidget);
      expect(find.text(_line), findsNothing);
    });

    testWidgets('an app above the minimum opens normally', (tester) async {
      final harness = _roomWhoseMinimumIs(_minimum(android: 7));

      await _pumpWithBuild(tester, harness, build: 8, opened: []);

      expect(find.text(_theChoice), findsOneWidget);
    });

    testWidgets('a version read that fails opens the app as before', (
      tester,
    ) async {
      final harness = SalaHarness();
      harness.room.minimumBuildsAnswer = const NetworkFailed('sem rede');

      await _pumpWithBuild(tester, harness, build: 6, opened: []);

      expect(find.text(_theChoice), findsOneWidget);
    });

    testWidgets('a version answer the tablet cannot read opens the app as '
        'before', (tester) async {
      final harness = SalaHarness();
      harness.room.minimumBuildsAnswer = const Refused(RefusalCode.unreadable);

      await _pumpWithBuild(tester, harness, build: 6, opened: []);

      expect(find.text(_theChoice), findsOneWidget);
    });

    testWidgets('a laptop build never sees the update screen', (tester) async {
      final harness = _roomWhoseMinimumIs(_minimum(android: 7));

      await _pumpWithBuild(tester, harness, build: 0, opened: []);

      expect(find.text(_theChoice), findsOneWidget);
      expect(find.text(_line), findsNothing);
      expect(harness.room.minimumBuildsAsked, 0);
    });
  });

  group('when the tablet reads, and that the screen stands', () {
    testWidgets('a version read that stalls does not hold the room back', (
      tester,
    ) async {
      final harness = _roomWhoseMinimumIs(_minimum(android: 7));
      harness.room.holdNextMinimumBuilds();

      await _pumpWithBuild(tester, harness, build: 6, opened: []);

      expect(harness.room.calls, contains('servedBooks'));
      expect(find.text(_theChoice), findsOneWidget);
      harness.room.releaseMinimumBuilds();
    });

    testWidgets('a held session at launch lands with no update screen at any '
        'moment, and the screen waits for the next Choice', (tester) async {
      final currentSession = FakeCurrentSessionLedger()
        ..held = const CurrentSession(
          sessionId: 'sessao-7',
          book: 'Ruth',
          pericope: 'P02',
          language: testLanguage,
        );
      final harness = SalaHarness(currentSession: currentSession);
      harness.room.minimumBuildsAnswer = Answered(_minimum(android: 7));
      final container = ProviderContainer(
        overrides: [
          ...harness.overrides,
          thisBuildProvider.overrideWithValue(6),
          openTheStoreProvider.overrideWithValue((uri) async {}),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const SalaApp()),
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        expect(find.text(_line), findsNothing);
      }

      expect(find.byType(ConversaView), findsOneWidget);
      expect(harness.room.calls, contains('fetchState'));

      await container.read(salaSessionProvider.notifier).abrirEscolha();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text(_line), findsOneWidget);
    });

    testWidgets('a minimum read that answers after the team opened a passage '
        'leaves the passage until the next Choice', (tester) async {
      final harness = _roomWhoseMinimumIs(_minimum(android: 7));
      harness.room.holdNextMinimumBuilds();
      final container = await _pumpWithBuild(
        tester,
        harness,
        build: 6,
        opened: [],
      );
      final notifier = container.read(salaSessionProvider.notifier);

      await notifier.goConversa(book: 'Ruth');
      await tester.pump(const Duration(milliseconds: 300));
      harness.room.releaseMinimumBuilds();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(_line), findsNothing);
      expect(find.byType(ConversaView), findsOneWidget);

      await notifier.abrirEscolha();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text(_line), findsOneWidget);
    });

    testWidgets('a minimum raised during a passage meets the team on its '
        'return to the Choice', (tester) async {
      final harness = _roomWhoseMinimumIs(_minimum());
      final container = await _pumpWithBuild(
        tester,
        harness,
        build: 6,
        opened: [],
      );
      expect(find.text(_theChoice), findsOneWidget);
      final notifier = container.read(salaSessionProvider.notifier);

      await notifier.goConversa(book: 'Ruth');
      await tester.pump(const Duration(milliseconds: 300));
      harness.room.minimumBuildsAnswer = Answered(_minimum(android: 7));
      expect(find.byType(ConversaView), findsOneWidget);
      expect(find.text(_line), findsNothing);

      await notifier.abrirEscolha();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text(_line), findsOneWidget);
    });

    testWidgets('a resume on the Choice reads the minimum again', (
      tester,
    ) async {
      final harness = _roomWhoseMinimumIs(_minimum());
      await _pumpWithBuild(tester, harness, build: 6, opened: []);
      expect(find.text(_theChoice), findsOneWidget);

      harness.room.minimumBuildsAnswer = Answered(_minimum(android: 7));
      await _resume(tester);

      expect(find.text(_line), findsOneWidget);
    });

    testWidgets('a resume in the middle of a passage never shows the update '
        'screen', (tester) async {
      final harness = _roomWhoseMinimumIs(_minimum());
      final container = await _pumpWithBuild(
        tester,
        harness,
        build: 6,
        opened: [],
      );
      await container
          .read(salaSessionProvider.notifier)
          .goConversa(book: 'Ruth');
      await tester.pump(const Duration(milliseconds: 300));

      harness.room.minimumBuildsAnswer = Answered(_minimum(android: 7));
      await _resume(tester);

      expect(find.text(_line), findsNothing);
      expect(find.byType(ConversaView), findsOneWidget);
    });

    testWidgets('the update screen stands once shown', (tester) async {
      final harness = _roomWhoseMinimumIs(_minimum(android: 7));
      await _pumpWithBuild(tester, harness, build: 6, opened: []);
      expect(find.text(_line), findsOneWidget);

      harness.room.minimumBuildsAnswer = const NetworkFailed('sem rede');
      await _resume(tester);

      expect(find.text(_line), findsOneWidget);
    });
  });
}
