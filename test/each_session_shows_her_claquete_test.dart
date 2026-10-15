import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/bead_styles.dart';
import 'package:internalization_room/features/sala/presentation/widgets/claquete.dart';
import 'package:internalization_room/features/sala/presentation/widgets/hear_again_button.dart';
import 'package:internalization_room/features/sala/presentation/widgets/shema_mark.dart';
import 'package:internalization_room/main.dart' show SalaApp;

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show relaunch;

const _sessionId = 'fia-fixture-0001';
const _herEightCharacters = 'fia-fixt';
final _noon = DateTime(2026, 9, 30, 14, 14, 5);

const _panorama = Passagem(
  pericope: 'panorama',
  audioUrl: '/voice/panorama',
  kind: PassagemKind.panorama,
);

final _claquete = find.byType(Claquete);
final _mark = find.byType(ShemaMark);

String _words(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(of: _claquete, matching: find.byType(Text)),
    )
    .map((text) => text.data)
    .join();

Future<void> _elapse(WidgetTester tester, Duration time) async {
  var left = time;
  const beat = Duration(milliseconds: 100);
  while (left > Duration.zero) {
    final step = left < beat ? left : beat;
    await tester.pump(step);
    left -= step;
  }
}

Future<void> _seconds(WidgetTester tester, int seconds) =>
    _elapse(tester, Duration(seconds: seconds));

Future<(SalaHarness, ProviderContainer)> _openP05(
  WidgetTester tester, {
  String? pericope = 'P05',
}) async {
  final harness = SalaHarness()
    ..room.passages = const [Passagem(pericope: 'P05', audioUrl: '/voice/p05')]
    ..room.nextSessionId = _sessionId;
  final container = await pumpSala(tester, harness);
  addTearDown(() => closeTheRoom(container));
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.abrirEscolha();
  await tester.pump(const Duration(milliseconds: 300));
  unawaited(notifier.goConversa(pericope: pericope));
  await _elapse(tester, const Duration(milliseconds: 300));
  expect(container.read(salaSessionProvider).sessionId, _sessionId);
  return (harness, container);
}

Iterable<String> _everythingTheScreenReaderCouldSay(WidgetTester tester) sync* {
  final root =
      tester.binding.rootPipelineOwner.semanticsOwner!.rootSemanticsNode!;
  final pending = [root];
  while (pending.isNotEmpty) {
    final node = pending.removeLast();
    final data = node.getSemanticsData();
    yield data.label;
    yield data.value;
    yield data.hint;
    node.visitChildren((child) {
      pending.add(child);
      return true;
    });
  }
}

void main() {
  testWidgets(
    'a team that opens P05 sees its claquete in the corner for twenty seconds, then nothing',
    (tester) => withClock(Clock.fixed(_noon), () async {
      await _openP05(tester);

      expect(_words(tester), 'P05 · 2026-09-30 14:14 · $_herEightCharacters');

      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      final rect = tester.getRect(_claquete);
      expect(rect.right, closeTo(screen.width - 14 - 76 - 8, 0.5));
      expect(rect.bottom, closeTo(screen.height - 18, 0.5));

      await _seconds(tester, 19);
      expect(_claquete, findsOneWidget);

      await _seconds(tester, 2);
      expect(_claquete, findsNothing);
    }),
  );

  testWidgets(
    'a relaunch into the same session shows the claquete again with the same session characters',
    (tester) => withClock(Clock.fixed(_noon), () async {
      final (harness, container) = await _openP05(tester);
      await _seconds(tester, 21);
      expect(_claquete, findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      final (_, next) = await relaunch(harness, container);
      addTearDown(() => closeTheRoom(next));
      await tester.pumpWidget(
        UncontrolledProviderScope(container: next, child: const SalaApp()),
      );
      for (var beat = 0; beat < 100; beat++) {
        if (next.read(salaSessionProvider).sessionId == _sessionId) break;
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(next.read(salaSessionProvider).sessionId, _sessionId);
      await tester.pump(const Duration(milliseconds: 100));

      expect(_words(tester), endsWith(_herEightCharacters));

      await _seconds(tester, 19);
      expect(_claquete, findsOneWidget);
      await _seconds(tester, 3);
      expect(_claquete, findsNothing);
    }),
  );

  testWidgets(
    'a tap on the Shema mark mid-session shows the claquete for twenty seconds',
    (tester) => withClock(Clock.fixed(_noon), () async {
      await _openP05(tester);
      await _seconds(tester, 21);
      expect(_claquete, findsNothing);

      await tester.tap(_mark);
      await tester.pump();

      expect(_words(tester), 'P05 · 2026-09-30 14:14 · $_herEightCharacters');
      await _seconds(tester, 19);
      expect(_claquete, findsOneWidget);
      await _seconds(tester, 2);
      expect(_claquete, findsNothing);
    }),
  );

  testWidgets(
    'the session characters are the start of the id the room gave the session',
    (tester) => withClock(Clock.fixed(_noon), () async {
      await _openP05(tester);

      final third = _words(tester).split(' · ').last;
      expect(third, _herEightCharacters);
      expect(_sessionId, startsWith(third));
      expect(third, isNot(_sessionId));
    }),
  );

  testWidgets('VoiceOver never announces the claquete', (tester) async {
    final handle = tester.ensureSemantics();
    await withClock(Clock.fixed(_noon), () async {
      await _openP05(tester);
      expect(_claquete, findsOneWidget);

      final heard = _everythingTheScreenReaderCouldSay(tester).join('\n');
      expect(heard, isNot(contains('P05')));
      expect(heard, isNot(contains(_herEightCharacters)));
      expect(heard, isNot(contains('2026-09-30')));
    });
    handle.dispose();
  });

  testWidgets('a tap on the claquete changes nothing', (tester) async {
    await withClock(Clock.fixed(_noon), () async {
      final (harness, container) = await _openP05(tester);
      final calls = List.of(harness.room.calls);
      final before = container.read(salaSessionProvider);

      await tester.tap(_claquete, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));

      final after = container.read(salaSessionProvider);
      expect(harness.room.calls, calls);
      expect(after.voice, before.voice);
      expect(after.stage, before.stage);
      expect(_claquete, findsOneWidget);
    });
  });

  testWidgets('the claquete writes the date and time zero-padded', (
    tester,
  ) async {
    await withClock(Clock.fixed(DateTime(2026, 3, 4, 9, 5)), () async {
      await _openP05(tester);

      expect(_words(tester), 'P05 · 2026-03-04 09:05 · $_herEightCharacters');
    });
  });

  testWidgets(
    'a second tap on the mark gives the claquete twenty seconds from that tap',
    (tester) => withClock(Clock.fixed(_noon), () async {
      await _openP05(tester);
      await _seconds(tester, 21);

      await tester.tap(_mark);
      await _seconds(tester, 15);
      expect(_claquete, findsOneWidget);
      await tester.tap(_mark);

      await _seconds(tester, 19);
      expect(_claquete, findsOneWidget);
      await _seconds(tester, 2);
      expect(_claquete, findsNothing);
    }),
  );

  testWidgets('leaving the session takes the claquete with it', (tester) async {
    await withClock(Clock.fixed(_noon), () async {
      final (_, container) = await _openP05(tester);
      expect(_claquete, findsOneWidget);

      container.read(salaSessionProvider.notifier).leaveThePassage();
      await _elapse(tester, const Duration(milliseconds: 500));

      expect(container.read(salaSessionProvider).stage, SalaStage.escolha);
      expect(_claquete, findsNothing);
    });
  });

  testWidgets('the claquete never covers the hear-again button', (
    tester,
  ) async {
    await withClock(Clock.fixed(_noon), () async {
      final (_, container) = await _openP05(tester);
      for (var beat = 0; beat < 50; beat++) {
        if (container.read(salaSessionProvider).canHearAgain) break;
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(container.read(salaSessionProvider).canHearAgain, isTrue);
      final button = find.descendant(
        of: find.byType(HearAgainButton),
        matching: find.byType(RoundActionButton),
      );
      expect(button, findsOneWidget);
      expect(_claquete, findsOneWidget);

      final overlap = tester
          .getRect(_claquete)
          .intersect(tester.getRect(button));
      expect(overlap.width <= 0 || overlap.height <= 0, isTrue);
    });
  });

  testWidgets('the Panorama shows no claquete and no Shema mark', (
    tester,
  ) async {
    await withClock(Clock.fixed(_noon), () async {
      final harness = SalaHarness()
        ..room.passages = const [
          _panorama,
          Passagem(pericope: 'P05', audioUrl: '/voice/p05'),
        ]
        ..room.nextSessionId = _sessionId;
      final container = await pumpSala(tester, harness);
      addTearDown(() => closeTheRoom(container));
      final notifier = container.read(salaSessionProvider.notifier);

      await notifier.abrirEscolha();
      await _elapse(tester, const Duration(seconds: 1));
      final state = container.read(salaSessionProvider);
      notifier.apontarPassagem(
        state.naRoda!.indexWhere((entry) => entry.isPanorama),
      );
      await _elapse(tester, const Duration(seconds: 2));
      notifier.entrarNaOferecida();
      for (var beat = 0; beat < 100; beat++) {
        if (container.read(salaSessionProvider).stage == SalaStage.panorama) {
          break;
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
      await _elapse(tester, const Duration(milliseconds: 500));

      expect(container.read(salaSessionProvider).stage, SalaStage.panorama);
      expect(_claquete, findsNothing);
      expect(_mark, findsNothing);
    });
  });

  testWidgets('a session with no pericope shows no claquete', (tester) async {
    await withClock(Clock.fixed(_noon), () async {
      final harness = SalaHarness()..room.nextSessionId = _sessionId;
      final container = await pumpSala(tester, harness);
      addTearDown(() => closeTheRoom(container));
      final notifier = container.read(salaSessionProvider.notifier);
      unawaited(notifier.goConversa());
      await _elapse(tester, const Duration(milliseconds: 500));

      expect(container.read(salaSessionProvider).sessionId, _sessionId);
      expect(_claquete, findsNothing);
    });
  });
}
