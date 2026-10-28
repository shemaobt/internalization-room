import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/sala_colors.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/moment.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/scene_rehearsal.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/corner_disc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show byLabel;

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
];

const _leave = 'Choose another passage';
const _back = 'Back to the current passage';
const _backInPortuguese = 'Voltar para a passagem atual';

class _Room {
  _Room(this.container);

  final ProviderContainer container;

  SalaSessionNotifier get notifier =>
      container.read(salaSessionProvider.notifier);

  SalaSessionState get state => container.read(salaSessionProvider);
}

Future<_Room> _pump(WidgetTester tester, {bool memory = false}) async {
  final harness = SalaHarness(lingua: 'en', filaEmMemoria: memory);
  harness.room.passages = _theBook;
  return _Room(await pumpSala(tester, harness));
}

Future<void> _passTime(WidgetTester tester, [int milliseconds = 400]) =>
    tester.pump(Duration(milliseconds: milliseconds));

Future<void> _readTheWheel(WidgetTester tester, _Room room) async {
  await room.notifier.abrirEscolha();
  await _passTime(tester, 300);
}

Future<void> _takeThePanorama(WidgetTester tester, _Room room) async {
  await _readTheWheel(tester, room);
  room.notifier.openTheEntry(room.state.naRoda!.first);
  await _passTime(tester);
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _takeThePassage(WidgetTester tester, _Room room) async {
  await _readTheWheel(tester, room);
  room.notifier.openTheEntry(
    room.state.naRoda!.firstWhere((entry) => entry.pericope == 'P01'),
  );
  await _passTime(tester);
  await _passTime(tester);
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.tap(byLabel(label), warnIfMissed: false);
  await _passTime(tester);
}

Finder _discOf(String label) => find.descendant(
  of: byLabel(label),
  matching: find.byWidgetPredicate((widget) {
    if (widget is! DecoratedBox) return false;
    final decoration = widget.decoration;
    return decoration is BoxDecoration && decoration.shape == BoxShape.circle;
  }),
);

BoxDecoration _bodyOf(WidgetTester tester, String label) =>
    (tester.widget<DecoratedBox>(_discOf(label).last).decoration
        as BoxDecoration);

Icon _glyphOf(WidgetTester tester, String label) => tester.widget<Icon>(
  find.descendant(of: _discOf(label).last, matching: find.byType(Icon)),
);

Finder _cornerDiscOf(String label) =>
    find.descendant(of: byLabel(label), matching: find.byType(CornerDisc));

List<double> _opacitiesOver(WidgetTester tester, String label) {
  final glyph = find
      .descendant(of: _discOf(label).last, matching: find.byType(Icon))
      .evaluate()
      .single;
  final labelled = byLabel(label).evaluate().first;
  final over = <double>[];
  glyph.visitAncestorElements((ancestor) {
    if (ancestor == labelled) return false;
    final widget = ancestor.widget;
    if (widget is Opacity) over.add(widget.opacity);
    if (widget is AnimatedOpacity) over.add(widget.opacity);
    if (widget is FadeTransition) over.add(widget.opacity.value);
    return true;
  });
  return over;
}

void _isDrawnInFull(WidgetTester tester, String label) {
  final over = _opacitiesOver(tester, label);
  expect(over.every((opacity) => opacity == 1.0), isTrue, reason: '$over');
  expect(_glyphOf(tester, label).color!.a, 1.0);
}

void _wearsTheBody(
  WidgetTester tester,
  String label,
  IconData glyph, {
  SalaColors colors = SalaColors.light,
}) {
  expect(_cornerDiscOf(label), findsOneWidget);
  expect(_discOf(label), findsAtLeastNWidgets(1));
  expect(tester.getSize(_discOf(label).last), const Size(44, 44));
  final body = _bodyOf(tester, label);
  expect(body.color, colors.elev);
  final shadow = body.boxShadow!.single;
  expect(shadow.offset, const Offset(0, 1));
  expect(shadow.blurRadius, 3);
  expect(shadow.color.toARGB32() & 0x00FFFFFF, 0x0A0703);
  expect(shadow.color.a, closeTo(0.15, 0.005));
  final icon = _glyphOf(tester, label);
  expect(icon.icon, glyph);
  expect(icon.size, 22);
  expect(icon.color, ShemaBrand.verdeClaro);
}

void main() {
  testWidgets('the way out wears the hear-again button\'s body', (
    tester,
  ) async {
    final room = await _pump(tester);
    await _takeThePanorama(tester, room);
    final hearAgain = roomLabelFor('hearAgain', 'en');

    expect(byLabel(_leave), findsOneWidget);
    expect(byLabel(hearAgain), findsOneWidget);
    _wearsTheBody(tester, _leave, LucideIcons.menu);
    _wearsTheBody(tester, hearAgain, LucideIcons.rotateCcw);
    _isDrawnInFull(tester, _leave);
    _isDrawnInFull(tester, hearAgain);
  });

  testWidgets('the way out keeps its place and its 46 px target', (
    tester,
  ) async {
    final room = await _pump(tester);
    await _takeThePanorama(tester, room);

    final rect = tester.getRect(byLabel(_leave));
    expect(rect.size, const Size(46, 46));
    expect(rect.left, 14);
    expect(rect.top, 118);

    await _tap(tester, _leave);
    await tester.pump(const Duration(seconds: 1));

    expect(room.state.stage, SalaStage.escolha);
  });

  testWidgets('the way out carried in a stage heading wears the same body', (
    tester,
  ) async {
    final room = await _pump(tester, memory: true);
    await _takeThePassage(tester, room);
    room.notifier.goEnsaio();
    await _passTime(tester, 300);
    await tester.pump(const Duration(seconds: 2));

    expect(room.state.stage, SalaStage.ensaio);
    _wearsTheBody(tester, _back, LucideIcons.chevronLeft);
  });

  testWidgets(
    'the way back on the Choice wears the same body and is full while live',
    (tester) async {
      final room = await _pump(tester);
      await _takeThePassage(tester, room);
      await _tap(tester, _leave);
      await tester.pump(const Duration(seconds: 1));

      _wearsTheBody(tester, _back, LucideIcons.chevronLeft);
      _isDrawnInFull(tester, _back);

      await _tap(tester, _back);
      await tester.pump(const Duration(seconds: 1));

      expect(room.state.stage, SalaStage.conversa);
    },
  );

  testWidgets('in the dark look the three corner buttons wear the dark body', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final room = await _pump(tester);
    await _takeThePanorama(tester, room);
    final hearAgain = roomLabelFor('hearAgain', 'en');

    _wearsTheBody(tester, _leave, LucideIcons.menu, colors: SalaColors.dark);
    _wearsTheBody(
      tester,
      hearAgain,
      LucideIcons.rotateCcw,
      colors: SalaColors.dark,
    );
    await _tap(tester, _leave);
    await tester.pump(const Duration(seconds: 1));
    _wearsTheBody(
      tester,
      _back,
      LucideIcons.chevronLeft,
      colors: SalaColors.dark,
    );
  });

  testWidgets(
    'the way back is dimmed and takes no tap while the scene rehearsal sends',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true)
        ..room.passages = const [
          Passagem(pericope: 'P01', audioUrl: '/voice/p01'),
        ]
        ..room.nextMoment = const Moment(
          at: MomentAt.articulation,
          part: 1,
          parts: 3,
        )
        ..room.sceneRehearsals.add(
          SceneRehearsalRecord(
            rehearsalId: 'ensaio-da-cena-1',
            sessionId: 'sessao-1',
            n: 1,
            recordedAt: DateTime(2026, 10, 15, 14, 5),
            frases: const [
              SceneFrase(fraseId: 'f1', startsMs: 0, endsMs: 4000),
            ],
          ),
        );
      harness.playback.measured = const Duration(seconds: 20);
      tester.view
        ..physicalSize = const Size(820, 2400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = await pumpSala(tester, harness);
      addTearDown(() => closeTheRoom(container));
      final notifier = container.read(salaSessionProvider.notifier);
      await notifier.abrirEscolha();
      await tester.pump(const Duration(milliseconds: 300));
      unawaited(notifier.goConversa(book: 'Ruth', pericope: 'P01'));
      for (var i = 0; i < 30; i++) {
        if (container.read(salaSessionProvider).voice == VoiceState.invite) {
          break;
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.tap(byLabel('ensaio da cena'));
      for (var i = 0; i < 30; i++) {
        if (container.read(salaSessionProvider).scene.step ==
            SceneStep.translate) {
          break;
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(milliseconds: 1500));
      harness.room.holdNextTurn();
      await tester.tap(byLabel('terminei'));
      await tester.pump(const Duration(milliseconds: 500));

      expect(container.read(salaSessionProvider).stage, SalaStage.cena);
      expect(_cornerDiscOf(_backInPortuguese), findsOneWidget);
      expect(_opacitiesOver(tester, _backInPortuguese), contains(0.2));
      expect(
        tester.widget<Semantics>(byLabel(_backInPortuguese)).properties.enabled,
        isFalse,
      );

      await tester.tap(byLabel(_backInPortuguese), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));

      expect(container.read(salaSessionProvider).stage, SalaStage.cena);

      harness.room.finishHeldTurn();
      await tester.pump(const Duration(seconds: 3));
    },
  );
}
