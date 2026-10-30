import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/moment.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/scene_question.dart';
import 'package:internalization_room/features/sala/domain/scene_rehearsal.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/ensaio_final_plan_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/listen_glyph.dart';
import 'package:internalization_room/features/sala/presentation/widgets/rehearsal_sheet.dart';
import 'package:internalization_room/features/sala/presentation/widgets/scene_question.dart';
import 'package:internalization_room/main.dart';

import 'every_way_back_is_her_bare_chevron_test.dart' show expectHerChevron;
import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show byLabel, relaunch;

const _recordEnsaio = 'Gravar o ensaio de vocês';
const _recordEnsaioEn = 'Record your rehearsal';

const _planLine = 'Estes são os ensaios das cenas que vocês me enviaram.';
const _swap = 'trocar o ensaio desta cena';
const _back = 'Voltar para a gravação';
const _useThis = 'usar este';
const _inUse = '✓ em uso';
const _recordAgain = 'gravar esta cena de novo';
const _whichScene = 'De que cena é este ensaio?';
const _labelFailed = 'não deu para guardar a resposta — toquem de novo';
const _cannotEnter = 'este ensaio não pode entrar — ensaiem esta cena de novo';
const _question = 'Qual cena vocês vão ensaiar?';
const _join = 'juntar as cenas e ouvir';
const _sceneByScene = 'Gravar cena por cena';
const _wholeAtOnce = 'gravar a passagem inteira de uma vez';
const _houseBack = 'Voltar para a passagem atual';
const _circle = [
  'Gravar o ensaio da cena',
  'gravem o ensaio da cena na língua materna; toquem para parar',
  'guardando o ensaio da cena…',
];

const _threeScenes = [
  Scene(sceneId: 'S1', title: 'A fome em Belém'),
  Scene(sceneId: 'S2', title: 'Noemi decide voltar'),
  Scene(sceneId: 'S3', title: 'Rute fica com Noemi'),
];

const _threeScenesEn = [
  Scene(sceneId: 'S1', title: 'Famine in Bethlehem'),
  Scene(sceneId: 'S2', title: 'Naomi decides to return'),
  Scene(sceneId: 'S3', title: 'Ruth clings to Naomi'),
];

const _midConversation = Moment(
  at: MomentAt.internalization,
  part: 2,
  parts: 3,
);

const _thePassage = Passagem(pericope: 'P01', audioUrl: '/voice/p01');

final _recordedAt = DateTime.utc(2026, 10, 22, 13, 7);

String _clock(DateTime at) {
  final local = at.toLocal();
  return '${'${local.hour}'.padLeft(2, '0')}:'
      '${'${local.minute}'.padLeft(2, '0')}';
}

String _sentAt(String hhmm) => '2026-10-22T$hhmm:00+00:00';

List<SceneFrase> _tiling(int durationMs, int k) => [
  for (var i = 0; i < k; i++)
    SceneFrase(
      fraseId: 'frase-$i',
      startsMs: durationMs * i ~/ k,
      endsMs: durationMs * (i + 1) ~/ k,
    ),
];

SceneRehearsalRecord _rehearsal(
  String sessionId, {
  required int n,
  required String? scene,
  String? sentAt = '2026-10-22T10:00:00+00:00',
  int durationMs = 7000,
  int k = 2,
  List<SceneFrase>? frases,
  String contentType = 'audio/wav',
  bool verified = true,
}) => SceneRehearsalRecord(
  rehearsalId: '$sessionId-ensaio-$n',
  sessionId: sessionId,
  n: n,
  scene: scene,
  recordedAt: _recordedAt,
  sentAt: sentAt,
  durationMs: durationMs,
  frases: frases ?? _tiling(durationMs, k),
  contentType: contentType,
  verified: verified,
);

/// Scene 1 holds rehearsals 1, 2 and 3, sent at 10:00, 10:10 and 10:05: the Default
/// rehearsal is 2.
List<SceneRehearsalRecord> _threeOnSceneOne(String s) => [
  _rehearsal(s, n: 1, scene: 'S1', sentAt: _sentAt('10:00')),
  _rehearsal(s, n: 2, scene: 'S1', sentAt: _sentAt('10:10')),
  _rehearsal(s, n: 3, scene: 'S1', sentAt: _sentAt('10:05')),
];

/// Scene 2 holds rehearsal 1, and rehearsals 4 and 6 have a frase and no Scene label.
List<SceneRehearsalRecord> _twoUnlabelled(String s) => [
  _rehearsal(s, n: 1, scene: 'S2'),
  _rehearsal(s, n: 4, scene: null),
  _rehearsal(s, n: 6, scene: null),
];

/// Rehearsals 6, 4 and 5 have a frase and no Scene label, listed in that order: the
/// card goes by the room's oldest-first, not by the listing's.
List<SceneRehearsalRecord> _threeUnlabelled(String s) => [
  ..._threeOnSceneOne(s),
  _rehearsal(s, n: 6, scene: null),
  _rehearsal(s, n: 4, scene: null),
  _rehearsal(s, n: 5, scene: null),
];

final _dot = find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      const {_recordEnsaio, _recordEnsaioEn}.contains(widget.properties.label),
);

Finder _row(int n) => byLabel('Cena $n — ${_threeScenes[n - 1].title}');

Finder _onRow(int n, Finder target) =>
    find.descendant(of: _row(n), matching: target);

Finder _onLine(String line, Finder target) =>
    find.descendant(of: byLabel(line), matching: target);

Finder _onCard(Finder target) =>
    find.descendant(of: byLabel(_whichScene), matching: target);

String _facts(int n, {String dur = '0:07', int k = 2}) =>
    'ensaio $n · ${_clock(_recordedAt)} · $dur · $k frases';

String _sent(int n, {String dur = '0:07', int k = 2}) =>
    '${_facts(n, dur: dur, k: k)} · enviado';

String _sceneButton(int n) => 'cena $n ${_threeScenes[n - 1].title}';

Finder _step(int n) => _onCard(byLabel(_facts(n)));

Future<void> _stepTo(WidgetTester tester, int n) async {
  await tester.ensureVisible(_step(n));
  await tester.tap(_step(n));
  await _theAnswerSettles(tester);
}

Finder _shows(int n) => _onCard(find.text(_facts(n)));

Finder _paintedOn(String label) => find.descendant(
  of: byLabel(label),
  matching: find.byWidgetPredicate(
    (widget) => widget is CustomPaint && widget.painter is ListenGlyphPainter,
  ),
);

ListenGlyph _glyphOn(WidgetTester tester, String label) =>
    (tester.widget<CustomPaint>(_paintedOn(label)).painter!
            as ListenGlyphPainter)
        .glyph;

const _herPlay = (
  includes: [Offset(10, 12), Offset(9, 7), Offset(9, 17)],
  excludes: [Offset(7, 12), Offset(16, 8), Offset(16, 16)],
);

const _herPause = (
  includes: [Offset(8, 12), Offset(16, 12), Offset(7, 6), Offset(17, 18)],
  excludes: [
    Offset(12, 12),
    Offset(8, 4),
    Offset(16, 20),
    Offset(6.1, 5.1),
    Offset(17.9, 18.9),
  ],
);

Tristate _pressedAt(WidgetTester tester, String label) => tester
    .getSemantics(byLabel(label))
    .getSemanticsData()
    .flagsCollection
    .isSelected;

Tristate _enabledAt(WidgetTester tester, String label) => tester
    .getSemantics(byLabel(label))
    .getSemanticsData()
    .flagsCollection
    .isEnabled;

List<String> _highlighted(WidgetTester tester) => [
  for (final button in tester.widgetList<SceneButton>(find.byType(SceneButton)))
    if (button.highlighted) button.label,
];

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  Duration beat = const Duration(milliseconds: 100),
  int beats = 30,
}) async {
  for (var vez = 0; vez < beats && !done(); vez++) {
    await tester.pump(beat);
  }
}

Future<void> _theAnswerSettles(WidgetTester tester) async {
  for (var vez = 0; vez < 10; vez++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<(SalaHarness, ProviderContainer)> _seeded(
  WidgetTester tester,
  List<SceneRehearsalRecord> Function(String session) seed, {
  String lingua = 'pt',
  List<Scene> scenes = _threeScenes,
}) async {
  final harness = SalaHarness(lingua: lingua, filaEmMemoria: true)
    ..room.passages = const [_thePassage]
    ..room.nextMoment = _midConversation
    ..room.passageScenes = scenes;
  final container = await pumpSala(tester, harness);
  addTearDown(() => closeTheRoom(container));
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.abrirEscolha();
  await tester.pump(const Duration(milliseconds: 300));
  unawaited(notifier.goConversa(book: 'Ruth', pericope: 'P01'));
  await _pumpUntil(
    tester,
    () => container.read(salaSessionProvider).voice == VoiceState.invite,
  );
  await tester.pump(const Duration(milliseconds: 1500));
  harness.room.sceneRehearsals.addAll(
    seed(container.read(salaSessionProvider).sessionId!),
  );
  return (harness, container);
}

Future<void> _openThePlan(WidgetTester tester) async {
  await tester.tap(_dot);
  await tester.pump(const Duration(milliseconds: 100));
  await _theAnswerSettles(tester);
}

Future<void> _openTheSheetOf(WidgetTester tester, int n) async {
  final swap = _onRow(n, find.text(_swap));
  await tester.ensureVisible(swap);
  await tester.tap(swap);
  await _theAnswerSettles(tester);
}

Future<void> _tapLabel(WidgetTester tester, String label) async {
  await tester.ensureVisible(byLabel(label));
  await tester.tap(byLabel(label));
  await _theAnswerSettles(tester);
}

Future<void> _useThe(WidgetTester tester, String line) =>
    _tapLabel(tester, '$_useThis — $line');

Future<ProviderContainer> _relaunchOnTheConversation(
  WidgetTester tester,
  SalaHarness harness,
  ProviderContainer container,
) async {
  final (_, next) = await relaunch(
    harness,
    container,
    filaEmMemoria: true,
    tester: tester,
  );
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    UncontrolledProviderScope(container: next, child: const SalaApp()),
  );
  await tester.pump(const Duration(milliseconds: 100));
  final notifier = next.read(salaSessionProvider.notifier);
  await notifier.abrirEscolha();
  await tester.pump(const Duration(milliseconds: 300));
  unawaited(notifier.goConversa(book: 'Ruth', pericope: 'P01'));
  await _pumpUntil(
    tester,
    () => !next.read(salaSessionProvider).awaitingTheGuide,
  );
  for (var vez = 0; vez < 10; vez++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
  return next;
}

void _expectOnlyFacts(WidgetTester tester) {
  final fixed = {
    'Ensaio Final',
    'Voltar para a passagem atual',
    _planLine,
    _sceneByScene,
    _wholeAtOnce,
    'falta o ensaio desta cena',
    _cannotEnter,
    'tradução incompleta',
    _swap,
    _join,
    'Ouvir',
    _back,
    _useThis,
    _inUse,
    _recordAgain,
    _whichScene,
    _labelFailed,
    for (final (i, scene) in _threeScenes.indexed) ...[
      scene.title,
      'Cena ${i + 1}',
      'cena ${i + 1}',
      _sceneButton(i + 1),
      '${i + 1}',
    ],
  };
  final facts = RegExp(
    r'^ensaio \d+ · \d{2}:\d{2} · \d+:\d{2} · \d+ frases'
    r'( · (enviado|não enviado))?( · tradução incompleta)?$',
  );
  bool aFact(String said) =>
      fixed.contains(said) ||
      facts.hasMatch(said) ||
      said
          .split(' — ')
          .every((piece) => fixed.contains(piece) || facts.hasMatch(piece));

  final plan = find.byType(EnsaioFinalPlanView);
  final texts = tester
      .widgetList<Text>(find.descendant(of: plan, matching: find.byType(Text)))
      .map((text) => text.data ?? '');
  final labels = tester
      .widgetList<Semantics>(
        find.descendant(of: plan, matching: find.byType(Semantics)),
      )
      .map((widget) => widget.properties.label)
      .whereType<String>()
      .where((label) => label.isNotEmpty);

  expect(texts, isNotEmpty);
  for (final said in [...texts, ...labels]) {
    expect(aFact(said), isTrue, reason: '«$said» não é um fato do plano');
  }
}

void _on(WidgetTester tester, Size screen, {required double bar}) {
  tester.view
    ..physicalSize = screen
    ..devicePixelRatio = 1
    ..padding = FakeViewPadding(top: bar)
    ..viewPadding = FakeViewPadding(top: bar);
  addTearDown(tester.view.reset);
}

void _inTheDark(WidgetTester tester) {
  tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
}

double _seenOpacity(WidgetTester tester, Finder mark) {
  var seen = 1.0;
  mark.evaluate().first.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is Opacity) seen *= widget.opacity;
    return true;
  });
  return seen;
}

void main() {
  testWidgets(
    '1. the sheet of scene 1 lists its three rehearsals newest first with '
    'their facts, the one in use and «usar este» on the others',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await _seeded(tester, _threeOnSceneOne);
      await _openThePlan(tester);

      await _openTheSheetOf(tester, 1);

      expect(byLabel(_back), findsOneWidget);
      expect(find.text('Cena 1'), findsOneWidget);
      expect(find.text(_threeScenes[0].title), findsOneWidget);
      expect(find.text(_swap), findsOneWidget);
      expect(
        tester.getTopLeft(find.text(_swap)).dy,
        greaterThan(tester.getTopLeft(find.text(_threeScenes[0].title)).dy),
      );
      final lines = [_sent(3), _sent(2), _sent(1)];
      final tops = [
        for (final line in lines) tester.getTopLeft(find.text(line)).dy,
      ];
      expect(tops, orderedEquals(List.of(tops)..sort()));
      expect(find.text(_inUse), findsOneWidget);
      expect(_onLine(_sent(2), find.text(_inUse)), findsOneWidget);
      expect(byLabel('$_useThis — ${_sent(3)}'), findsOneWidget);
      expect(byLabel('$_useThis — ${_sent(1)}'), findsOneWidget);
      expect(byLabel('$_useThis — ${_sent(2)}'), findsNothing);
      expect(find.text(_useThis), findsNWidgets(2));
      expect(find.text(_recordAgain), findsOneWidget);
      expect(find.text(_planLine), findsNothing);
      semantics.dispose();
    },
  );

  testWidgets(
    '2. «usar este» on rehearsal 1 puts it on the plan, and only that tap does',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final (harness, _) = await _seeded(tester, _threeOnSceneOne);
      await _openThePlan(tester);
      await _openTheSheetOf(tester, 1);

      await _useThe(tester, _sent(1));

      expect(find.text(_planLine), findsOneWidget);
      expect(byLabel(_back), findsNothing);
      expect(_onRow(1, find.text(_facts(1))), findsOneWidget);
      expect(_onRow(1, find.text(_facts(2))), findsNothing);

      await _openTheSheetOf(tester, 1);

      expect(_onLine(_sent(1), find.text(_inUse)), findsOneWidget);
      expect(find.text(_inUse), findsOneWidget);
      expect(byLabel('$_useThis — ${_sent(3)}'), findsOneWidget);
      expect(byLabel('$_useThis — ${_sent(2)}'), findsOneWidget);
      expect(byLabel('$_useThis — ${_sent(1)}'), findsNothing);
      expect(harness.room.calls, isNot(contains('sendTake')));
      expect(await harness.takes.pending(), isEmpty);
      semantics.dispose();
    },
  );

  testWidgets('3. the back arrow returns to the plan unchanged', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final (harness, _) = await _seeded(tester, _threeOnSceneOne);
    await _openThePlan(tester);
    await _openTheSheetOf(tester, 1);

    await _tapLabel(tester, _back);

    expect(find.text(_planLine), findsOneWidget);
    expect(byLabel(_back), findsNothing);
    expect(_onRow(1, find.text(_facts(2))), findsOneWidget);
    expect(harness.room.labelsSent, isEmpty);
    expect(harness.room.calls, isNot(contains('sendTake')));
    semantics.dispose();
  });

  for (final (device, screen, bar, center) in [
    ('the SE', const Size(375, 667), 20.0, const Offset(42.5, 73.35)),
    ('an iPad', const Size(820, 1180), 24.0, const Offset(69.2, 103)),
  ]) {
    for (final (look, verdeClaro) in [
      ('light', const Color(0xFF777D45)),
      ('dark', const Color(0xFFAAB07E)),
    ]) {
      testWidgets(
        'on $device in the $look look the way back on the sheet is her bare '
        'chevron at 5% and 6%, at 0.6',
        (tester) async {
          _on(tester, screen, bar: bar);
          if (look == 'dark') _inTheDark(tester);
          final semantics = tester.ensureSemantics();
          await _seeded(tester, _threeOnSceneOne);
          await _openThePlan(tester);
          await _openTheSheetOf(tester, 1);

          final chevron = find.descendant(
            of: byLabel(_back),
            matching: find.byType(CustomPaint),
          );
          expectHerChevron(tester, chevron, verdeClaro);
          expect(
            _seenOpacity(tester, chevron),
            closeTo(0.6, 0.001),
            reason:
                'a volta da folha era desenhada por inteiro, não discreta como a dela',
          );
          final box = tester.getRect(byLabel(_back));
          expect(box.width, closeTo(44, 0.01));
          expect(box.height, closeTo(44, 0.01));
          expect(
            box.center.dx,
            closeTo(center.dx, 0.01),
            reason: 'a volta ficava na borda da coluna, não a 6% da tela',
          );
          expect(box.center.dy, closeTo(center.dy, 0.01));
          semantics.dispose();
        },
      );
    }
  }

  for (final (device, screen, bar) in [
    ('the SE', const Size(375, 667), 20.0),
    ('an iPad', const Size(820, 1180), 24.0),
  ]) {
    testWidgets(
      'on $device the title and the rehearsals start under the way back, '
      'never beneath it',
      (tester) async {
        _on(tester, screen, bar: bar);
        final semantics = tester.ensureSemantics();
        await _seeded(tester, _threeOnSceneOne);
        await _openThePlan(tester);
        await _openTheSheetOf(tester, 1);

        final back = tester.getRect(byLabel(_back));
        expect(
          tester.getTopLeft(find.text('Cena 1')).dy,
          greaterThanOrEqualTo(back.bottom),
          reason: 'o título começava no alto da folha, sob a volta',
        );
        expect(
          tester.getRect(byLabel(_sent(3))).top,
          greaterThanOrEqualTo(back.bottom),
          reason: 'as linhas começavam sob a volta',
        );
        semantics.dispose();
      },
    );
  }

  testWidgets(
    'on the SE the way back scrolls away with the sheet, as hers, instead of '
    'standing in a band of its own',
    (tester) async {
      _on(tester, const Size(375, 667), bar: 20);
      final semantics = tester.ensureSemantics();
      await _seeded(
        tester,
        (s) => [
          for (var n = 1; n <= 7; n++)
            _rehearsal(s, n: n, scene: 'S1', sentAt: _sentAt('10:0$n')),
        ],
      );
      await _openThePlan(tester);
      await _openTheSheetOf(tester, 1);

      final page = find.descendant(
        of: find.byType(RehearsalSheet),
        matching: find.byType(Scrollable),
      );
      expect(
        tester.getRect(page).top,
        0,
        reason: 'a folha rolava numa faixa abaixo da volta, não a tela toda',
      );
      final before = tester.getRect(byLabel(_back)).top;
      await tester.drag(page, const Offset(0, -120));
      await tester.pump(const Duration(milliseconds: 100));

      final scrolled = tester.state<ScrollableState>(page).position.pixels;
      expect(scrolled, greaterThan(0));
      expect(
        tester.getRect(byLabel(_back)).top,
        closeTo(before - scrolled, 0.01),
        reason: 'a volta ficava parada enquanto a folha rolava',
      );
      semantics.dispose();
    },
  );

  for (final (device, screen) in [
    ('the SE', const Size(375, 667)),
    ('an iPad', const Size(820, 1180)),
  ]) {
    testWidgets(
      'on $device «✓ em uso» and every «usar este» sit on their own line '
      'under the play, starting where the card starts, not where the facts do',
      (tester) async {
        _on(tester, screen, bar: 20);
        final semantics = tester.ensureSemantics();
        await _seeded(tester, _threeOnSceneOne);
        await _openThePlan(tester);
        await _openTheSheetOf(tester, 1);

        for (final (n, action) in [
          (3, byLabel('$_useThis — ${_sent(3)}')),
          (2, _onLine(_sent(2), find.text(_inUse))),
          (1, byLabel('$_useThis — ${_sent(1)}')),
        ]) {
          final facts = tester.getRect(find.text(_sent(n)));
          final play = tester.getRect(byLabel('Ouvir — ${_sent(n)}'));
          final said = tester.getRect(action);
          expect(
            said.left,
            closeTo(play.left, 0.01),
            reason:
                'a linha das ações começava sob os fatos, não no começo do '
                'cartão como a dela: ensaio $n',
          );
          expect(
            said.top,
            greaterThanOrEqualTo(facts.bottom),
            reason: 'a ação do ensaio $n dividia a linha com os fatos',
          );
          expect(said.top, greaterThanOrEqualTo(play.bottom));
        }
        semantics.dispose();
      },
    );
  }

  for (final (device, screen, left, right) in [
    ('the SE', const Size(375, 667), 30.0, 345.0),
    ('an iPad', const Size(820, 1180), 175.0, 645.0),
  ]) {
    testWidgets(
      'on $device the sheet stands in her centred column, never a wide one '
      'pushed to the left',
      (tester) async {
        _on(tester, screen, bar: 20);
        final semantics = tester.ensureSemantics();
        await _seeded(tester, _threeOnSceneOne);
        await _openThePlan(tester);
        await _openTheSheetOf(tester, 1);

        for (final n in [3, 2, 1]) {
          final card = tester.getRect(byLabel(_sent(n)));
          expect(
            card.left,
            closeTo(left, 0.01),
            reason: 'a coluna da folha tinha 600 de largura e 16 de margem',
          );
          expect(card.right, closeTo(right, 0.01));
        }
        for (final said in [
          'Cena 1',
          _threeScenes[0].title,
          _swap,
          _recordAgain,
        ]) {
          expect(
            tester.getCenter(find.text(said)).dx,
            closeTo(screen.width / 2, 0.01),
            reason: 'o texto da folha começava na borda esquerda: $said',
          );
        }
        semantics.dispose();
      },
    );
  }

  for (final (look, verde, verdeClaro) in [
    ('light', const Color(0xFF3F3E20), const Color(0xFF777D45)),
    ('dark', const Color(0xFFECEADC), const Color(0xFFAAB07E)),
  ]) {
    testWidgets(
      'in the $look look the sheet is headed in her verde and her quieter '
      'verde-claro, not in ink and grey',
      (tester) async {
        if (look == 'dark') _inTheDark(tester);
        final semantics = tester.ensureSemantics();
        await _seeded(tester, _threeOnSceneOne);
        await _openThePlan(tester);
        await _openTheSheetOf(tester, 1);

        TextStyle styleOf(String said) =>
            tester.widget<Text>(find.text(said)).style!;
        final heading = styleOf('Cena 1');
        expect(
          heading.fontSize,
          24,
          reason: 'o título da folha tinha 22 em tinta',
        );
        expect(heading.fontWeight, FontWeight.w500);
        expect(heading.color, verde);
        final scene = styleOf(_threeScenes[0].title);
        expect(
          scene.fontSize,
          closeTo(15.2, 0.001),
          reason: 'o nome da cena vinha no cinza do texto',
        );
        expect(scene.fontWeight, FontWeight.w400);
        expect(scene.color, verdeClaro);
        final sub = styleOf(_swap);
        expect(
          sub.fontSize,
          closeTo(14.72, 0.001),
          reason: 'a linha de baixo tinha 14 em cinza',
        );
        expect(sub.color, verdeClaro);
        semantics.dispose();
      },
    );
  }

  for (final (look, areia, azul, fill) in [
    (
      'light',
      const Color(0xFFC5C29F),
      const Color(0xFF89AAA3),
      const Color.fromRGBO(255, 255, 255, .4),
    ),
    (
      'dark',
      const Color(0xFF6E6A57),
      const Color(0xFF8FB1A9),
      const Color.fromRGBO(236, 234, 220, .05),
    ),
  ]) {
    testWidgets(
      'in the $look look each rehearsal is her framed card, the one in use '
      'framed in azul, not a row over a hairline',
      (tester) async {
        if (look == 'dark') _inTheDark(tester);
        final semantics = tester.ensureSemantics();
        await _seeded(tester, _threeOnSceneOne);
        await _openThePlan(tester);
        await _openTheSheetOf(tester, 1);

        final lines = [_sent(3), _sent(2), _sent(1)];
        for (final line in lines) {
          final card =
              tester
                      .widget<DecoratedBox>(
                        find
                            .descendant(
                              of: byLabel(line),
                              matching: find.byType(DecoratedBox),
                            )
                            .first,
                      )
                      .decoration
                  as BoxDecoration;
          expect(
            card.border,
            Border.all(color: line == _sent(2) ? azul : areia, width: 1.2),
            reason: 'cada ensaio era uma linha sobre um fio, sem moldura',
          );
          expect(card.borderRadius, BorderRadius.circular(14));
          expect(card.color, fill);
          final play = tester.getRect(byLabel('Ouvir — $line'));
          expect(
            play.left - tester.getRect(byLabel(line)).left,
            closeTo(1.2 + 12, 0.01),
            reason: 'o play encostava a 8 da borda da linha',
          );
        }
        for (var i = 1; i < lines.length; i++) {
          expect(
            tester.getRect(byLabel(lines[i])).top -
                tester.getRect(byLabel(lines[i - 1])).bottom,
            closeTo(8.8, 0.01),
            reason: 'as linhas da folha se encostavam umas nas outras',
          );
        }
        semantics.dispose();
      },
    );
  }

  testWidgets(
    '4. an unsent rehearsal is listed «não enviado» with «usar este», and once '
    'used it holds the row and opens «juntar»',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await _seeded(
        tester,
        (s) => [_rehearsal(s, n: 2, scene: 'S2', sentAt: null)],
      );
      await _openThePlan(tester);
      expect(_enabledAt(tester, _join), Tristate.isFalse);

      await _openTheSheetOf(tester, 2);

      final unsent = '${_facts(2)} · não enviado';
      expect(find.text(unsent), findsOneWidget);
      expect(
        byLabel('$_useThis — $unsent'),
        findsOneWidget,
        reason: 'o ensaio não enviado aparecia na folha sem como ser usado',
      );
      expect(_onLine(unsent, find.text(_inUse)), findsNothing);
      expect(_onLine(unsent, find.text(_cannotEnter)), findsNothing);

      await _useThe(tester, unsent);

      expect(find.text(_planLine), findsOneWidget);
      expect(_onRow(2, find.text(_facts(2))), findsOneWidget);
      expect(_onRow(2, find.text('falta o ensaio desta cena')), findsNothing);
      expect(
        _enabledAt(tester, _join),
        Tristate.isTrue,
        reason: 'escolher o ensaio não enviado não abria o juntar',
      );
      semantics.dispose();
    },
  );

  group('5. a sent rehearsal that cannot enter says why and offers no '
      '«usar este»', () {
    for (final (why, rehearsal) in [
      (
        'audio/mp4',
        (String s) =>
            _rehearsal(s, n: 5, scene: 'S2', contentType: 'audio/mp4'),
      ),
      (
        'not verified',
        (String s) => _rehearsal(s, n: 5, scene: 'S2', verified: false),
      ),
    ]) {
      testWidgets('when it is $why', (tester) async {
        final semantics = tester.ensureSemantics();
        await _seeded(
          tester,
          (s) => [
            _rehearsal(s, n: 3, scene: 'S2', sentAt: _sentAt('10:00')),
            _rehearsal(s, n: 4, scene: 'S2', sentAt: _sentAt('10:05')),
            rehearsal(s),
          ],
        );
        await _openThePlan(tester);

        await _openTheSheetOf(tester, 2);

        expect(_onLine(_sent(5), find.text(_cannotEnter)), findsOneWidget);
        expect(byLabel('$_useThis — ${_sent(5)}'), findsNothing);
        expect(_onLine(_sent(5), find.text(_inUse)), findsNothing);
        expect(_onLine(_sent(4), find.text(_inUse)), findsOneWidget);
        semantics.dispose();
      });
    }
  });

  for (final (look, verdeClaro, telha) in [
    ('light', const Color(0xFF777D45), const Color(0xFFBE4A01)),
    ('dark', const Color(0xFFAAB07E), const Color(0xFFD6612A)),
  ]) {
    testWidgets(
      'in the $look look the facts are her small verde-claro figures and the '
      'note her smaller telha under them',
      (tester) async {
        if (look == 'dark') _inTheDark(tester);
        final semantics = tester.ensureSemantics();
        await _seeded(
          tester,
          (s) => [
            _rehearsal(s, n: 4, scene: 'S2', sentAt: _sentAt('10:05')),
            _rehearsal(s, n: 5, scene: 'S2', contentType: 'audio/mp4'),
          ],
        );
        await _openThePlan(tester);
        await _openTheSheetOf(tester, 2);

        for (final line in [_sent(4), _sent(5)]) {
          final facts = tester.widget<Text>(find.text(line)).style!;
          expect(
            facts.fontSize,
            closeTo(12.48, 0.001),
            reason: 'os fatos tinham 15 em tinta',
          );
          expect(facts.color, verdeClaro);
          expect(facts.fontFeatures, [const FontFeature.tabularFigures()]);
        }
        final note = _onLine(_sent(5), find.text(_cannotEnter));
        final style = tester.widget<Text>(note).style!;
        expect(
          style.fontSize,
          closeTo(12.16, 0.001),
          reason: 'a nota tinha 14, maior que os fatos dela',
        );
        expect(style.color, telha);
        final facts = tester.getRect(find.text(_sent(5)));
        expect(tester.getRect(note).left, closeTo(facts.left, 0.01));
        expect(tester.getRect(note).top, greaterThanOrEqualTo(facts.bottom));
        semantics.dispose();
      },
    );
  }

  for (final (look, verde) in [
    ('light', const Color(0xFF3F3E20)),
    ('dark', const Color(0xFFECEADC)),
  ]) {
    testWidgets(
      'in the $look look «✓ em uso» is her small bold verde badge, not grey '
      'body text',
      (tester) async {
        if (look == 'dark') _inTheDark(tester);
        final semantics = tester.ensureSemantics();
        await _seeded(tester, _threeOnSceneOne);
        await _openThePlan(tester);
        await _openTheSheetOf(tester, 1);

        final badge = tester
            .widget<Text>(_onLine(_sent(2), find.text(_inUse)))
            .style!;
        expect(
          badge.fontSize,
          closeTo(12.8, 0.001),
          reason: '«✓ em uso» tinha 15 no cinza do texto',
        );
        expect(badge.fontWeight, FontWeight.w600);
        expect(badge.color, verde);
        semantics.dispose();
      },
    );
  }

  for (final (look, areia, verdeClaro) in [
    ('light', const Color(0xFFC5C29F), const Color(0xFF777D45)),
    ('dark', const Color(0xFF6E6A57), const Color(0xFFAAB07E)),
  ]) {
    testWidgets(
      'in the $look look «usar este» is her quiet bordered pill, not a telha '
      'word',
      (tester) async {
        if (look == 'dark') _inTheDark(tester);
        final semantics = tester.ensureSemantics();
        await _seeded(tester, _threeOnSceneOne);
        await _openThePlan(tester);
        await _openTheSheetOf(tester, 1);

        final button = byLabel('$_useThis — ${_sent(3)}');
        final pill =
            tester
                    .widget<DecoratedBox>(
                      find
                          .descendant(
                            of: button,
                            matching: find.byType(DecoratedBox),
                          )
                          .first,
                    )
                    .decoration
                as BoxDecoration;
        expect(
          pill.border,
          Border.all(color: areia, width: 1.4),
          reason: '«usar este» era uma palavra telha solta, sem a borda dela',
        );
        expect(pill.borderRadius, BorderRadius.circular(999));
        expect(pill.color, isNull);
        final word = find.descendant(of: button, matching: find.text(_useThis));
        final style = tester.widget<Text>(word).style!;
        expect(style.fontSize, closeTo(13.44, 0.001));
        expect(style.color, verdeClaro);
        final frame = tester.getRect(
          find
              .descendant(of: button, matching: find.byType(DecoratedBox))
              .first,
        );
        expect(
          tester.getRect(word).left - frame.left,
          closeTo(1.4 + 17.6, 0.01),
        );
        expect(tester.getRect(word).top - frame.top, closeTo(1.4 + 8, 0.01));
        semantics.dispose();
      },
    );
  }

  testWidgets(
    'on the SE «usar este» takes a finger over 44 high while its frame stays '
    'her size',
    (tester) async {
      _on(tester, const Size(375, 667), bar: 20);
      final semantics = tester.ensureSemantics();
      await _seeded(tester, _threeOnSceneOne);
      await _openThePlan(tester);
      await _openTheSheetOf(tester, 1);

      final button = byLabel('$_useThis — ${_sent(3)}');
      await tester.ensureVisible(button);
      await tester.pump();
      final hit = tester.getRect(button);
      final frame = tester.getRect(
        find.descendant(of: button, matching: find.byType(DecoratedBox)).first,
      );
      expect(
        hit.height,
        greaterThanOrEqualTo(44),
        reason: 'a pílula só aceitava o dedo dentro da moldura, abaixo de 44',
      );
      expect(frame.height, lessThan(44));

      await tester.tapAt(Offset(frame.center.dx, hit.top + 1));
      await _theAnswerSettles(tester);

      expect(
        find.text(_planLine),
        findsOneWidget,
        reason: 'um toque logo acima da moldura não usava o ensaio',
      );
      expect(_onRow(1, find.text(_facts(3))), findsOneWidget);
      semantics.dispose();
    },
  );

  for (final (look, verdeClaro) in [
    ('light', const Color(0xFF777D45)),
    ('dark', const Color(0xFFAAB07E)),
  ]) {
    testWidgets(
      'in the $look look «gravar esta cena de novo» is her quiet underlined '
      'link at .7, not a telha button',
      (tester) async {
        if (look == 'dark') _inTheDark(tester);
        final semantics = tester.ensureSemantics();
        await _seeded(tester, _threeOnSceneOne);
        await _openThePlan(tester);
        await _openTheSheetOf(tester, 1);

        final foot = find.text(_recordAgain);
        final style = tester.widget<Text>(foot).style!;
        expect(
          style.color,
          verdeClaro,
          reason: 'o pé da folha era um botão telha de 15',
        );
        expect(style.fontSize, closeTo(13.44, 0.001));
        expect(style.decoration, TextDecoration.underline);
        expect(_seenOpacity(tester, foot), closeTo(0.7, 0.001));
        expect(
          find.ancestor(of: foot, matching: find.byType(TextButton)),
          findsOneWidget,
        );
        semantics.dispose();
      },
    );
  }

  testWidgets(
    'the line in use is announced as the selected one, and no other line is',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await _seeded(tester, _threeOnSceneOne);
      await _openThePlan(tester);
      await _openTheSheetOf(tester, 1);

      expect(
        _pressedAt(tester, _sent(2)),
        Tristate.isTrue,
        reason: 'a linha em uso só dizia «✓ em uso» em texto, sem o estado',
      );
      for (final n in [3, 1]) {
        expect(_pressedAt(tester, _sent(n)), isNot(Tristate.isTrue));
      }
      await _tapLabel(tester, 'Ouvir — ${_sent(3)}');
      expect(_pressedAt(tester, 'Ouvir — ${_sent(3)}'), Tristate.isTrue);
      expect(
        _pressedAt(tester, _sent(3)),
        isNot(Tristate.isTrue),
        reason: 'a linha que toca não é a linha em uso',
      );
      await _tapLabel(tester, 'Ouvir — ${_sent(3)}');

      await _useThe(tester, _sent(1));
      await _openTheSheetOf(tester, 1);

      expect(_pressedAt(tester, _sent(1)), Tristate.isTrue);
      expect(_pressedAt(tester, _sent(2)), isNot(Tristate.isTrue));
      semantics.dispose();
    },
  );

  testWidgets(
    'the sheet opens with VoiceOver on «Cena 1 — A fome em Belém», announced '
    'as a heading, not on two mute lines of text',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await _seeded(tester, _threeOnSceneOne);
      await _openThePlan(tester);
      await _openTheSheetOf(tester, 1);

      final heading = byLabel('Cena 1 — A fome em Belém');
      expect(
        heading,
        findsOneWidget,
        reason: 'o título da folha era texto mudo, sem nome para o VoiceOver',
      );
      final data = tester.getSemantics(heading).getSemanticsData();
      expect(
        data.flagsCollection.isHeader,
        isTrue,
        reason: 'o título não era anunciado como cabeçalho, como o h1 dela',
      );
      expect(
        data.flagsCollection.isFocused,
        Tristate.isTrue,
        reason: 'a folha abria sem levar o VoiceOver ao seu título',
      );
      semantics.dispose();
    },
  );

  testWidgets(
    '6. a rehearsal with an untranslated stretch reads «tradução incompleta» '
    'on its line and can still be used',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await _seeded(
        tester,
        (s) => [
          _rehearsal(
            s,
            n: 3,
            scene: 'S1',
            sentAt: _sentAt('10:00'),
            durationMs: 11000,
            frases: const [
              SceneFrase(fraseId: 'a', startsMs: 0, endsMs: 5000),
              SceneFrase(fraseId: 'b', startsMs: 5000, endsMs: 8000),
            ],
          ),
          _rehearsal(s, n: 1, scene: 'S1', sentAt: _sentAt('10:05')),
        ],
      );
      await _openThePlan(tester);

      await _openTheSheetOf(tester, 1);

      final partial = '${_sent(3, dur: '0:11')} · tradução incompleta';
      expect(find.text(partial), findsOneWidget);
      expect(byLabel('$_useThis — $partial'), findsOneWidget);

      await _useThe(tester, partial);

      expect(_onRow(1, find.text(_facts(3, dur: '0:11'))), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets(
    '7. «gravar esta cena de novo» opens the scene rehearsal screen with that '
    'scene highlighted and the question still asked',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await _seeded(
        tester,
        (s) => [
          _rehearsal(s, n: 1, scene: 'S1'),
          _rehearsal(s, n: 2, scene: 'S2', sentAt: _sentAt('10:00')),
          _rehearsal(s, n: 3, scene: 'S2', sentAt: _sentAt('10:05')),
        ],
      );
      await _openThePlan(tester);
      await _openTheSheetOf(tester, 2);

      await tester.ensureVisible(find.text(_recordAgain));
      await tester.tap(find.text(_recordAgain));
      await _pumpUntil(tester, () => byLabel(_question).evaluate().isNotEmpty);
      await tester.pump(const Duration(seconds: 1));

      expect(byLabel(_question), findsOneWidget);
      expect(_highlighted(tester), [_sceneButton(2)]);
      for (final circle in _circle) {
        expect(byLabel(circle), findsNothing, reason: 'nada foi escolhido');
      }

      await tester.tap(byLabel(_houseBack));
      await _pumpUntil(tester, () => byLabel(_question).evaluate().isEmpty);
      await _theAnswerSettles(tester);

      expect(byLabel(_question), findsNothing);
      expect(_dot, findsOneWidget);

      await _openThePlan(tester);

      expect(find.text(_planLine), findsOneWidget);
      expect(byLabel(_back), findsNothing);
      semantics.dispose();
    },
  );

  testWidgets(
    '7. «gravar esta cena de novo» asks the question even when the session\'s '
    'newest rehearsal is unsent',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await _seeded(
        tester,
        (s) => [
          _rehearsal(s, n: 2, scene: 'S2', sentAt: _sentAt('10:00')),
          _rehearsal(s, n: 3, scene: 'S2', sentAt: _sentAt('10:05')),
          _rehearsal(s, n: 4, scene: 'S1', sentAt: null),
        ],
      );
      await _openThePlan(tester);
      await _openTheSheetOf(tester, 2);

      await tester.ensureVisible(find.text(_recordAgain));
      await tester.tap(find.text(_recordAgain));
      await _pumpUntil(tester, () => byLabel(_question).evaluate().isNotEmpty);
      await tester.pump(const Duration(seconds: 1));

      expect(byLabel(_question), findsOneWidget);
      expect(_highlighted(tester), [_sceneButton(2)]);
      for (final circle in _circle) {
        expect(byLabel(circle), findsNothing, reason: 'nada foi escolhido');
      }
      semantics.dispose();
    },
  );

  testWidgets(
    '7. «gravar esta cena de novo» brings back a scene take still waiting in '
    'the Outbox',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final (harness, container) = await _seeded(
        tester,
        (s) => [
          _rehearsal(s, n: 2, scene: 'S2', sentAt: _sentAt('10:00')),
          _rehearsal(s, n: 3, scene: 'S2', sentAt: _sentAt('10:05')),
        ],
      );
      await harness.takes.enqueue(
        harness.recorder.aFile('cena-que-espera'),
        sessionId: container.read(salaSessionProvider).sessionId!,
        kind: 'cena',
        scope: 'cena',
        scene: 'S1',
      );
      await _openThePlan(tester);
      await _openTheSheetOf(tester, 2);

      await tester.ensureVisible(find.text(_recordAgain));
      await tester.tap(find.text(_recordAgain));
      await _pumpUntil(
        tester,
        () => find.byType(SceneChip).evaluate().isNotEmpty,
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(SceneChip), findsOneWidget);
      expect(
        tester.widget<SceneChip>(find.byType(SceneChip)).words,
        contains(_threeScenes[0].title),
      );
      expect(byLabel(_question), findsNothing);
      semantics.dispose();
    },
  );

  testWidgets('8. play on a line plays that rehearsal, and a second tap stops '
      'it', (tester) async {
    final semantics = tester.ensureSemantics();
    final (harness, _) = await _seeded(tester, _threeOnSceneOne);
    await _openThePlan(tester);
    await _openTheSheetOf(tester, 1);
    final sessionId = harness.room.sceneRehearsals.first.sessionId;

    await _tapLabel(tester, 'Ouvir — ${_sent(3)}');

    expect(
      harness.room.clipsFetched,
      contains(
        endsWith(
          '/sessions/$sessionId/scene-rehearsals/$sessionId-ensaio-3/audio',
        ),
      ),
    );
    expect(harness.playback.played.last, contains('$sessionId-ensaio-3'));
    expect(harness.playback.sounding, isTrue);

    await _tapLabel(tester, 'Ouvir — ${_sent(3)}');

    expect(harness.playback.sounding, isFalse);
    expect(byLabel(_back), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('9. the sheet speaks her English in an English room', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _seeded(
      tester,
      lingua: 'en',
      scenes: _threeScenesEn,
      _threeOnSceneOne,
    );
    await _openThePlan(tester);
    const swapEn = 'use another rehearsal for this scene';
    await tester.tap(
      find.descendant(
        of: byLabel('Scene 1 — ${_threeScenesEn[0].title}'),
        matching: find.text(swapEn),
      ),
    );
    await _theAnswerSettles(tester);

    final clock = _clock(_recordedAt);
    final line3 = 'rehearsal 3 · $clock · 0:07 · 2 sentences · sent';
    expect(byLabel('Back to recording'), findsOneWidget);
    expect(find.text('Scene 1'), findsOneWidget);
    expect(find.text(swapEn), findsOneWidget);
    expect(find.text(line3), findsOneWidget);
    expect(find.text('✓ in use'), findsOneWidget);
    expect(byLabel('use this one — $line3'), findsOneWidget);
    expect(byLabel('Listen — $line3'), findsOneWidget);
    expect(find.text('record this scene again'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets(
    'the card is headed by «De que cena é este ensaio?» as a heading, not by '
    'a line of text',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await _seeded(tester, _twoUnlabelled);
      await _openThePlan(tester);

      final title = tester
          .getSemantics(_onCard(find.text(_whichScene)))
          .getSemanticsData();
      expect(
        title.flagsCollection.isHeader,
        isTrue,
        reason: 'o título do cartão era texto mudo, sem ser um título',
      );
      expect(title.headingLevel, 2);
      expect(title.label, _whichScene);
      expect(byLabel(_whichScene), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets(
    '10. the card puts the older unlabelled rehearsal first, and a scene tap '
    'labels it and shows the next',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final (harness, _) = await _seeded(tester, _twoUnlabelled);
      final sessionId = harness.room.sceneRehearsals.first.sessionId;
      await _openThePlan(tester);

      expect(byLabel(_whichScene), findsOneWidget);
      expect(_onCard(find.text(_whichScene)), findsOneWidget);
      expect(_onCard(find.text(_facts(4))), findsOneWidget);
      expect(_onCard(find.text(_facts(6))), findsNothing);
      expect(_onCard(byLabel('Ouvir — ${_facts(4)}')), findsOneWidget);
      for (final n in [1, 2, 3]) {
        expect(_onCard(byLabel(_sceneButton(n))), findsOneWidget);
      }
      expect(_highlighted(tester), isEmpty);
      expect(_onRow(2, find.text(_swap)), findsNothing);

      await _tapLabel(tester, _sceneButton(2));

      expect(harness.room.labelsSent, [
        (rehearsalId: '$sessionId-ensaio-4', scene: 'S2'),
      ]);
      expect(_onCard(find.text(_facts(6))), findsOneWidget);
      expect(_onCard(find.text(_facts(4))), findsNothing);

      await _openTheSheetOf(tester, 2);

      expect(find.text(_sent(4)), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets(
    'the card steps through every unlabelled rehearsal of the session, '
    'oldest first, with next and previous',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final (harness, _) = await _seeded(tester, _threeUnlabelled);
      await _openThePlan(tester);

      expect(_shows(4), findsOneWidget);
      await _stepTo(tester, 5);
      expect(_shows(5), findsOneWidget);
      await _stepTo(tester, 6);
      expect(_shows(6), findsOneWidget);
      await _stepTo(tester, 5);
      expect(_shows(5), findsOneWidget);
      expect(harness.room.labelsSent, isEmpty);
      semantics.dispose();
    },
  );

  testWidgets(
    'previous stands before the play and next after the facts, as hers',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await _seeded(tester, _threeUnlabelled);
      await _openThePlan(tester);
      await _stepTo(tester, 5);

      final play = tester.getCenter(_onCard(byLabel('Ouvir — ${_facts(5)}')));
      final facts = tester.getCenter(_shows(5));
      expect(tester.getCenter(_step(4)).dx, lessThan(play.dx));
      expect(tester.getCenter(_step(6)).dx, greaterThan(facts.dx));
      semantics.dispose();
    },
  );

  testWidgets('at the oldest rehearsal the card offers no previous, and at the '
      'newest no next', (tester) async {
    final semantics = tester.ensureSemantics();
    await _seeded(tester, _threeUnlabelled);
    await _openThePlan(tester);

    expect(_step(5), findsOneWidget);
    expect(_step(4), findsNothing);
    expect(_step(6), findsNothing);
    await _stepTo(tester, 5);
    await _stepTo(tester, 6);
    expect(_step(5), findsOneWidget);
    expect(_step(4), findsNothing);
    expect(_step(6), findsNothing);
    semantics.dispose();
  });

  testWidgets(
    'a card with one unlabelled rehearsal offers neither previous nor next',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await _seeded(
        tester,
        (s) => [
          _rehearsal(s, n: 1, scene: 'S1'),
          _rehearsal(s, n: 4, scene: null),
        ],
      );
      await _openThePlan(tester);

      expect(_shows(4), findsOneWidget);
      for (final n in [1, 4]) {
        expect(_step(n), findsNothing);
      }
      semantics.dispose();
    },
  );

  testWidgets(
    'each step is named by the rehearsal it goes to, in her English in an '
    'English room',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await _seeded(
        tester,
        lingua: 'en',
        scenes: _threeScenesEn,
        _threeUnlabelled,
      );
      await _openThePlan(tester);

      final clock = _clock(_recordedAt);
      expect(
        find.descendant(
          of: byLabel('Which scene is this rehearsal?'),
          matching: byLabel('rehearsal 5 · $clock · 0:07 · 2 sentences'),
        ),
        findsOneWidget,
      );
      semantics.dispose();
    },
  );

  testWidgets(
    'placing a stepped-to rehearsal labels that rehearsal and moves the '
    'card to the next remaining',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final (harness, _) = await _seeded(tester, _threeUnlabelled);
      final sessionId = harness.room.sceneRehearsals.first.sessionId;
      await _openThePlan(tester);
      await _stepTo(tester, 5);

      await _tapLabel(tester, _sceneButton(2));

      expect(harness.room.labelsSent, [
        (rehearsalId: '$sessionId-ensaio-5', scene: 'S2'),
      ]);
      expect(_shows(6), findsOneWidget);
      expect(_step(4), findsOneWidget);
      expect(_step(5), findsNothing);
      semantics.dispose();
    },
  );

  testWidgets(
    'placing the newest rehearsal moves the card back to the one before it',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final (harness, _) = await _seeded(tester, _threeUnlabelled);
      final sessionId = harness.room.sceneRehearsals.first.sessionId;
      await _openThePlan(tester);
      await _stepTo(tester, 5);
      await _stepTo(tester, 6);

      await _tapLabel(tester, _sceneButton(3));

      expect(harness.room.labelsSent, [
        (rehearsalId: '$sessionId-ensaio-6', scene: 'S3'),
      ]);
      expect(_shows(5), findsOneWidget);
      expect(_step(4), findsOneWidget);
      expect(_step(6), findsNothing);
      semantics.dispose();
    },
  );

  testWidgets(
    'the card keeps the rehearsal it stepped to across a scene\'s sheet',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await _seeded(tester, _threeUnlabelled);
      await _openThePlan(tester);
      await _stepTo(tester, 5);

      await _openTheSheetOf(tester, 1);
      await _tapLabel(tester, _back);

      expect(_shows(5), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets('the steps rest while a label is in the air', (tester) async {
    final semantics = tester.ensureSemantics();
    final (harness, _) = await _seeded(tester, _threeUnlabelled);
    await _openThePlan(tester);
    await _stepTo(tester, 5);
    harness.room.holdTheLabel();

    await _tapLabel(tester, _sceneButton(2));

    expect(_enabledAt(tester, _facts(4)), Tristate.isFalse);
    expect(_enabledAt(tester, _facts(6)), Tristate.isFalse);
    await tester.tap(_step(4), warnIfMissed: false);
    await _theAnswerSettles(tester);
    expect(_shows(5), findsOneWidget);

    harness.room.releaseTheLabel();
    await _theAnswerSettles(tester);
    await tester.pump(const Duration(milliseconds: 600));

    expect(_enabledAt(tester, _facts(4)), Tristate.isTrue);
    semantics.dispose();
  });

  testWidgets('a relaunch opens the card on the oldest again', (tester) async {
    final semantics = tester.ensureSemantics();
    final (harness, container) = await _seeded(tester, _threeUnlabelled);
    await _openThePlan(tester);
    await _stepTo(tester, 5);
    await _stepTo(tester, 6);

    final next = await _relaunchOnTheConversation(tester, harness, container);
    addTearDown(() => closeTheRoom(next));
    await _openThePlan(tester);

    expect(_shows(4), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a step is pressed through its semantics action', (tester) async {
    final semantics = tester.ensureSemantics();
    await _seeded(tester, _threeUnlabelled);
    await _openThePlan(tester);

    tester.semantics.tap(find.semantics.byLabel(_facts(5)));
    await _theAnswerSettles(tester);

    expect(_shows(5), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a refused label shows its line only on the rehearsal refused', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final (harness, _) = await _seeded(tester, _threeUnlabelled);
    await _openThePlan(tester);
    harness.room.labelAnswersFirst.add(const NetworkFailed('sem rede'));

    await _tapLabel(tester, _sceneButton(2));
    expect(_onCard(find.text(_labelFailed)), findsOneWidget);

    await _stepTo(tester, 5);
    expect(_onCard(find.text(_labelFailed)), findsNothing);

    await _stepTo(tester, 4);
    expect(_onCard(find.text(_labelFailed)), findsOneWidget);
    semantics.dispose();
  });

  group('11. a label that cannot be stored says so, and the rehearsal stays '
      'on the card', () {
    for (final (why, failure) in <(String, RoomFailure)>[
      ('the network fails', const NetworkFailed('sem rede')),
      ('the room refuses it', const Refused(RefusalCode.notFound)),
    ]) {
      testWidgets('when $why', (tester) async {
        final semantics = tester.ensureSemantics();
        final (harness, _) = await _seeded(tester, _twoUnlabelled);
        await _openThePlan(tester);
        harness.room.labelAnswersFirst.add(failure);

        await _tapLabel(tester, _sceneButton(2));

        expect(_onCard(find.text(_labelFailed)), findsOneWidget);
        expect(_onCard(find.text(_facts(4))), findsOneWidget);
        expect(find.text(_facts(4)), findsOneWidget, reason: 'nenhuma linha');
        expect(_onRow(2, find.text(_swap)), findsNothing);

        await _tapLabel(tester, _sceneButton(2));

        expect(find.text(_labelFailed), findsNothing);
        expect(_onCard(find.text(_facts(6))), findsOneWidget);
        semantics.dispose();
      });
    }
  });

  testWidgets(
    '12. a rehearsal labelled with a scene this passage lacks is on the card '
    'too',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final (harness, _) = await _seeded(
        tester,
        (s) => [_rehearsal(s, n: 4, scene: 'S9')],
      );
      final sessionId = harness.room.sceneRehearsals.first.sessionId;
      await _openThePlan(tester);

      expect(_onCard(find.text(_facts(4))), findsOneWidget);

      await _tapLabel(tester, _sceneButton(1));

      expect(harness.room.labelsSent, [
        (rehearsalId: '$sessionId-ensaio-4', scene: 'S1'),
      ]);
      semantics.dispose();
    },
  );

  testWidgets('13. one label at a time', (tester) async {
    final semantics = tester.ensureSemantics();
    final (harness, _) = await _seeded(tester, _twoUnlabelled);
    await _openThePlan(tester);
    harness.room.holdTheLabel();

    await _tapLabel(tester, _sceneButton(2));

    for (final n in [1, 2, 3]) {
      expect(_enabledAt(tester, _sceneButton(n)), Tristate.isFalse);
    }

    await _tapLabel(tester, _sceneButton(3));
    await _tapLabel(tester, 'Ouvir — ${_facts(1)}');

    expect(harness.room.labelsSent, hasLength(1));
    expect(
      harness.room.clipsFetched,
      isNot(contains(endsWith('ensaio-1/audio'))),
    );

    harness.room.releaseTheLabel();
    await _theAnswerSettles(tester);

    expect(_onCard(find.text(_facts(6))), findsOneWidget);
    for (final n in [1, 2, 3]) {
      expect(_enabledAt(tester, _sceneButton(n)), Tristate.isTrue);
    }
    semantics.dispose();
  });

  testWidgets(
    '13. a double tap on a scene labels only the rehearsal the card showed',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final (harness, _) = await _seeded(tester, _twoUnlabelled);
      final sessionId = harness.room.sceneRehearsals.first.sessionId;
      await _openThePlan(tester);
      await tester.ensureVisible(byLabel(_sceneButton(2)));
      await tester.pump();
      final where = tester.getCenter(byLabel(_sceneButton(2)));

      await tester.tapAt(where);
      await tester.pump(const Duration(milliseconds: 120));
      await tester.tapAt(where);
      await tester.pump(const Duration(milliseconds: 100));

      expect(harness.room.labelsSent, [
        (rehearsalId: '$sessionId-ensaio-4', scene: 'S2'),
      ]);
      expect(_onCard(find.text(_facts(6))), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 600));
      semantics.dispose();
    },
  );

  testWidgets(
    '13. the next rehearsal on the card takes a tap once 0.6 s have passed',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final (harness, _) = await _seeded(tester, _twoUnlabelled);
      final sessionId = harness.room.sceneRehearsals.first.sessionId;
      await _openThePlan(tester);
      await _tapLabel(tester, _sceneButton(2));
      await tester.pump(const Duration(milliseconds: 600));

      await _tapLabel(tester, _sceneButton(1));

      expect(harness.room.labelsSent, [
        (rehearsalId: '$sessionId-ensaio-4', scene: 'S2'),
        (rehearsalId: '$sessionId-ensaio-6', scene: 'S1'),
      ]);
      semantics.dispose();
    },
  );

  testWidgets(
    '13. a double tap on the last unlabelled rehearsal\'s scene moves '
    'neither «juntar» nor «Gravar cena por cena»',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final (harness, _) = await _seeded(
        tester,
        (s) => [
          _rehearsal(s, n: 1, scene: 'S1'),
          _rehearsal(s, n: 4, scene: null),
        ],
      );
      await _openThePlan(tester);
      await tester.ensureVisible(byLabel(_sceneButton(2)));
      await tester.pump();
      final where = tester.getCenter(byLabel(_sceneButton(2)));

      await tester.tapAt(where);
      await tester.pump(const Duration(milliseconds: 120));
      await tester.tapAt(where);
      await tester.pump(const Duration(milliseconds: 100));

      expect(byLabel(_whichScene), findsNothing);
      expect(_enabledAt(tester, _join), Tristate.isFalse);
      await tester.ensureVisible(find.text(_sceneByScene));
      await tester.tap(find.text(_sceneByScene));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text(_planLine), findsOneWidget);
      expect(harness.room.labelsSent, hasLength(1));
      await tester.pump(const Duration(milliseconds: 600));
      expect(_enabledAt(tester, _join), Tristate.isTrue);
      semantics.dispose();
    },
  );

  group('14. the sheet and the card show only facts', () {
    testWidgets('over the sheet', (tester) async {
      final semantics = tester.ensureSemantics();
      await _seeded(tester, _threeOnSceneOne);
      await _openThePlan(tester);
      await _openTheSheetOf(tester, 1);

      expect(byLabel(_back), findsOneWidget);
      _expectOnlyFacts(tester);
      semantics.dispose();
    });

    testWidgets('over the card', (tester) async {
      final semantics = tester.ensureSemantics();
      await _seeded(tester, _twoUnlabelled);
      await _openThePlan(tester);

      expect(byLabel(_whichScene), findsOneWidget);
      _expectOnlyFacts(tester);
      semantics.dispose();
    });
  });

  group('15. the sheet lasts one visit of the plan', () {
    testWidgets('and is gone after a relaunch, the choice with it', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final (harness, container) = await _seeded(tester, _threeOnSceneOne);
      await _openThePlan(tester);
      await _openTheSheetOf(tester, 1);
      await _useThe(tester, _sent(1));
      await _openTheSheetOf(tester, 1);

      final next = await _relaunchOnTheConversation(tester, harness, container);
      addTearDown(() => closeTheRoom(next));

      expect(_dot, findsOneWidget);
      await _openThePlan(tester);

      expect(byLabel(_back), findsNothing);
      expect(_onRow(1, find.text(_facts(2))), findsOneWidget);
      semantics.dispose();
    });

    testWidgets(
      'and a new tap of the dot opens the plan with no sheet and no failure '
      'line',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final (harness, _) = await _seeded(
          tester,
          (s) => [..._threeOnSceneOne(s), _rehearsal(s, n: 4, scene: null)],
        );
        await _openThePlan(tester);
        harness.room.labelAnswersFirst.add(const NetworkFailed('sem rede'));
        await _tapLabel(tester, _sceneButton(2));
        expect(find.text(_labelFailed), findsOneWidget);
        await _openTheSheetOf(tester, 1);
        await tester.ensureVisible(find.text(_recordAgain));
        await tester.tap(find.text(_recordAgain));
        await _pumpUntil(
          tester,
          () => byLabel(_question).evaluate().isNotEmpty,
        );

        await tester.tap(byLabel(_houseBack));
        await _pumpUntil(tester, () => byLabel(_question).evaluate().isEmpty);
        await _theAnswerSettles(tester);
        expect(_dot, findsOneWidget);
        await _openThePlan(tester);

        expect(find.text(_planLine), findsOneWidget);
        expect(byLabel(_back), findsNothing);
        expect(find.text(_labelFailed), findsNothing);
        semantics.dispose();
      },
    );
  });

  testWidgets(
    'the card rests while a join runs, and a tap on it labels nothing',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final (harness, container) = await _seeded(tester, _twoUnlabelled);
      await _openThePlan(tester);
      harness.room.holdNextTake('parte-2');
      await tester.ensureVisible(byLabel(_join));
      await tester.tap(byLabel(_join));
      await _pumpUntil(
        tester,
        () =>
            harness.room.holdTakeScope == 'parte-2' &&
            container.read(salaSessionProvider).joining == 2,
      );
      await tester.pump();

      expect(_enabledAt(tester, _sceneButton(3)), Tristate.isFalse);
      await tester.ensureVisible(byLabel(_sceneButton(3)));
      await tester.tap(byLabel(_sceneButton(3)), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 100));
      harness.room.finishHeldTake();
      await _theAnswerSettles(tester);
      await tester.pump(const Duration(seconds: 1));

      expect(harness.room.labelsSent, isEmpty);
      semantics.dispose();
    },
  );

  testWidgets(
    'the card\'s play shows her pause while its rehearsal plays, and the play '
    'again after a second tap',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final (harness, _) = await _seeded(tester, _twoUnlabelled);
      await _openThePlan(tester);
      final play = 'Ouvir — ${_facts(4)}';
      expect(_glyphOn(tester, play), ListenGlyph.play);

      await _tapLabel(tester, play);

      expect(harness.playback.sounding, isTrue);
      expect(
        _glyphOn(tester, play),
        ListenGlyph.pause,
        reason: 'o ensaio do cartão tocava e o botão ainda mostrava tocar',
      );
      expect(_pressedAt(tester, play), Tristate.isTrue);

      await _tapLabel(tester, play);

      expect(harness.playback.sounding, isFalse);
      expect(_glyphOn(tester, play), ListenGlyph.play);
      expect(_pressedAt(tester, play), Tristate.isFalse);
      semantics.dispose();
    },
  );

  testWidgets(
    'the sheet\'s line that plays shows her pause, the others the play, and a '
    'second tap gives it back',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final (harness, _) = await _seeded(tester, _threeOnSceneOne);
      await _openThePlan(tester);
      await _openTheSheetOf(tester, 1);
      final play = 'Ouvir — ${_sent(3)}';

      await _tapLabel(tester, play);

      expect(harness.playback.sounding, isTrue);
      expect(
        _glyphOn(tester, play),
        ListenGlyph.pause,
        reason: 'o ensaio da folha tocava e o botão ainda mostrava tocar',
      );
      expect(_pressedAt(tester, play), Tristate.isTrue);
      for (final n in [1, 2]) {
        expect(_glyphOn(tester, 'Ouvir — ${_sent(n)}'), ListenGlyph.play);
        expect(_pressedAt(tester, 'Ouvir — ${_sent(n)}'), Tristate.isFalse);
      }

      await _tapLabel(tester, play);

      expect(harness.playback.sounding, isFalse);
      expect(_glyphOn(tester, play), ListenGlyph.play);
      expect(_pressedAt(tester, play), Tristate.isFalse);
      semantics.dispose();
    },
  );

  testWidgets('the card offers its rehearsal as her filled triangle and '
      'pauses it with her two filled bars, not lucide outlines', (
    tester,
  ) async {
    await _seeded(tester, _twoUnlabelled);
    await _openThePlan(tester);
    final play = 'Ouvir — ${_facts(4)}';

    expect(
      find.descendant(of: byLabel(play), matching: find.byType(Icon)),
      findsNothing,
      reason: 'o cartão desenhava o play vazado do Lucide',
    );
    expect(
      _paintedOn(play),
      paints..path(
        style: PaintingStyle.fill,
        includes: _herPlay.includes,
        excludes: _herPlay.excludes,
      ),
      reason: 'o play dela é «M8 6l10 6-10 6z» (EnsaioFinalPlan.tsx:24)',
    );

    await _tapLabel(tester, play);

    expect(
      _paintedOn(play),
      paints..path(
        style: PaintingStyle.fill,
        includes: _herPause.includes,
        excludes: _herPause.excludes,
      ),
      reason:
          'a pausa dela são duas barras cheias com rx 1 '
          '(EnsaioFinalPlan.tsx:25)',
    );
  });

  testWidgets('a line of the plan\'s sheet is offered as her filled triangle '
      'and pauses with her two filled bars, not lucide outlines', (
    tester,
  ) async {
    await _seeded(tester, _threeOnSceneOne);
    await _openThePlan(tester);
    await _openTheSheetOf(tester, 1);
    final play = 'Ouvir — ${_sent(3)}';

    expect(
      find.descendant(of: byLabel(play), matching: find.byType(Icon)),
      findsNothing,
      reason: 'a folha do plano desenhava o play vazado do Lucide',
    );
    expect(
      _paintedOn(play),
      paints..path(
        style: PaintingStyle.fill,
        includes: _herPlay.includes,
        excludes: _herPlay.excludes,
      ),
      reason: 'o play dela é «M8 6l10 6-10 6z» (EnsaioFinalSheet.tsx:19)',
    );

    await _tapLabel(tester, play);

    expect(
      _paintedOn(play),
      paints..path(
        style: PaintingStyle.fill,
        includes: _herPause.includes,
        excludes: _herPause.excludes,
      ),
      reason:
          'a pausa dela são duas barras cheias com rx 1 '
          '(EnsaioFinalSheet.tsx:20)',
    );
  });
}
