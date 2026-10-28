import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/bead_styles.dart';
import 'package:internalization_room/features/sala/presentation/widgets/claquete.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/features/sala/presentation/widgets/hand_button.dart';
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
  pericope: 'OV-Ruth',
  audioUrl: '/voice/panorama',
  kind: PassagemKind.panorama,
);

final _claquete = find.byType(Claquete);
final _mark = find.descendant(
  of: find.byType(ClaqueteLayer),
  matching: find.byType(ShemaMark),
);

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

Future<List<double>> _markOverOneBreath(WidgetTester tester) async {
  final seen = <double>[];
  for (var beat = 0; beat <= 92; beat++) {
    seen.add(tester.widget<ShemaMark>(_mark).opacity);
    await tester.pump(const Duration(milliseconds: 100));
  }
  return seen;
}

void _breathesAsHers(List<double> seen) {
  final quietest = seen.indexOf(seen.reduce(min));
  final fullest = seen.indexOf(seen.reduce(max));
  expect(
    seen[quietest],
    closeTo(0.66, 0.005),
    reason: 'a marca ficava parada em .72; a dela respira até .66',
  );
  expect(
    seen[fullest],
    closeTo(0.8, 0.005),
    reason: 'a marca ficava parada em .72; a dela respira até .8',
  );
  expect(
    (fullest - quietest).abs(),
    inInclusiveRange(42, 48),
    reason: 'a respiração dela leva 9 s, 4,5 s de cada lado',
  );
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
  unawaited(notifier.goConversa(book: 'Ruth', pericope: pericope));
  await _elapse(tester, const Duration(milliseconds: 300));
  expect(container.read(salaSessionProvider).sessionId, _sessionId);
  return (harness, container);
}

Future<void> _openP05WhileTheVoiceSpeaks(WidgetTester tester) async {
  final harness = SalaHarness()
    ..room.passages = const [Passagem(pericope: 'P05', audioUrl: '/voice/p05')]
    ..room.nextSessionId = _sessionId;
  final container = await pumpSala(tester, harness);
  addTearDown(() => closeTheRoom(container));
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.abrirEscolha();
  await tester.pump(const Duration(milliseconds: 300));
  harness.voice.holdNextLine();
  addTearDown(harness.voice.finishHeldLine);
  unawaited(notifier.goConversa(book: 'Ruth', pericope: 'P05'));
  for (var beat = 0; beat < 50; beat++) {
    if (container.read(salaSessionProvider).voice == VoiceState.speaking &&
        _mark.evaluate().isNotEmpty) {
      break;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(container.read(salaSessionProvider).voice, VoiceState.speaking);
}

Future<ProviderContainer> _openThePanorama(WidgetTester tester) async {
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
  notifier.openTheEntry(state.naRoda!.firstWhere((entry) => entry.isPanorama));
  for (var beat = 0; beat < 100; beat++) {
    if (container.read(salaSessionProvider).stage == SalaStage.panorama) break;
    await tester.pump(const Duration(milliseconds: 100));
  }
  await _elapse(tester, const Duration(milliseconds: 500));
  expect(container.read(salaSessionProvider).stage, SalaStage.panorama);
  return container;
}

Iterable<String> _everythingTheScreenReaderCouldSay(WidgetTester tester) sync* {
  final root = tester
      .renderObject(find.byType(Scaffold))
      .owner!
      .semanticsOwner!
      .rootSemanticsNode!;
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

Future<ProviderContainer> _resumedOnTheCheckScreenOfAnSE(
  WidgetTester tester,
) async {
  tester.view
    ..physicalSize = const Size(375, 667)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final folder = Directory.systemTemp.createTempSync('sala-1817');
  addTearDown(() => folder.deleteSync(recursive: true));
  final harness = SalaHarness(filaEmMemoria: true);
  harness.emAberto.rows['Ruth/P01/pt'] = ResumePoint(
    sessionId: _sessionId,
    stage: SalaStage.retro,
    takes: [
      for (final n in [1, 2])
        KeptTake(
          scopeId: KeptScope.parte(n),
          path: (File(
            '${folder.path}/p$n.m4a',
          )..writeAsBytesSync([1, 2, 3])).path,
          takeId: 'take-$n',
        ),
    ],
  );
  harness.room.retroSoFar = BackTranslationProgress(
    segments: [
      for (final frase in [1, 2, 3, 4])
        SegmentView(
          segmentId: 'segment-$frase',
          takeId: 'take-${(frase + 1) ~/ 2}',
          startsMs: frase.isOdd ? 0 : 4000,
          endsMs: frase.isOdd ? 4000 : 8000,
          frase: frase,
        ),
    ],
  );
  final container = harness.container();
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await tester.pump(const Duration(milliseconds: 100));
  unawaited(
    container
        .read(salaSessionProvider.notifier)
        .goConversa(book: 'Ruth', pericope: 'P01'),
  );
  await waitFor(
    'the check screen to come back with its four frases',
    () =>
        container.read(salaSessionProvider).stage == SalaStage.retro &&
        container.read(salaSessionProvider).btTrechos.length == 4,
    step: () => letTheRehearsalReachTheRoom(tester),
  );
  await tester.pump(const Duration(milliseconds: 100));
  return container;
}

void main() {
  testWidgets(
    'a team that opens P05 sees its claquete in the corner for twenty seconds, then nothing',
    (tester) => withClock(Clock.fixed(_noon), () async {
      await _openP05(tester);

      expect(_words(tester), 'P05 · 2026-09-30 14:14 · $_herEightCharacters');

      final rect = tester.getRect(_claquete);
      expect(
        rect.right,
        closeTo(780.8, 0.5),
        reason:
            'a claquete ficava ao lado do ouvir de novo; a dela fica a 2,4% '
            'da borda',
      );
      expect(
        rect.bottom,
        closeTo(584.4, 0.5),
        reason:
            'a claquete ficava a 18 px do fundo; a dela fica a 2,6% da altura',
      );

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
      expect(_claquete, findsOneWidget);

      final overlap = tester
          .getRect(_claquete)
          .intersect(tester.getRect(button));
      expect(overlap.width <= 0 || overlap.height <= 0, isTrue);
    });
  });

  testWidgets('in the dark room the claquete is her lighter olive', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await withClock(Clock.fixed(_noon), () async {
      await _openP05(tester);

      final style = tester
          .widget<Text>(
            find.descendant(of: _claquete, matching: find.byType(Text)),
          )
          .style!;
      expect(style.color, const Color(0xFFAAB07E).withValues(alpha: 0.7));
    });
  });

  testWidgets(
    'the Shema mark on the conversation breathes between .66 and .8, not still at .72',
    (tester) => withClock(Clock.fixed(_noon), () async {
      await _openP05(tester);

      _breathesAsHers(await _markOverOneBreath(tester));
    }),
  );

  testWidgets(
    'the Shema mark on the Panorama breathes as the conversation does',
    (tester) => withClock(Clock.fixed(_noon), () async {
      await _openThePanorama(tester);

      _breathesAsHers(await _markOverOneBreath(tester));
    }),
  );

  testWidgets(
    'with reduced motion the Shema mark stays still at .72, not at the bottom of a breath',
    (tester) => withClock(Clock.fixed(_noon), () async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final (_, container) = await _openP05(tester);
      for (var beat = 0; beat < 50; beat++) {
        if (container.read(salaSessionProvider).voice != VoiceState.speaking) {
          break;
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        container.read(salaSessionProvider).voice,
        isNot(VoiceState.speaking),
      );

      final seen = await _markOverOneBreath(tester);
      expect(seen.toSet(), {
        0.72,
      }, reason: 'sem movimento a dela fica em .72, sem a animação');
    }),
  );

  testWidgets(
    'with reduced motion the Shema mark rises to .85 while the voice speaks',
    (tester) => withClock(Clock.fixed(_noon), () async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await _openP05WhileTheVoiceSpeaks(tester);

      expect(
        tester.widget<ShemaMark>(_mark).opacity,
        0.85,
        reason: 'enquanto a voz fala a dela sobe para .85',
      );
    }),
  );

  testWidgets(
    'while the voice speaks the Shema mark keeps breathing, as hers does with motion on',
    (tester) => withClock(Clock.fixed(_noon), () async {
      await _openP05WhileTheVoiceSpeaks(tester);

      _breathesAsHers(await _markOverOneBreath(tester));
    }),
  );

  testWidgets('the claquete is written at her .68rem, not a size of ours', (
    tester,
  ) async {
    await withClock(Clock.fixed(_noon), () async {
      await _openP05(tester);

      final style = tester
          .widget<Text>(
            find.descendant(of: _claquete, matching: find.byType(Text)),
          )
          .style!;
      expect(
        style.fontSize,
        10.88,
        reason: 'a claquete saía em 11; a dela é .68rem de 16 px',
      );
    });
  });

  testWidgets('at phone width the claquete keeps clear of the hand', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await withClock(Clock.fixed(_noon), () async {
      await _openP05(tester);
      expect(_claquete, findsOneWidget);

      final hand = tester.getRect(find.byType(HandButton));
      final claquete = tester.getRect(_claquete);
      expect(claquete.left, greaterThanOrEqualTo(hand.right + 8 - 0.5));
      expect(claquete.right, closeTo(366, 0.5));
      expect(claquete.bottom, closeTo(649.658, 0.5));
    });
  });

  testWidgets(
    'on an SE her corner keeps the claquete clear of the replay, the hand and the circle',
    (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await withClock(Clock.fixed(_noon), () async {
        final (_, container) = await _openP05(tester);
        for (var beat = 0; beat < 50; beat++) {
          if (container.read(salaSessionProvider).canHearAgain) break;
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(container.read(salaSessionProvider).canHearAgain, isTrue);
        expect(_claquete, findsOneWidget);

        final claquete = tester.getRect(_claquete);
        for (final (what, widget) in [
          (
            'o ouvir de novo',
            find.descendant(
              of: find.byType(HearAgainButton),
              matching: find.byType(RoundActionButton),
            ),
          ),
          ('a mão', find.byType(HandButton)),
          ('o círculo', find.byType(FacilitatorCircle)),
        ]) {
          expect(widget, findsWidgets);
          for (final one in widget.evaluate()) {
            final box = one.renderObject! as RenderBox;
            final overlap = claquete.intersect(
              box.localToGlobal(Offset.zero) & box.size,
            );
            expect(
              overlap.width <= 0 || overlap.height <= 0,
              isTrue,
              reason: 'no canto dela a claquete cobria $what',
            );
          }
        }
      });
    },
  );

  testWidgets(
    'a tap on the Shema mark on the Panorama shows the claquete for twenty seconds again',
    (tester) => withClock(Clock.fixed(_noon), () async {
      await _openThePanorama(tester);
      await _seconds(tester, 21);
      expect(_claquete, findsNothing);

      await tester.tap(_mark);
      await tester.pump();

      expect(
        _words(tester),
        'OV-Ruth · 2026-09-30 14:14 · $_herEightCharacters',
      );
      await _seconds(tester, 19);
      expect(_claquete, findsOneWidget);
      await _seconds(tester, 2);
      expect(_claquete, findsNothing);
    }),
  );

  testWidgets(
    'leaving the Panorama takes the claquete and the mark with it, and going back to it shows the claquete again',
    (tester) => withClock(Clock.fixed(_noon), () async {
      final container = await _openThePanorama(tester);
      final notifier = container.read(salaSessionProvider.notifier);
      await _seconds(tester, 5);

      notifier.leaveThePassage();
      await _elapse(tester, const Duration(seconds: 1));
      expect(container.read(salaSessionProvider).stage, SalaStage.escolha);
      expect(_claquete, findsNothing);
      expect(_mark, findsNothing);
      await _seconds(tester, 21);

      final state = container.read(salaSessionProvider);
      notifier.openTheEntry(
        state.naRoda!.firstWhere((entry) => entry.isPanorama),
      );
      await _elapse(tester, const Duration(seconds: 1));

      expect(container.read(salaSessionProvider).stage, SalaStage.panorama);
      expect(
        _words(tester),
        'OV-Ruth · 2026-09-30 14:14 · $_herEightCharacters',
      );
      expect(_mark, findsOneWidget);
    }),
  );

  testWidgets('VoiceOver never announces the claquete on the Panorama', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await withClock(Clock.fixed(_noon), () async {
      await _openThePanorama(tester);
      expect(_claquete, findsOneWidget);

      final heard = _everythingTheScreenReaderCouldSay(tester).join('\n');
      expect(heard, isNot(contains('OV-Ruth')));
      expect(heard, isNot(contains(_herEightCharacters)));
      expect(heard, isNot(contains('2026-09-30')));
    });
    handle.dispose();
  });

  testWidgets(
    'the Panorama shows its claquete for twenty seconds and keeps the Shema mark, as the conversation does',
    (tester) => withClock(Clock.fixed(_noon), () async {
      await _openThePanorama(tester);

      expect(
        _words(tester),
        'OV-Ruth · 2026-09-30 14:14 · $_herEightCharacters',
      );
      expect(_mark, findsOneWidget);

      await _seconds(tester, 19);
      expect(_claquete, findsOneWidget);
      await _seconds(tester, 2);
      expect(_claquete, findsNothing);
      expect(_mark, findsOneWidget);
    }),
  );

  testWidgets(
    'the Panorama writes its claquete in her corner, as the conversation does',
    (tester) => withClock(Clock.fixed(_noon), () async {
      await _openThePanorama(tester);

      final rect = tester.getRect(_claquete);
      expect(rect.right, closeTo(780.8, 0.5));
      expect(rect.bottom, closeTo(584.4, 0.5));
    }),
  );

  testWidgets('a session with no pericope shows no claquete', (tester) async {
    await withClock(Clock.fixed(_noon), () async {
      final harness = SalaHarness()..room.nextSessionId = _sessionId;
      final container = await pumpSala(tester, harness);
      addTearDown(() => closeTheRoom(container));
      final notifier = container.read(salaSessionProvider.notifier);
      unawaited(notifier.goConversa(book: 'Ruth'));
      await _elapse(tester, const Duration(milliseconds: 500));

      expect(container.read(salaSessionProvider).sessionId, _sessionId);
      expect(_claquete, findsNothing);
    });
  });

  testWidgets(
    'a session resumed on the check screen of an SE draws no claquete over its frases',
    (tester) => withClock(Clock.fixed(_noon), () async {
      final container = await _resumedOnTheCheckScreenOfAnSE(tester);
      final state = container.read(salaSessionProvider);
      expect(state.stage, SalaStage.retro);
      expect(state.sessionId, _sessionId);

      expect(
        _claquete,
        findsNothing,
        reason:
            'a claquete ficava parada sobre a tela da conferência e cobria o '
            'título das frases; a dela só existe no canvas da conversa',
      );
      closeTheRoom(container);
    }),
  );
}
