import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/dev/dev_skip_bar.dart';
import 'package:internalization_room/features/sala/data/linked_team.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/device_link.dart';
import 'package:internalization_room/features/sala/domain/hand_reply.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/moment.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/circle_glyph.dart';
import 'package:internalization_room/features/sala/presentation/widgets/colar_overlay.dart';
import 'package:internalization_room/features/sala/presentation/widgets/conversa_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/ensaio_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/panorama_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/part_strips.dart';
import 'package:internalization_room/core/theme/sala_colors.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/features/sala/presentation/widgets/hand_button.dart';
import 'package:internalization_room/features/sala/presentation/widgets/hear_again_button.dart';
import 'package:internalization_room/features/sala/presentation/widgets/escolha_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/language_and_look.dart';
import 'package:internalization_room/features/sala/presentation/widgets/moment_label.dart';
import 'package:internalization_room/features/sala/presentation/widgets/retro_view.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'retro_findings_exits_test.dart' as achados;
import 'package:internalization_room/features/sala/presentation/widgets/replay_arc.dart';
import 'scenario_helpers.dart'
    show byLabel, offTheRows, onTheCircle, onTheRows, stateReads, inTheHome;
import 'the_circle_glyphs_are_hers_test.dart' show paintedGlyph;

Set<Color> paintedBy(WidgetTester tester, Finder corner) {
  final colours = <Color>{};
  for (final box in tester.widgetList<Container>(
    find.descendant(of: corner, matching: find.byType(Container)),
  )) {
    final decoration = box.decoration;
    if (decoration is! BoxDecoration) continue;
    if (decoration.color != null) colours.add(decoration.color!);
    final gradient = decoration.gradient;
    if (gradient != null) colours.addAll(gradient.colors);
    if (decoration.border != null) colours.add(decoration.border!.top.color);
    colours.addAll(decoration.boxShadow?.map((halo) => halo.color) ?? const []);
  }
  for (final mark in tester.widgetList<Icon>(
    find.descendant(of: corner, matching: find.byType(Icon)),
  )) {
    if (mark.color != null) colours.add(mark.color!);
  }
  for (final paint in tester.widgetList<CustomPaint>(
    find.descendant(of: corner, matching: find.byType(CustomPaint)),
  )) {
    final painter = paint.painter;
    if (painter is ReplayArcPainter) colours.add(painter.ink);
  }
  return colours;
}

bool sameTone(Color one, Color other) =>
    one.r == other.r && one.g == other.g && one.b == other.b;

double contrastOf(Color one, Color other) {
  double channel(double value) => value <= 0.03928
      ? value / 12.92
      : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  double light(Color tone) =>
      0.2126 * channel(tone.r) +
      0.7152 * channel(tone.g) +
      0.0722 * channel(tone.b);
  final one0 = light(one);
  final other0 = light(other);
  return (math.max(one0, other0) + 0.05) / (math.min(one0, other0) + 0.05);
}

Color markAsSeen(WidgetTester tester, Finder corner, Color background) {
  final marca = find.descendant(
    of: corner,
    matching: find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter is ReplayArcPainter,
    ),
  );
  final tinta =
      (tester.widget<CustomPaint>(marca).painter! as ReplayArcPainter).ink;
  var alpha = tinta.a;
  for (final veu in tester.widgetList<FadeTransition>(
    find.ancestor(of: marca, matching: find.byType(FadeTransition)),
  )) {
    alpha *= veu.opacity.value;
  }
  for (final veu in tester.widgetList<Opacity>(
    find.ancestor(of: marca, matching: find.byType(Opacity)),
  )) {
    alpha *= veu.opacity;
  }
  return Color.alphaBlend(tinta.withValues(alpha: alpha), background);
}

bool leaveIsDeaf(WidgetTester tester) => tester
    .widgetList<IgnorePointer>(
      find.ancestor(
        of: byLabel('Escolher outra passagem'),
        matching: find.byType(IgnorePointer),
      ),
    )
    .any((portao) => portao.ignoring);

void expectOnlyHerMenuAndTheLanguageCodesAreWritten() {
  final words = find.byType(Text);
  final codes = find.descendant(
    of: find.byType(LanguageAndLook),
    matching: words,
  );
  final menu = find.descendant(of: find.byType(EscolhaView), matching: words);
  expect(
    codes,
    findsNWidgets(languages.length),
    reason: 'na escolha os códigos PT e EN são escritos',
  );
  expect(
    words,
    findsNWidgets(languages.length + menu.evaluate().length),
    reason: 'na escolha só o menu dela e os códigos são escritos',
  );
}

Future<ProviderContainer> pumpSala(
  WidgetTester tester,
  SalaHarness harness,
) async {
  final container = harness.container();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await tester.pump(const Duration(milliseconds: 100));
  return container;
}

/// A tablet whose credential was collected on an earlier day: a room that refuses every
/// door from the start still finds it linked.
const _holdingItsCredential = RememberedLink(
  deviceId: 'aparelho-1',
  team: TeamLink(projectId: 'equipe-1'),
  credential: 'credencial-1',
);

const retellExit = 'Ouvir e traduzir esta parte de novo';
const wholeClipExit = 'Ouvir e traduzir a gravação de novo';
const continuarOEnsaio = 'Continuar o ensaio';
const regravarAFrase1 = 'regravar a frase 1';

Future<ProviderContainer> pumpToFindings(
  WidgetTester tester,
  bool hasFinding,
) async {
  final harness = SalaHarness()
    ..room.verdictChecked = false
    ..room.verdictHasFinding = hasFinding;
  final container = await pumpSala(tester, harness);
  final notifier = container.read(salaSessionProvider.notifier);

  await notifier.goConversa(book: 'Ruth');
  await tester.pump(const Duration(milliseconds: 200));
  notifier.goEnsaio();
  await tester.pump(const Duration(milliseconds: 100));
  notifier.gravarACena(1);
  notifier.gravarACena(1);
  await tester.pump(const Duration(milliseconds: 100));
  notifier.takeKeep();
  await untilTheAdvanceDiscLights(
    notifier,
    step: () => letTheRehearsalReachTheRoom(tester),
  );
  notifier.startRetro();
  await tester.pump(const Duration(milliseconds: 200));
  harness.playback.finishPlayback();
  await tester.pump(const Duration(milliseconds: 200));
  await notifier.finishBackTranslation();
  await tester.pump(const Duration(milliseconds: 200));
  return container;
}

const _thePanorama = Passagem(
  pericope: 'panorama',
  audioUrl: '/voice/panorama',
  kind: PassagemKind.panorama,
);

/// The team taps the Panorama, the Choice's first entry, and its line is said.
Future<void> _enterThePanorama(
  WidgetTester tester,
  SalaHarness harness,
  ProviderContainer container,
) async {
  harness.room.passages = [_thePanorama, ...harness.room.passages];
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.abrirEscolha();
  await tester.pump(const Duration(milliseconds: 300));
  notifier.openTheEntry(_thePanorama);
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('convite draws the mark and the title and no circle', (
    tester,
  ) async {
    await pumpSala(tester, SalaHarness());

    expect(find.text('Escolha a passagem'), findsOneWidget);
    expect(find.byType(FacilitatorCircle), findsNothing);
  });

  testWidgets('every stage paints something the team can see', (tester) async {
    final harness = SalaHarness()..room.done = true;
    final container = await pumpSala(tester, harness);
    final notifier = container.read(salaSessionProvider.notifier);

    for (final go in [
      () => notifier.goConversa(book: 'Ruth'),
      notifier.goEnsaio,
      notifier.startRetro,
    ]) {
      go();
      await tester.pump(const Duration(milliseconds: 120));
      final body = tester.getSize(find.byType(Scaffold));
      expect(body.width, greaterThan(0));
      expect(body.height, greaterThan(0));
    }
    closeTheRoom(container);
  });

  testWidgets('the choice screen is her menu and nothing else', (tester) async {
    final harness = SalaHarness();
    final container = await pumpSala(tester, harness);
    await container.read(salaSessionProvider.notifier).abrirEscolha();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Escolha a passagem'), findsOneWidget);
    expect(find.text('Rute 1:1–5'), findsOneWidget);
    expect(find.byType(FacilitatorCircle), findsNothing);
    expect(
      find.byType(ColarOverlay),
      findsNothing,
      reason: 'o colar mede uma passagem; na escolha ainda não há passagem',
    );
    expectOnlyHerMenuAndTheLanguageCodesAreWritten();
  });

  testWidgets('a finished book keeps the title in english over an empty list', (
    tester,
  ) async {
    final harness = SalaHarness(lingua: 'en')..room.passages = const [];
    final container = await pumpSala(tester, harness);
    await container.read(salaSessionProvider.notifier).abrirEscolha();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Choose the Passage'), findsOneWidget);
    expect(find.byType(FacilitatorCircle), findsNothing);
  });

  testWidgets(
    'a wheel still to be read keeps the title in english over an empty list',
    (tester) async {
      final harness = SalaHarness(lingua: 'en', linkedAs: _holdingItsCredential)
        ..room.failWith = const Refused('BAD_REQUEST');
      final container = await pumpSala(tester, harness);
      await container.read(salaSessionProvider.notifier).abrirEscolha();
      await tester.pump(const Duration(milliseconds: 300));

      expect(container.read(salaSessionProvider).rodaPorLer, isTrue);
      expect(find.text('Choose the Passage'), findsOneWidget);
      expect(find.byType(FacilitatorCircle), findsNothing);
      closeTheRoom(container);
    },
  );

  testWidgets('a finished book offers nothing to enter', (tester) async {
    final harness = SalaHarness()..room.passages = const [];
    final container = await pumpSala(tester, harness);
    await container.read(salaSessionProvider.notifier).abrirEscolha();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      byLabel('Entrar nesta passagem'),
      findsNothing,
      reason:
          'não há o que oferecer, e um botão que não leva a lugar nenhum '
          'é pior do que nenhum botão',
    );
    expect(find.byType(FacilitatorCircle), findsNothing);
  });

  testWidgets('no stage ever shows a written word', (tester) async {
    final harness = SalaHarness()..room.done = true;
    final container = await pumpSala(tester, harness);
    final notifier = container.read(salaSessionProvider.notifier);

    expectOnlyHerMenuAndTheLanguageCodesAreWritten();

    await notifier.abrirEscolha();
    await tester.pump(const Duration(milliseconds: 300));
    expectOnlyHerMenuAndTheLanguageCodesAreWritten();

    for (final go in [() => notifier.goConversa(book: 'Ruth')]) {
      go();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 1400));
      await tester.pump(const Duration(milliseconds: 1400));
      expect(
        find.byType(Text),
        findsNothing,
        reason:
            'a sala é falada de ponta a ponta: uma palavra escrita é uma '
            'palavra que esta equipe não pode ler',
      );
    }

    notifier.startRetro();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 1400));
    await tester.pump(const Duration(milliseconds: 1400));
    expect(
      find.byType(Text),
      findsNWidgets(
        find
            .descendant(of: find.byType(RetroView), matching: find.byType(Text))
            .evaluate()
            .length,
      ),
      reason:
          'na tradução só a tela dela escreve, com as palavras dela; nenhum '
          'outro canto da sala ganha uma palavra escrita',
    );
    closeTheRoom(container);
  });

  testWidgets('no stage is a dead end — every screen answers a touch', (
    tester,
  ) async {
    final harness = SalaHarness()..room.done = true;
    final container = await pumpSala(tester, harness);
    final notifier = container.read(salaSessionProvider.notifier);

    Future<void> expectALiveGesture(String stage) async {
      await tester.pump(const Duration(milliseconds: 200));
      final live = tester
          .widgetList<GestureDetector>(find.byType(GestureDetector))
          .where((it) => it.onTap != null || it.onLongPress != null);
      expect(
        live,
        isNotEmpty,
        reason:
            'sem gesto vivo em "$stage" a equipe não tem o que tocar, e '
            'não há texto que explique o que houve',
      );
    }

    await expectALiveGesture('convite');
    await notifier.abrirEscolha();
    await expectALiveGesture('escolha');
    notifier.goConversa(book: 'Ruth');
    await expectALiveGesture('conversa');
    notifier.goEnsaio();
    await expectALiveGesture('ensaio');
    notifier.startRetro();
    await expectALiveGesture('retro');
    closeTheRoom(container);
  });

  testWidgets('conversa offers a tap to speak, the hand and the colar', (
    tester,
  ) async {
    final container = await pumpSala(tester, SalaHarness());
    container.read(salaSessionProvider.notifier).goConversa(book: 'Ruth');
    await tester.pump(const Duration(milliseconds: 200));

    expect(container.read(salaSessionProvider).stage, SalaStage.conversa);
    expect(find.byType(ColarOverlay), findsOneWidget);
    expect(byLabel('Deixar uma pergunta para o facilitador'), findsOneWidget);
    expect(
      byLabel('Toque para falar'),
      findsOneWidget,
      reason: 'o círculo dizia «Tocar para falar», não as palavras dela',
    );
  });

  testWidgets('the dev seal shows from the invite on, before any skip exists', (
    tester,
  ) async {
    dotenv.testLoad(fileInput: 'BACKEND_URL=http://x\nDEV_PULAR_FASES=1');
    addTearDown(() => dotenv.testLoad(fileInput: ''));
    final container = await pumpSala(tester, SalaHarness());
    final notifier = container.read(salaSessionProvider.notifier);
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      find.text('DEV'),
      findsOneWidget,
      reason: 'sem o selo no convite não dá para saber que o build é de dev',
    );
    expect(find.text('pular → ensaio'), findsNothing);

    await notifier.abrirEscolha();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('DEV'), findsOneWidget);
    expect(find.text('pular → retro'), findsNothing);
  });

  testWidgets('the dev bar names every skip, and waits for its inputs', (
    tester,
  ) async {
    dotenv.testLoad(fileInput: 'BACKEND_URL=http://x\nDEV_PULAR_FASES=1');
    addTearDown(() => dotenv.testLoad(fileInput: ''));
    final harness = SalaHarness();
    final container = await pumpSala(tester, harness);
    harness.room.holdNextCreate();
    unawaited(
      container.read(salaSessionProvider.notifier).goConversa(book: 'Ruth'),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('DEV'), findsOneWidget);
    expect(find.text('pular → ensaio'), findsOneWidget);
    expect(find.text('esperando a sessão nascer'), findsOneWidget);
    expect(find.text('grave 1 parte no ensaio antes'), findsOneWidget);

    await tester.tap(find.text('pular → ensaio'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      container.read(salaSessionProvider).stage,
      SalaStage.conversa,
      reason:
          'sem sessão, pular criaria um ensaio órfão: gravações sem '
          'sessão e uma sala pedindo pessoa',
    );

    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump();
  });

  testWidgets('the dev bar walks into the ensaio once the session exists', (
    tester,
  ) async {
    dotenv.testLoad(fileInput: 'BACKEND_URL=http://x\nDEV_PULAR_FASES=1');
    addTearDown(() => dotenv.testLoad(fileInput: ''));
    final container = await pumpSala(tester, SalaHarness());
    unawaited(
      container.read(salaSessionProvider.notifier).goConversa(book: 'Ruth'),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(salaSessionProvider).sessionId, isNotNull);
    expect(find.text('esperando a sessão nascer'), findsNothing);

    await tester.tap(find.text('pular → ensaio'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(container.read(salaSessionProvider).stage, SalaStage.ensaio);
    expect(onTheRows('Gravar'), findsOneWidget);
    expect(
      find.text('DEV'),
      findsOneWidget,
      reason: 'a barra segue visível no ensaio para o próximo pulo',
    );
  });

  testWidgets('a field build shows no dev bar at all', (tester) async {
    dotenv.testLoad(fileInput: 'BACKEND_URL=http://x');
    addTearDown(() => dotenv.testLoad(fileInput: ''));
    final container = await pumpSala(tester, SalaHarness());
    unawaited(
      container.read(salaSessionProvider.notifier).goConversa(book: 'Ruth'),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('DEV'), findsNothing);
    expect(find.text('pular → ensaio'), findsNothing);
  });

  testWidgets(
    "the room's own screen hides the skip bar, not only a bar built by a test",
    (tester) async {
      dotenv.testLoad(fileInput: 'BACKEND_URL=http://x\nDEV_PULAR_FASES=1');
      addTearDown(() => dotenv.testLoad(fileInput: ''));
      final harness = SalaHarness();
      final container = ProviderContainer(
        overrides: [
          ...harness.overrides,
          debugBuildProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const SalaApp()),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        find.byType(DevSkipBar),
        findsOneWidget,
        reason:
            'a barra segue montada na Stack: o que muda é ela não desenhar nada',
      );
      expect(
        find.text('DEV'),
        findsNothing,
        reason:
            'o teste anterior montava a barra à mão e passava o sinalizador, '
            'então trocar o mount de produção por um fixo deixava a suíte verde e '
            'a barra voltava no release',
      );
    },
  );

  testWidgets('a peer cue turns the circle into team-talk mode, still read '
      'as «Toque para falar», not a line of its own', (tester) async {
    final harness = SalaHarness()..room.peerCue = true;
    final container = await pumpSala(tester, harness);
    container.read(salaSessionProvider.notifier).goConversa(book: 'Ruth');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(container.read(salaSessionProvider).peerCue, isTrue);
    expect(paintedGlyph(CircleGlyph.team), findsOneWidget);
    expect(
      onTheCircle('Toque para falar'),
      findsOneWidget,
      reason:
          'o círculo dizia «Conversem entre vocês…», um rótulo que o dela '
          'não tem; o dela diz sempre o mesmo',
    );
  });

  testWidgets('a peer cue at done names the team glyph the circle shows', (
    tester,
  ) async {
    final harness = SalaHarness()
      ..room.peerCue = true
      ..room.done = true;
    final container = await pumpSala(tester, harness);
    container.read(salaSessionProvider.notifier).goConversa(book: 'Ruth');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(container.read(salaSessionProvider).voice, VoiceState.done);
    expect(paintedGlyph(CircleGlyph.team), findsOneWidget);
    expect(onTheCircle('Toque para falar'), findsOneWidget);
  });

  testWidgets('a Panorama reply that sends the team to talk among themselves '
      'shows the team glyph at rest, as the Conversation does', (tester) async {
    final harness = SalaHarness()..room.peerCue = true;
    final container = await pumpSala(tester, harness);
    await _enterThePanorama(tester, harness, container);
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(PanoramaView), findsOneWidget);
    expect(container.read(salaSessionProvider).peerCue, isTrue);
    expect(paintedGlyph(CircleGlyph.team), findsOneWidget);
    expect(onTheCircle('Toque para falar'), findsOneWidget);
  });

  testWidgets('a Panorama reply without the cue draws no team glyph', (
    tester,
  ) async {
    final harness = SalaHarness();
    final container = await pumpSala(tester, harness);
    await _enterThePanorama(tester, harness, container);
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(PanoramaView), findsOneWidget);
    expect(paintedGlyph(CircleGlyph.team), findsNothing);
  });

  testWidgets(
    'done without a peer cue offers a tap to speak, with no team glyph',
    (tester) async {
      final harness = SalaHarness()..room.done = true;
      final container = await pumpSala(tester, harness);
      container.read(salaSessionProvider.notifier).goConversa(book: 'Ruth');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      expect(container.read(salaSessionProvider).voice, VoiceState.done);
      expect(paintedGlyph(CircleGlyph.team), findsNothing);
      expect(byLabel('Toque para falar'), findsOneWidget);
    },
  );

  testWidgets('hearing a line again is offered in english to an english room', (
    tester,
  ) async {
    final harness = SalaHarness(lingua: 'en');
    final container = await pumpSala(tester, harness);
    await _enterThePanorama(tester, harness, container);
    await tester.pump(const Duration(seconds: 1));

    expect(container.read(salaSessionProvider).canHearAgain, isTrue);
    expect(
      byLabel('Hear that again'),
      findsOneWidget,
      reason: 'o botão dizia «Hear it again», e o dela diz «Hear that again»',
    );
    expect(
      byLabel('Ouvir de novo'),
      findsNothing,
      reason:
          'o botão de ouvir de novo falava português a um aparelho em inglês',
    );
  });

  testWidgets('«Choose another passage» speaks english to an english room', (
    tester,
  ) async {
    final container = await pumpSala(tester, SalaHarness(lingua: 'en'));
    container.read(salaSessionProvider.notifier).goConversa(book: 'Ruth');
    await tester.pump(const Duration(milliseconds: 200));

    expect(byLabel('Choose another passage'), findsOneWidget);
    expect(
      byLabel('Escolher outra passagem'),
      findsNothing,
      reason:
          'a saída da passagem se anunciava em português a um aparelho em '
          'inglês',
    );
  });

  testWidgets('the hand speaks english to an english room', (tester) async {
    final container = await pumpSala(tester, SalaHarness(lingua: 'en'));
    container.read(salaSessionProvider.notifier).goConversa(book: 'Ruth');
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      byLabel('Leave a question for your facilitator'),
      findsOneWidget,
      reason: 'a mão dizia «for the facilitator», não as palavras dela',
    );
    expect(
      byLabel('Deixar uma pergunta para o facilitador'),
      findsNothing,
      reason: 'a mão falava português a um aparelho em inglês',
    );
  });

  testWidgets('an unheard reply is offered in english to an english room', (
    tester,
  ) async {
    final container = await pumpSala(
      tester,
      SalaHarness(
        lingua: 'en',
        replies: const [
          HandReply(
            id: 'r1',
            audioUrl: '/api/internalization-room/voice/resposta',
          ),
        ],
      ),
    );
    container.read(salaSessionProvider.notifier).goConversa(book: 'Ruth');
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      byLabel("Hear your facilitator's reply"),
      findsOneWidget,
      reason: 'a mão dizia «the facilitator\'s answer», não as palavras dela',
    );
    expect(
      byLabel('Ouvir a resposta do facilitador'),
      findsNothing,
      reason:
          'a resposta do facilitador era oferecida em português a um '
          'aparelho em inglês',
    );
  });

  testWidgets('an armed question keeps the hand speaking english in an english '
      'room', (tester) async {
    final container = await pumpSala(tester, SalaHarness(lingua: 'en'));
    final notifier = container.read(salaSessionProvider.notifier);
    notifier.goConversa(book: 'Ruth');
    await tester.pump(const Duration(milliseconds: 200));

    notifier.handTap();
    await tester.pump(const Duration(milliseconds: 200));

    expect(container.read(salaSessionProvider).noteMode, isTrue);
    expect(byLabel('Leave a question for your facilitator'), findsOneWidget);
    expect(
      byLabel('Deixar uma pergunta para o facilitador'),
      findsNothing,
      reason: 'a mão armada falava português a um aparelho em inglês',
    );
  });

  testWidgets('a reply playing is announced in english to an english room', (
    tester,
  ) async {
    final harness = SalaHarness(
      lingua: 'en',
      replies: const [
        HandReply(id: 'r1', audioUrl: '/api/internalization-room/voice/r1'),
      ],
    );
    final container = await pumpSala(tester, harness);
    final notifier = container.read(salaSessionProvider.notifier);
    notifier.goConversa(book: 'Ruth');
    await tester.pump(const Duration(milliseconds: 200));

    harness.voice.holdNextLine();
    notifier.handTap();
    await tester.pump(const Duration(milliseconds: 200));

    expect(container.read(salaSessionProvider).playingReplyId, 'r1');
    expect(byLabel('Hear your facilitator\'s reply'), findsOneWidget);
    expect(
      byLabel('Ouvir a resposta do facilitador'),
      findsNothing,
      reason:
          'a resposta tocando era anunciada em português a um aparelho em '
          'inglês',
    );

    harness.voice.finishHeldLine();
    await tester.pump(const Duration(milliseconds: 200));
    closeTheRoom(container);
  });

  testWidgets('an unheard reply turns the hand into a listening affordance', (
    tester,
  ) async {
    final container = await pumpSala(
      tester,
      SalaHarness(
        replies: const [
          HandReply(
            id: 'r1',
            audioUrl: '/api/internalization-room/voice/resposta',
          ),
        ],
      ),
    );
    container.read(salaSessionProvider.notifier).goConversa(book: 'Ruth');
    await tester.pump(const Duration(milliseconds: 200));

    expect(byLabel('Ouvir a resposta do facilitador'), findsOneWidget);
    expect(byLabel('Deixar uma pergunta para o facilitador'), findsNothing);
  });

  testWidgets(
    'the retro hangs its part strips once and the conversa necklace stays away',
    (tester) async {
      final harness = SalaHarness();
      final container = await pumpSala(tester, harness);
      final notifier = container.read(salaSessionProvider.notifier);

      notifier.goConversa(book: 'Ruth');
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(ColarOverlay), findsOneWidget);
      expect(find.byType(PartStrips), findsNothing);

      notifier.goEnsaio();
      notifier.gravarACena(1);
      notifier.gravarACena(1);
      await tester.pump(const Duration(milliseconds: 200));
      notifier.takeKeep();
      await untilTheAdvanceDiscLights(
        notifier,
        step: () => letTheRehearsalReachTheRoom(tester),
      );
      notifier.startRetro();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 1400));

      expect(find.byType(PartStrips), findsOneWidget);
      expect(
        find.byType(ColarOverlay),
        findsNothing,
        reason:
            'duas fileiras no alto da retro liam como a mesma coisa duas vezes, que '
            'é a razão de o colar da conversa ficar de fora daqui',
      );
    },
  );

  testWidgets('the rehearsal does not show the necklace', (tester) async {
    final harness = SalaHarness();
    final container = await pumpSala(tester, harness);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goConversa(book: 'Ruth');
    await tester.pump(const Duration(milliseconds: 200));
    notifier.goEnsaio();
    await tester.pump(const Duration(milliseconds: 200));

    expect(onTheRows('Gravar'), findsOneWidget);
    expect(
      find.byType(ColarOverlay),
      findsNothing,
      reason:
          'o progresso do ensaio é a fileira de contas dos pedaços; a '
          'cobertura da conversa não desenha ali',
    );
  });

  testWidgets('a finding on a stretch asks the team which voice must speak', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true)
      ..room.verdictChecked = false
      ..room.verdictHasFinding = true
      ..room.verdictFindingSegmentId = 'trecho-1'
      ..room.takeLandsAfter = const Duration(milliseconds: 300);
    final container = await pumpSala(tester, harness);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.goConversa(book: 'Ruth');
    await tester.pump(const Duration(milliseconds: 200));
    notifier.goEnsaio();
    await tester.pump(const Duration(milliseconds: 100));
    notifier.gravarACena(1);
    notifier.gravarACena(1);
    await tester.pump(const Duration(milliseconds: 100));
    notifier.takeKeep();
    await theRoomNamesTheParts(tester, container, parts: 1);
    expect(
      container.read(salaSessionProvider).partes.single.takeId,
      'gravacao-1',
      reason:
          'a parte entrava no retro antes de a sala dar o nome, e o '
          'trecho contado de volta não tinha de quem ser',
    );
    notifier.startRetro();
    await tester.pump(const Duration(milliseconds: 200));
    harness.playback.at = const Duration(seconds: 10);
    notifier.retroTap();
    notifier.retroTap();
    await tester.pump(const Duration(milliseconds: 200));
    await confirmarATraducaoNaTela(tester, container);
    await tester.pump(const Duration(milliseconds: 600));
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 200));
    await notifier.finishBackTranslation();
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(salaSessionProvider).btPhase, BtPhase.playing);
    expect(container.read(salaSessionProvider).btVeredito, isTrue);

    expect(container.read(salaSessionProvider).btVeredito, isTrue);
    expect(
      byLabel('voltar e regravar uma parte'),
      findsOneWidget,
      reason:
          'as duas saídas continuam ali, mas agora como os dois microfones '
          'do achado, e é a equipe que diz qual voz precisa falar de novo',
    );
    expect(
      byLabel(retellExit),
      findsNothing,
      reason:
          'o par antigo de saídas deixou de existir para um achado com '
          'trecho nomeado — quem decidia era o tipo, não a equipe',
    );
    expect(byLabel(continuarOEnsaio), findsNothing);
  });

  testWidgets('an addition finding offers the way on and nothing else', (
    tester,
  ) async {
    final container = await achados.pumpToFindings(tester, true);

    expect(container.read(salaSessionProvider).btPhase, BtPhase.playing);
    expect(container.read(salaSessionProvider).btVeredito, isTrue);

    expect(container.read(salaSessionProvider).btVeredito, isTrue);
    expect(byLabel(retellExit), findsNothing);
    expect(
      byLabel(wholeClipExit),
      findsNothing,
      reason:
          'telling the whole recording again is the same offer as '
          'telling one stretch again, only wider — it cannot take out of the '
          'recording what the kind says is in it, so the pointer being '
          'absent must not smuggle the offer back in',
    );
    expect(byLabel(continuarOEnsaio), findsNothing);
    expect(byLabel(regravarAFrase1), findsOneWidget);
  });

  testWidgets('a finding with no stretch offers the way on, as the whole '
      'sentence of a frase', (tester) async {
    final container = await achados.pumpToFindings(tester, true);

    expect(container.read(salaSessionProvider).btPhase, BtPhase.playing);
    expect(container.read(salaSessionProvider).btVeredito, isTrue);

    expect(container.read(salaSessionProvider).btVeredito, isTrue);
    expect(byLabel(wholeClipExit), findsNothing);
    expect(
      byLabel(regravarAFrase1),
      findsOneWidget,
      reason:
          'sem o disco de continuar o ensaio, a saída é regravar inteira a '
          'frase onde falta',
    );
  });

  testWidgets('no finding at all still leaves the team a way out', (
    tester,
  ) async {
    final container = await achados.pumpToFindings(tester, false);

    expect(container.read(salaSessionProvider).btPhase, BtPhase.playing);
    expect(container.read(salaSessionProvider).btVeredito, isTrue);

    expect(container.read(salaSessionProvider).btVeredito, isTrue);
    final offered =
        byLabel(retellExit).evaluate().length +
        byLabel(wholeClipExit).evaluate().length +
        byLabel(regravarAFrase1).evaluate().length;
    expect(offered, greaterThan(0));
  });

  testWidgets('the ensaio lights its play once the room holds a part to hear', (
    tester,
  ) async {
    final container = await pumpSala(tester, SalaHarness());
    final notifier = container.read(salaSessionProvider.notifier);
    bool? tocavel() =>
        tester.widget<Semantics>(offTheRows('Ouvir')).properties.enabled;

    await notifier.goConversa(book: 'Ruth');
    await tester.pump(const Duration(milliseconds: 200));
    notifier.goEnsaio();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tocavel(), isFalse);

    notifier.gravarACena(1);
    notifier.gravarACena(1);
    await tester.pump(const Duration(milliseconds: 100));
    notifier.takeKeep();
    await theRoomNamesTheParts(tester, container, parts: 1);
    await tester.pump(const Duration(milliseconds: 800));

    expect(tocavel(), isTrue);
  });

  testWidgets('a retro whose telling the room refuses is never stuck and '
      'calls nobody', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true)
      ..room.takeLandsAfter = const Duration(milliseconds: 300);
    final container = await pumpSala(tester, harness);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.goConversa(book: 'Ruth');
    await tester.pump(const Duration(milliseconds: 200));
    notifier.goEnsaio();
    notifier.gravarACena(1);
    notifier.gravarACena(1);
    await tester.pump(const Duration(milliseconds: 200));
    notifier.takeKeep();
    await theRoomNamesTheParts(tester, container, parts: 1);
    expect(
      container.read(salaSessionProvider).partes.single.takeId,
      'gravacao-1',
      reason:
          'a parte entrava no retro antes de a sala dar o nome, e o '
          'trecho contado de volta não tinha de quem ser',
    );
    notifier.startRetro();
    await tester.pump(const Duration(milliseconds: 300));

    harness.room.failWith = const Refused('UNAUTHORIZED');
    harness.playback.at = const Duration(seconds: 2);
    notifier.retroTap();
    notifier.retroTap();
    await tester.pump(const Duration(milliseconds: 100));
    await confirmarATraducaoNaTela(tester, container);
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(salaSessionProvider).needsPerson, isFalse);
    expect(
      container.read(salaSessionProvider).voice,
      VoiceState.invite,
      reason: 'a retro travada não tinha saída nenhuma pela tela',
    );
  });

  testWidgets(
    'the Panorama\'s turn does not vanish while the room replays a line',
    (tester) async {
      final harness = SalaHarness();
      final container = await pumpSala(tester, harness);
      final notifier = container.read(salaSessionProvider.notifier);

      await _enterThePanorama(tester, harness, container);
      expect(container.read(salaSessionProvider).panoramaSaid, isTrue);
      expect(find.byType(PanoramaView), findsOneWidget);

      harness.voice.holdNextLine();
      unawaited(notifier.hearAgain());
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        container.read(salaSessionProvider).voice,
        VoiceState.speaking,
        reason: 'a sala está falando, então o toque não vale agora',
      );
      expect(
        container.read(salaSessionProvider).panoramaSaid,
        isTrue,
        reason:
            'mas a vez da equipe não pode sumir: ouvir o panorama de novo leva '
            'um a dois minutos, e a mão já estava a caminho do círculo',
      );
      expect(find.byType(PanoramaView), findsOneWidget);

      harness.voice.finishHeldLine();
      await tester.pump(const Duration(milliseconds: 400));
    },
  );

  testWidgets('the way out of the rehearsal survives playing it', (
    tester,
  ) async {
    final harness = SalaHarness();
    final container = await pumpSala(tester, harness);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.goConversa(book: 'Ruth');
    await tester.pump(const Duration(milliseconds: 300));

    notifier.goEnsaio();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 2));
    notifier.gravarACena(1);
    notifier.gravarACena(1);
    await tester.pump(const Duration(milliseconds: 300));
    notifier.takeKeep();
    await tester.pump(const Duration(milliseconds: 300));
    expect(inTheHome('Traduzir a gravação'), findsOneWidget);

    await untilTheAdvanceDiscLights(
      notifier,
      step: () => letTheRehearsalReachTheRoom(tester),
    );
    notifier.playTheRehearsal();
    await tester.pump(const Duration(milliseconds: 200));

    expect(container.read(salaSessionProvider).playPing, isTrue);
    expect(
      tester
          .widget<Semantics>(inTheHome('Traduzir a gravação'))
          .properties
          .enabled,
      isTrue,
      reason: 'ouvir o ensaio guardado apagava o caminho para a retro',
    );
    expect(
      tester
          .widget<AnimatedOpacity>(
            find
                .descendant(
                  of: inTheHome('Traduzir a gravação'),
                  matching: find.byType(AnimatedOpacity),
                )
                .first,
          )
          .opacity,
      1,
    );
  });

  testWidgets(
    'the screen is held awake when the room opens, not when the team taps',
    (tester) async {
      final harness = SalaHarness();
      await pumpSala(tester, harness);

      expect(
        harness.awake.held,
        isTrue,
        reason:
            'a equipe conversava quatro minutos sem tocar no tablet e o '
            'bloqueio automático levava junto a gravação aberta',
      );
    },
  );

  testWidgets(
    'a room that is gone lets the screen sleep again, instead of holding it forever',
    (tester) async {
      final harness = SalaHarness();
      await pumpSala(tester, harness);
      expect(harness.awake.held, isTrue);

      await tester.pumpWidget(const SizedBox());

      expect(
        harness.awake.held,
        isFalse,
        reason:
            'segurar a tela e nunca soltar deixa o tablet aceso muito '
            'depois de a sala ter saído da frente',
      );
    },
  );

  testWidgets(
    'hearing a line again is a quiet green mark, never a second terracotta disc',
    (tester) async {
      final harness = SalaHarness();
      final container = await pumpSala(tester, harness);
      await _enterThePanorama(tester, harness, container);
      await tester.pump(const Duration(seconds: 1));

      expect(
        container.read(salaSessionProvider).canHearAgain,
        isTrue,
        reason:
            'o caso precisa mesmo estar oferecendo ouvir de novo para '
            'poder olhar para ele',
      );
      await tester.pump(const Duration(milliseconds: 1200));

      final ouvir = find.byType(HearAgainButton);
      final pintado = paintedBy(tester, ouvir);

      expect(
        pintado,
        isNotEmpty,
        reason: 'sem nada pintado no canto este teste não olha coisa nenhuma',
      );
      expect(
        pintado.any((cor) => sameTone(cor, SalaColors.light.telha)),
        isFalse,
        reason:
            'a tela em repouso tinha dois discos de telha cheios, e a telha '
            'é a cor que diz qual é a coisa viva agora — com dois, ela deixa '
            'de dizer qualquer coisa',
      );
      expect(
        pintado.any((cor) => sameTone(cor, SalaColors.light.verde)),
        isTrue,
        reason:
            'o repetir é o verde dela e periférico: presente para quem '
            'procura, invisível para quem não está procurando',
      );

      expect(
        contrastOf(
          markAsSeen(tester, ouvir, SalaColors.light.paper),
          SalaColors.light.paper,
        ),
        closeTo(2.19, 0.02),
        reason:
            'a seta dela é --verde a .42, 2,19:1 sobre o papel; o disco '
            'que a erguia acima disso não existe no app dela',
      );
    },
  );

  testWidgets(
    'the way out of a passage cannot be taken while the microphone is open',
    (tester) async {
      final container = await pumpSala(tester, SalaHarness());
      final notifier = container.read(salaSessionProvider.notifier);
      await notifier.goConversa(book: 'Ruth', pericope: 'P01');
      await tester.pump(const Duration(milliseconds: 300));

      final sair = byLabel('Escolher outra passagem');
      expect(
        sair,
        findsOneWidget,
        reason:
            'com a sala parada a saída está na tela, que é de onde este '
            'caso parte',
      );

      notifier.conversaTap();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        container.read(salaSessionProvider).voice,
        VoiceState.listening,
        reason:
            'o caso precisa mesmo abrir o microfone para medir o que '
            'acontece com o dedo enquanto ele está aberto',
      );

      expect(
        tester
            .widgetList<AnimatedOpacity>(
              find.ancestor(of: sair, matching: find.byType(AnimatedOpacity)),
            )
            .map((veu) => veu.opacity),
        contains(0.0),
        reason: 'gravando, a saída sai da vista',
      );

      await tester.tap(sair, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        container.read(salaSessionProvider).stage,
        SalaStage.conversa,
        reason:
            'o botão ficava vivo com o microfone aberto, no canto onde a '
            'mão descansa: um toque errado descartava a gravação em curso e '
            'jogava a equipe de volta na roda, sem uma palavra na tela '
            'dizendo o que tinha acabado de acontecer',
      );
    },
  );

  testWidgets('the way out answers the finger when the room is not listening', (
    tester,
  ) async {
    final container = await pumpSala(tester, SalaHarness());
    await container
        .read(salaSessionProvider.notifier)
        .goConversa(book: 'Ruth', pericope: 'P01');
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(byLabel('Escolher outra passagem'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      container.read(salaSessionProvider).stage,
      SalaStage.escolha,
      reason:
          'e fora do turno ele continua sendo um botão de verdade — sem '
          'isto, o caso vizinho passaria de graça num botão que nunca '
          'funcionou',
    );
  });

  testWidgets(
    'a stage arrives over the one it replaces, slowly enough that nothing jumps',
    (tester) async {
      final container = await pumpSala(tester, SalaHarness());
      final notifier = container.read(salaSessionProvider.notifier);
      await notifier.goConversa(book: 'Ruth', pericope: 'P01');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(seconds: 2));
      expect(
        find.byType(ConversaView),
        findsOneWidget,
        reason:
            'o caso precisa mesmo começar numa etapa já assentada: uma '
            'etapa que ainda está entrando sai de onde entrou, e o que se '
            'mediria seria o resto da travessia anterior',
      );

      notifier.goEnsaio();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(
        find.byType(EnsaioView),
        findsOneWidget,
        reason: 'a etapa nova entra na hora',
      );
      expect(
        find.byType(ConversaView),
        findsOneWidget,
        reason:
            'meio segundo depois a etapa que sai ainda está na tela: a '
            'troca acontecia em 400 milissegundos, que numa sala sem palavra '
            'nenhuma é a tela inteira sendo substituída num piscar',
      );

      await tester.pump(const Duration(milliseconds: 1200));
      expect(
        find.byType(ConversaView),
        findsNothing,
        reason:
            'e a travessia acaba — uma etapa que nunca sai é duas telas '
            'empilhadas, não um esmaecer',
      );
      closeTheRoom(container);
    },
  );

  testWidgets(
    'the finger still opens the microphone while the team is talking among themselves',
    (tester) async {
      final harness = SalaHarness()..room.peerCue = true;
      final container = await pumpSala(tester, harness);
      container.read(salaSessionProvider.notifier).goConversa(book: 'Ruth');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(seconds: 2));
      expect(
        container.read(salaSessionProvider).peerCue,
        isTrue,
        reason: 'o caso precisa mesmo estar no modo de conversa entre a equipe',
      );

      await tester.tap(find.byType(FacilitatorCircle));
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        container.read(salaSessionProvider).voice,
        VoiceState.listening,
        reason:
            'a deixa manda a equipe conversar entre si e o círculo continua '
            'sendo o mesmo botão: é assim que ela volta para contar o que '
            'combinou, e a marca desenhada por cima dele não pode ficar no '
            'caminho do dedo',
      );
      expect(
        container.read(salaSessionProvider).peerCue,
        isTrue,
        reason:
            'o talkMode dela só muda na próxima resposta (page.tsx:628): um '
            'microfone aberto e largado devolve o círculo ao glifo da equipe',
      );
    },
  );

  testWidgets('the way out stays out of reach through every voice of a turn', (
    tester,
  ) async {
    final harness = SalaHarness();
    final container = await pumpSala(tester, harness);
    final notifier = container.read(salaSessionProvider.notifier);
    VoiceState voz() => container.read(salaSessionProvider).voice;
    await notifier.goConversa(book: 'Ruth', pericope: 'P01');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 2));

    harness.room.holdNextTurn();
    harness.voice.holdNextLine();

    notifier.conversaTap();
    await tester.pump(const Duration(milliseconds: 200));
    expect(voz(), VoiceState.listening);
    expect(leaveIsDeaf(tester), isTrue, reason: 'com o microfone aberto');

    notifier.conversaTap();
    await letTheRehearsalReachTheRoom(tester);
    expect(voz(), VoiceState.thinking);
    expect(
      leaveIsDeaf(tester),
      isTrue,
      reason:
          'e com a fala da equipe já a caminho da sala: o turno inteiro é '
          'trabalho que se perde, não só o pedaço em que o microfone está '
          'aberto',
    );

    harness.room.finishHeldTurn();
    await letTheRehearsalReachTheRoom(tester);
    expect(voz(), VoiceState.speaking);
    expect(
      leaveIsDeaf(tester),
      isTrue,
      reason:
          'e com a sala falando, que é quando a equipe está ouvindo e '
          'não olhando para a tela — a mão descansa exatamente no canto onde '
          'o botão fica',
    );
    closeTheRoom(container);
  });

  testWidgets(
    'the way out stays out of reach while the room waits for a person',
    (tester) async {
      final harness = SalaHarness(linkedAs: _holdingItsCredential)
        ..room.failTurnsWith = const Refused('UNAUTHORIZED');
      final container = await pumpSala(tester, harness);
      final notifier = container.read(salaSessionProvider.notifier);
      await notifier.goConversa(book: 'Ruth', pericope: 'P01');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(seconds: 2));

      notifier.conversaTap();
      await tester.pump(const Duration(milliseconds: 200));
      notifier.conversaTap();
      await waitFor(
        'a sala pedir uma pessoa',
        () => container.read(salaSessionProvider).needsPerson,
        step: () => tester.pump(const Duration(milliseconds: 100)),
      );

      expect(
        container.read(salaSessionProvider).needsPerson,
        isTrue,
        reason: 'o caso precisa mesmo chegar ao pedido de uma pessoa',
      );
      expect(
        leaveIsDeaf(tester),
        isTrue,
        reason:
            'e este é o estado que dura mais: a sala fica esperando '
            'alguém chegar, e é o mais fácil de a equipe cutucar até deixar a '
            'passagem sem querer',
      );
      closeTheRoom(container);
    },
  );

  testWidgets('the first touch after the panorama opening records the team, '
      'even when the app has just come back to the front', (tester) async {
    final harness = SalaHarness();
    final container = await pumpSala(tester, harness);

    await _enterThePanorama(tester, harness, container);

    expect(
      container.read(salaSessionProvider).panoramaSaid,
      isTrue,
      reason: 'o que vem abaixo só vale com a abertura já dita',
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(byLabel('Toque para falar'));
    await tester.pump(const Duration(milliseconds: 200));

    final state = container.read(salaSessionProvider);
    expect(
      state.stage,
      SalaStage.panorama,
      reason: 'a volta ao primeiro plano abria a roda por cima do panorama',
    );
    expect(
      state.voice,
      VoiceState.listening,
      reason: 'o toque depois da abertura grava a resposta da equipe',
    );
  });

  testWidgets(
    'the Panorama canvas shows the circle, the hand, «Ouvir de novo» and the '
    'way out, and no beads, rehearsal entry, moment label or kept takes, '
    'while the Watch reads a room that says the passage is done',
    (tester) async {
      final harness = SalaHarness(watchesWithoutAHalt: true)
        ..room.done = true
        ..room.nextMoment = const Moment(at: MomentAt.articulation, parts: 3)
        ..room.nextCoverage = coverage(
          engaged: totalBeads,
          surfaced: totalBeads,
        );
      final container = await pumpSala(tester, harness);
      await _enterThePanorama(tester, harness, container);
      await tester.pump(const Duration(seconds: 3));
      final read = container.read(salaSessionProvider);

      expect(stateReads(harness), greaterThan(0));
      expect(read.stage, SalaStage.panorama);
      expect(read.endOfThePassage, isFalse);
      expect(read.coverage.engaged, 0);
      expect(read.coverage.beadsFilled, 0);
      expect(find.byType(FacilitatorCircle), findsOneWidget);
      expect(find.byType(HandButton), findsOneWidget);
      expect(byLabel(roomLabelFor('hearAgain', 'pt')), findsOneWidget);
      expect(byLabel(roomLabelFor('leavePassage', 'pt')), findsOneWidget);
      expect(find.byType(ColarOverlay), findsNothing);
      expect(find.byType(PartStrips), findsNothing);
      expect(find.byType(EnsaioView), findsNothing);
      expect(find.byType(MomentLabel), findsNothing);
      expect(byLabel(roomLabelFor('recordEnsaio', 'pt')), findsNothing);
      closeTheRoom(container);
    },
  );
}
