import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/sala_colors.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show byLabel, enterThePassage, relaunch, settle;

Future<void> _catchUp(WidgetTester tester) async {
  await tester.runAsync(settle);
  await tester.pump(const Duration(milliseconds: 1500));
}

Future<void> _theThemeFinishes(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Brightness _statusBarGlyphs(WidgetTester tester) => tester
    .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find
          .ancestor(
            of: find.byType(Scaffold).first,
            matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
          )
          .first,
    )
    .value
    .statusBarIconBrightness!;

bool _selected(WidgetTester tester, String label) => isSemantics(
  isSelected: true,
).matches(tester.getSemantics(find.bySemanticsLabel(label)), {});

Color _ground(WidgetTester tester) =>
    SalaColors.of(tester.element(find.byType(Scaffold).first)).paper;

Future<ProviderContainer> _openTheChoice(
  WidgetTester tester,
  SalaHarness harness,
) async {
  final container = await pumpSala(tester, harness);
  await tester.pump(const Duration(milliseconds: 300));
  return container;
}

Future<void> _enter(
  WidgetTester tester,
  ProviderContainer container,
  String pericope,
) async {
  final notifier = container.read(salaSessionProvider.notifier);
  await tester.runAsync(
    () => enterThePassage(
      notifier,
      () => container.read(salaSessionProvider),
      pericope,
    ),
  );
  await _catchUp(tester);
}

Future<void> _leave(WidgetTester tester, ProviderContainer container) async {
  container.read(salaSessionProvider.notifier).leaveThePassage();
  await _catchUp(tester);
}

Future<ProviderContainer> _reopen(
  WidgetTester tester,
  SalaHarness harness,
  ProviderContainer container,
) async {
  await tester.pumpWidget(const SizedBox());
  final (_, next) = await relaunch(harness, container, tester: tester);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: next, child: const SalaApp()),
  );
  await tester.pump(const Duration(milliseconds: 300));
  return next;
}

void choiceTest(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(name, (tester) async {
      final voiceOver = tester.ensureSemantics();
      try {
        await body(tester);
      } finally {
        voiceOver.dispose();
      }
    });

void main() {
  void deviceIs(WidgetTester tester, {Locale? locale, Brightness? brightness}) {
    if (locale != null) {
      tester.platformDispatcher.localesTestValue = [locale];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    }
    if (brightness != null) {
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    }
  }

  choiceTest(
    'a fresh tablet set to English shows «PT» chosen and opens its first session '
    'in Portuguese',
    (tester) async {
      deviceIs(tester, locale: const Locale('en'));
      final harness = SalaHarness(filaEmMemoria: true, lingua: null);
      final container = await _openTheChoice(tester, harness);

      expect(_selected(tester, 'PT'), isTrue);
      expect(_selected(tester, 'EN'), isFalse);
      expect(find.text('Escolha a passagem'), findsOneWidget);

      await _enter(tester, container, 'P01');

      expect(harness.room.languagesSent, ['pt']);
    },
  );

  choiceTest(
    'tapping «EN» on the Choice opens the next passage in English, screen and voice',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true, lingua: null);
      final container = await _openTheChoice(tester, harness);

      await tester.tap(find.text('EN'));
      await _catchUp(tester);

      expect(_selected(tester, 'EN'), isTrue);
      expect(find.text('Choose the Passage'), findsOneWidget);

      await _enter(tester, container, 'P01');

      expect(harness.room.languagesSent.last, 'en');
      expect(byLabel(circleLabelFor('default', 'en')), findsOneWidget);
    },
  );

  choiceTest(
    '«EN» chosen on the Choice is still chosen after the app is closed and reopened',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true, lingua: null);
      final container = await _openTheChoice(tester, harness);

      await tester.tap(find.text('EN'));
      await _catchUp(tester);
      await _reopen(tester, harness, container);

      expect(_selected(tester, 'EN'), isTrue);
      expect(_selected(tester, 'PT'), isFalse);
    },
  );

  choiceTest(
    'an English session left for the Choice stays English after «PT» is tapped, and '
    'the next passage opens in Portuguese',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true, lingua: null);
      final container = await _openTheChoice(tester, harness);
      await tester.tap(find.text('EN'));
      await _catchUp(tester);
      await _enter(tester, container, 'P01');
      final english = container.read(salaSessionProvider).sessionId;
      await _leave(tester, container);

      await tester.tap(find.text('PT'));
      await _catchUp(tester);
      await tester.tap(byLabel(roomLabelFor('backToPassage', 'pt')));
      await _catchUp(tester);

      expect(container.read(salaSessionProvider).sessionId, english);
      expect(harness.room.languagesSent, ['en']);
      expect((await harness.currentSession.read())?.language, 'en');

      await _leave(tester, container);
      await _enter(tester, container, 'P02');

      expect(harness.room.languagesSent.last, 'pt');
    },
  );

  choiceTest(
    'a fresh tablet set to dark opens dark, the sun makes it light, and light '
    'outlives a reopen',
    (tester) async {
      deviceIs(tester, brightness: Brightness.dark);
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await _openTheChoice(tester, harness);

      expect(_ground(tester), SalaColors.dark.paper);

      await tester.tap(byLabel('Claro'));
      await _theThemeFinishes(tester);

      expect(_ground(tester), SalaColors.light.paper);

      await _reopen(tester, harness, container);

      expect(_ground(tester), SalaColors.light.paper);
    },
  );

  choiceTest(
    'a tablet set to Spanish opens Portuguese sessions until «EN» is chosen',
    (tester) async {
      deviceIs(tester, locale: const Locale('es'));
      final harness = SalaHarness(filaEmMemoria: true, lingua: null);
      final container = await _openTheChoice(tester, harness);

      await _enter(tester, container, 'P01');

      expect(harness.room.languagesSent, ['pt']);

      await _leave(tester, container);
      await tester.tap(find.text('EN'));
      await _catchUp(tester);
      await _enter(tester, container, 'P02');

      expect(harness.room.languagesSent.last, 'en');
    },
  );

  choiceTest('a fresh tablet set to light opens light, with the sun chosen', (
    tester,
  ) async {
    deviceIs(tester, brightness: Brightness.light);
    await _openTheChoice(tester, SalaHarness(filaEmMemoria: true));

    expect(_ground(tester), SalaColors.light.paper);
    expect(_selected(tester, 'Claro'), isTrue);
    expect(_selected(tester, 'Escuro'), isFalse);
  });

  choiceTest('dark keeps the warm ground', (tester) async {
    await _openTheChoice(tester, SalaHarness(filaEmMemoria: true));

    await tester.tap(byLabel('Escuro'));
    await _theThemeFinishes(tester);

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    final theme = Theme.of(tester.element(find.byType(Scaffold).first));
    expect(theme.brightness, Brightness.dark);
    expect(
      scaffold.backgroundColor ?? theme.scaffoldBackgroundColor,
      SalaColors.dark.paper,
    );
  });

  choiceTest(
    'the language and look controls show on the Choice and nowhere else',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await _openTheChoice(tester, harness);

      expect(find.text('PT'), findsOneWidget);
      expect(byLabel('Claro'), findsOneWidget);

      await _enter(tester, container, 'P01');

      expect(find.text('PT'), findsNothing);
      expect(find.text('EN'), findsNothing);
      expect(byLabel('Claro'), findsNothing);
      expect(byLabel('Escuro'), findsNothing);
    },
  );

  choiceTest('the sun and the moon are named in the Room language', (
    tester,
  ) async {
    await _openTheChoice(
      tester,
      SalaHarness(filaEmMemoria: true, lingua: null),
    );

    expect(byLabel('Claro'), findsOneWidget);
    expect(byLabel('Escuro'), findsOneWidget);

    await tester.tap(find.text('EN'));
    await _catchUp(tester);

    expect(byLabel('Light'), findsOneWidget);
    expect(byLabel('Dark'), findsOneWidget);
  });

  choiceTest(
    'an English session reached again after «PT» is tapped still hears her acknowledgement in English',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true, lingua: null);
      final container = await _openTheChoice(tester, harness);
      final notifier = container.read(salaSessionProvider.notifier);
      await tester.tap(find.text('EN'));
      await _catchUp(tester);
      await _enter(tester, container, 'P01');
      await _leave(tester, container);
      await tester.tap(find.text('PT'));
      await _catchUp(tester);
      await tester.tap(byLabel(roomLabelFor('backToPassage', 'pt')));
      await _catchUp(tester);
      harness.voice.fixedLines.clear();

      notifier.conversaTap();
      await _catchUp(tester);
      notifier.conversaTap();
      await _catchUp(tester);

      final heard = [
        for (final line in harness.voice.fixedLines)
          if (instantAckLines.contains(line.$1)) line.$2,
      ];
      expect(heard, isNotEmpty);
      expect(heard, everyElement('en'));
    },
  );

  choiceTest('on a dark device, the sun gives the status bar dark glyphs', (
    tester,
  ) async {
    deviceIs(tester, brightness: Brightness.dark);
    await _openTheChoice(tester, SalaHarness(filaEmMemoria: true));

    await tester.tap(byLabel('Claro'));
    await _theThemeFinishes(tester);

    expect(_statusBarGlyphs(tester), Brightness.dark);
  });

  choiceTest('on a light device, the moon gives the status bar light glyphs', (
    tester,
  ) async {
    deviceIs(tester, brightness: Brightness.light);
    await _openTheChoice(tester, SalaHarness(filaEmMemoria: true));

    await tester.tap(byLabel('Escuro'));
    await _theThemeFinishes(tester);

    expect(_statusBarGlyphs(tester), Brightness.light);
  });
}
