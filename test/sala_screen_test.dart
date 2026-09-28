import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/dev/dev_skip_bar.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/hand_reply.dart';
import 'package:internalization_room/features/sala/data/mic_permission.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/bead_row.dart';
import 'package:internalization_room/features/sala/presentation/widgets/bead_styles.dart';
import 'package:internalization_room/features/sala/presentation/widgets/colar_overlay.dart';
import 'package:internalization_room/features/sala/presentation/widgets/conversa_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/ensaio_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/passage_ruler.dart';
import 'package:internalization_room/core/theme/sala_colors.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/features/sala/presentation/widgets/hear_again_button.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show byLabel;

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
  final marca = find.descendant(of: corner, matching: find.byType(Icon));
  final tinta = tester.widget<Icon>(marca).color!;
  var alpha = tinta.a;
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
        of: byLabel('Deixar esta passagem e escolher outra'),
        matching: find.byType(IgnorePointer),
      ),
    )
    .any((portao) => portao.ignoring);

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

const retellExit = 'Ouvir e traduzir esta parte de novo';
const wholeClipExit = 'Ouvir e traduzir a gravação de novo';
const continuarOEnsaio = 'Continuar o ensaio';

Future<ProviderContainer> pumpToFindings(
  WidgetTester tester,
  BtFindingKind? finding,
) async {
  final harness = SalaHarness()
    ..room.verdictChecked = false
    ..room.verdictFinding = finding;
  final container = await pumpSala(tester, harness);
  final notifier = container.read(salaSessionProvider.notifier);

  await notifier.goConversa();
  await tester.pump(const Duration(milliseconds: 200));
  notifier.goEnsaio();
  await tester.pump(const Duration(milliseconds: 100));
  notifier.ensaioTap();
  notifier.ensaioTap();
  await tester.pump(const Duration(milliseconds: 100));
  notifier.takeKeep();
  notifier.startRetro();
  await tester.pump(const Duration(milliseconds: 200));
  harness.playback.finishPlayback();
  await tester.pump(const Duration(milliseconds: 200));
  await notifier.finishBackTranslation();
  await tester.pump(const Duration(milliseconds: 200));
  return container;
}

void main() {
  testWidgets('convite renders the facilitator circle', (tester) async {
    await pumpSala(tester, SalaHarness());

    expect(find.byType(FacilitatorCircle), findsOneWidget);
  });

  testWidgets('the circle has real size, not just a place in the tree', (
    tester,
  ) async {
    await pumpSala(tester, SalaHarness());

    final drawn = tester.getSize(find.byType(FacilitatorCircle));

    expect(
      drawn.width,
      greaterThan(0),
      reason:
          'um Stack com restrições frouxas encolhe para o maior filho sem '
          'posição — um filho de 0x0 colapsa a tela inteira, e o widget continua '
          'na árvore como se estivesse lá',
    );
    expect(drawn.height, greaterThan(0));
  });

  testWidgets('every stage paints something the team can see', (tester) async {
    final harness = SalaHarness()..room.done = true;
    final container = await pumpSala(tester, harness);
    final notifier = container.read(salaSessionProvider.notifier);

    for (final go in [
      notifier.goConversa,
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

  testWidgets('the choice screen is the circle, the wood and nothing else', (
    tester,
  ) async {
    final harness = SalaHarness();
    final container = await pumpSala(tester, harness);
    await container.read(salaSessionProvider.notifier).abrirEscolha();
    await tester.pump(const Duration(milliseconds: 300));

    expect(byLabel('Ouvir esta passagem de novo'), findsOneWidget);
    expect(byLabel('Entrar nesta passagem'), findsOneWidget);
    expect(
      find.byType(PassageRuler),
      findsOneWidget,
      reason:
          'a régua é o gesto de andar pelo livro, não só um enfeite de posição',
    );
    expect(
      find.byType(ColarOverlay),
      findsNothing,
      reason: 'o colar mede uma passagem; na escolha ainda não há passagem',
    );
    expect(
      find.byType(Text),
      findsNothing,
      reason: 'nenhuma palavra escrita, em nenhuma tela da sala',
    );
  });

  testWidgets('the wooden button carries the passage the room just said', (
    tester,
  ) async {
    final harness = SalaHarness();
    final container = await pumpSala(tester, harness);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      container.read(salaSessionProvider).voice,
      VoiceState.invite,
      reason: 'passo 1: a sala terminou de dizer a primeira',
    );
    await tester.drag(find.byType(PassageRuler), const Offset(400, 0));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      container.read(salaSessionProvider).oferecida?.pericope,
      'P03',
      reason: 'passo 2: o dedo correu a régua até a ponta',
    );

    await tester.drag(find.byType(PassageRuler), const Offset(-140, 0));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      container.read(salaSessionProvider).oferecida?.pericope,
      'P02',
      reason: 'passo 3: e voltou uma — o que a roda de mão única não permitia',
    );

    await tester.pump(const Duration(milliseconds: 800));
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is RoundActionButton && w.mood != ButtonMood.lit,
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(harness.room.pericopesAsked, contains('P02'));
    expect(container.read(salaSessionProvider).stage, SalaStage.conversa);
  });

  testWidgets(
    'the wooden button names the panorama, not "entrar nesta passagem"',
    (tester) async {
      const panorama = Passagem(
        pericope: 'panorama',
        audioUrl: '/voice/panorama',
        kind: PassagemKind.panorama,
      );
      final harness = SalaHarness()
        ..room.passages = const [
          panorama,
          Passagem(pericope: 'P01', audioUrl: '/voice/p01'),
        ];
      final container = await pumpSala(tester, harness);
      await container.read(salaSessionProvider.notifier).abrirEscolha();
      await tester.pump(const Duration(milliseconds: 300));

      expect(byLabel('Panorama do Livro'), findsOneWidget);
      expect(
        byLabel('Entrar nesta passagem'),
        findsNothing,
        reason:
            'o panorama é a porta de entrada da roda, mas o botão de '
            'entrar nele ainda dizia o rótulo genérico de qualquer passagem',
      );
    },
  );

  testWidgets('the panorama button speaks english to an english room', (
    tester,
  ) async {
    const panorama = Passagem(
      pericope: 'panorama',
      audioUrl: '/voice/panorama',
      kind: PassagemKind.panorama,
    );
    final harness = SalaHarness(lingua: 'en')
      ..room.passages = const [
        panorama,
        Passagem(pericope: 'P01', audioUrl: '/voice/p01'),
      ];
    final container = await pumpSala(tester, harness);
    await container.read(salaSessionProvider.notifier).abrirEscolha();
    await tester.pump(const Duration(milliseconds: 300));

    expect(byLabel('Book Panorama'), findsOneWidget);
    expect(
      byLabel('Panorama do Livro'),
      findsNothing,
      reason:
          'um aparelho em inglês não pode mostrar o nome do panorama '
          'em português',
    );
  });

  testWidgets('the choice circle speaks english to an english room', (
    tester,
  ) async {
    final container = await pumpSala(tester, SalaHarness(lingua: 'en'));
    await container.read(salaSessionProvider.notifier).abrirEscolha();
    await tester.pump(const Duration(milliseconds: 300));

    expect(byLabel('Hear this passage again'), findsOneWidget);
    expect(
      byLabel('Ouvir esta passagem de novo'),
      findsNothing,
      reason:
          'o círculo da roda dizia "Ouvir esta passagem de novo" a um '
          'aparelho em inglês',
    );
  });

  testWidgets('the way into a passage speaks english to an english room', (
    tester,
  ) async {
    final container = await pumpSala(tester, SalaHarness(lingua: 'en'));
    await container.read(salaSessionProvider.notifier).abrirEscolha();
    await tester.pump(const Duration(milliseconds: 300));

    expect(byLabel('Enter this passage'), findsOneWidget);
    expect(
      byLabel('Entrar nesta passagem'),
      findsNothing,
      reason:
          'só o panorama falava inglês; a conta de entrar numa passagem '
          'dizia "Entrar nesta passagem" a um aparelho em inglês',
    );
  });

  testWidgets('the passage ruler speaks english to an english room', (
    tester,
  ) async {
    final container = await pumpSala(tester, SalaHarness(lingua: 'en'));
    await container.read(salaSessionProvider.notifier).abrirEscolha();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      byLabel('Choose the passage by running a finger along the row'),
      findsOneWidget,
    );
    expect(
      byLabel('Escolher a passagem, correndo o dedo pela fileira'),
      findsNothing,
      reason:
          'a régua da roda se apresentava em português a um aparelho em '
          'inglês',
    );
  });

  testWidgets(
    'the ruler reads where the team stands in english, not "1 de 3"',
    (tester) async {
      final harness = SalaHarness(lingua: 'en')
        ..room.passages = const [
          Passagem(pericope: 'P01', audioUrl: '/voice/p01'),
          Passagem(pericope: 'P02', audioUrl: '/voice/p02'),
          Passagem(pericope: 'P03', audioUrl: '/voice/p03'),
        ];
      final container = await pumpSala(tester, harness);
      await container.read(salaSessionProvider.notifier).abrirEscolha();
      await tester.pump(const Duration(milliseconds: 300));

      expect(container.read(salaSessionProvider).aOferecer, 0);
      final ruler = tester
          .widget<Semantics>(
            byLabel('Choose the passage by running a finger along the row'),
          )
          .properties;
      expect(
        ruler.value,
        '1 of 3',
        reason:
            'o leitor de tela dizia "1 de 3" no meio de uma frase em inglês',
      );
      expect(ruler.increasedValue, '2 of 3');
      expect(ruler.decreasedValue, '1 of 3');
    },
  );

  testWidgets('a finished book is announced in english to an english room', (
    tester,
  ) async {
    final harness = SalaHarness(lingua: 'en')..room.passages = const [];
    final container = await pumpSala(tester, harness);
    await container.read(salaSessionProvider.notifier).abrirEscolha();
    await tester.pump(const Duration(milliseconds: 300));

    expect(byLabel('Every passage has been worked through'), findsOneWidget);
    expect(
      byLabel('Todas as passagens foram trabalhadas'),
      findsNothing,
      reason:
          'o livro terminado era anunciado em português a um aparelho em '
          'inglês',
    );
  });

  testWidgets(
    'a wheel still to be read asks for it in english, not in portuguese',
    (tester) async {
      final harness = SalaHarness(lingua: 'en')
        ..room.failWith = const RoomBroke('HTTP 500');
      final container = await pumpSala(tester, harness);
      await container.read(salaSessionProvider.notifier).abrirEscolha();
      await tester.pump(const Duration(milliseconds: 300));

      expect(container.read(salaSessionProvider).rodaPorLer, isTrue);
      expect(byLabel('Tap to look for the passages'), findsOneWidget);
      expect(
        byLabel('Tocar para procurar as passagens'),
        findsNothing,
        reason:
            'a roda que ainda não foi lida pedia o toque em português a um '
            'aparelho em inglês',
      );
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
    expect(byLabel('Todas as passagens foram trabalhadas'), findsOneWidget);
  });

  testWidgets(
    'the Choice halts and calls a person once every passage it offered is refused',
    (tester) async {
      final harness = SalaHarness()
        ..room.passages = const [
          Passagem(pericope: 'P01', audioUrl: '/voice/p01'),
          Passagem(pericope: 'P02', audioUrl: '/voice/p02'),
        ]
        ..room.passagesThatCannotOpen = {'P01', 'P02'};
      final container = await pumpSala(tester, harness);
      final notifier = container.read(salaSessionProvider.notifier);
      await notifier.abrirEscolha();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(byLabel('Entrar nesta passagem'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        byLabel('Todas as passagens foram trabalhadas'),
        findsNothing,
        reason: 'uma passagem da roda ainda não foi tentada nesta visita',
      );
      expect(container.read(salaSessionProvider).needsPerson, isFalse);

      await tester.tap(byLabel('Entrar nesta passagem'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        byLabel('Entrar nesta passagem'),
        findsNothing,
        reason: 'nada sobrou para entrar nesta visita',
      );
      expect(
        byLabel('Todas as passagens foram trabalhadas'),
        findsOneWidget,
        reason:
            'a sala chama uma pessoa pelo mesmo caminho de um livro sem nada '
            'a oferecer, com o mesmo rótulo',
      );
      expect(container.read(salaSessionProvider).needsPerson, isTrue);
      expect(harness.room.personsAsked, 0);
    },
  );

  testWidgets('no stage ever shows a written word', (tester) async {
    final harness = SalaHarness()..room.done = true;
    final container = await pumpSala(tester, harness);
    final notifier = container.read(salaSessionProvider.notifier);

    expect(find.byType(Text), findsNothing, reason: 'convite');

    await notifier.abrirEscolha();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(Text), findsNothing, reason: 'escolha');

    for (final go in [
      notifier.goConversa,
      notifier.goEnsaio,
      notifier.startRetro,
    ]) {
      go();
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        find.byType(Text),
        findsNothing,
        reason:
            'a sala é falada de ponta a ponta: uma palavra escrita é uma '
            'palavra que esta equipe não pode ler',
      );
    }
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
    notifier.goConversa();
    await expectALiveGesture('conversa');
    notifier.goEnsaio();
    await expectALiveGesture('ensaio');
    notifier.startRetro();
    await expectALiveGesture('retro');
    closeTheRoom(container);
  });

  testWidgets('the mic gate answers a touch out loud, not in silence', (
    tester,
  ) async {
    final harness = SalaHarness()..recorder.permitted = false;
    final container = await pumpSala(tester, harness);
    await container.read(micPermissionProvider.notifier).check();
    await tester.pump(const Duration(milliseconds: 200));
    harness.voice.assets.clear();

    await tester.tap(find.byType(FacilitatorCircle));
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      harness.voice.assets,
      contains(micBlockedAsset(testLanguage)),
      reason:
          'a tela do microfone não tem texto: se o toque não fala, ela é '
          'muda e sem efeito para sempre',
    );
  });

  testWidgets('conversa offers a tap to speak, the hand and the colar', (
    tester,
  ) async {
    final container = await pumpSala(tester, SalaHarness());
    container.read(salaSessionProvider.notifier).goConversa();
    await tester.pump(const Duration(milliseconds: 200));

    expect(container.read(salaSessionProvider).stage, SalaStage.conversa);
    expect(find.byType(ColarOverlay), findsOneWidget);
    expect(byLabel('Levantar a mão'), findsOneWidget);
    expect(byLabel('Tocar para falar'), findsOneWidget);
  });

  testWidgets('the dev seal shows from the invite on, before any skip exists', (
    tester,
  ) async {
    dotenv.testLoad(
      fileInput:
          'BACKEND_URL=http://x\nINTERNALIZATION_ROOM_KEY=k\nDEV_PULAR_FASES=1',
    );
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
    dotenv.testLoad(
      fileInput:
          'BACKEND_URL=http://x\nINTERNALIZATION_ROOM_KEY=k\nDEV_PULAR_FASES=1',
    );
    addTearDown(() => dotenv.testLoad(fileInput: ''));
    final harness = SalaHarness()..network.reachable = false;
    final container = await pumpSala(tester, harness);
    unawaited(container.read(salaSessionProvider.notifier).goConversa());
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
    dotenv.testLoad(
      fileInput:
          'BACKEND_URL=http://x\nINTERNALIZATION_ROOM_KEY=k\nDEV_PULAR_FASES=1',
    );
    addTearDown(() => dotenv.testLoad(fileInput: ''));
    final container = await pumpSala(tester, SalaHarness());
    unawaited(container.read(salaSessionProvider.notifier).goConversa());
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(salaSessionProvider).sessionId, isNotNull);
    expect(find.text('esperando a sessão nascer'), findsNothing);

    await tester.tap(find.text('pular → ensaio'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(container.read(salaSessionProvider).stage, SalaStage.ensaio);
    expect(byLabel('Tocar para gravar o ensaio'), findsOneWidget);
    expect(
      find.text('DEV'),
      findsOneWidget,
      reason: 'a barra segue visível no ensaio para o próximo pulo',
    );
  });

  testWidgets('a field build shows no dev bar at all', (tester) async {
    dotenv.testLoad(
      fileInput: 'BACKEND_URL=http://x\nINTERNALIZATION_ROOM_KEY=k',
    );
    addTearDown(() => dotenv.testLoad(fileInput: ''));
    final container = await pumpSala(tester, SalaHarness());
    unawaited(container.read(salaSessionProvider.notifier).goConversa());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('DEV'), findsNothing);
    expect(find.text('pular → ensaio'), findsNothing);
  });

  testWidgets(
    "the room's own screen hides the skip bar, not only a bar built by a test",
    (tester) async {
      dotenv.testLoad(
        fileInput:
            'BACKEND_URL=http://x\nINTERNALIZATION_ROOM_KEY=k\nDEV_PULAR_FASES=1',
      );
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

  testWidgets('a peer cue turns the circle into team-talk mode', (
    tester,
  ) async {
    final harness = SalaHarness()..room.peerCue = true;
    final container = await pumpSala(tester, harness);
    container.read(salaSessionProvider.notifier).goConversa();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(container.read(salaSessionProvider).peerCue, isTrue);
    expect(find.byIcon(LucideIcons.users), findsOneWidget);
    expect(
      byLabel('Conversem entre vocês — tocar quando quiserem me contar'),
      findsOneWidget,
    );
  });

  testWidgets('hearing a line again is offered in english to an english room', (
    tester,
  ) async {
    final container = await pumpSala(tester, SalaHarness(lingua: 'en'));
    container.read(salaSessionProvider.notifier).conviteTap();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(seconds: 1));

    expect(container.read(salaSessionProvider).canHearAgain, isTrue);
    expect(byLabel('Hear it again'), findsOneWidget);
    expect(
      byLabel('Ouvir de novo'),
      findsNothing,
      reason:
          'o botão de ouvir de novo falava português a um aparelho em inglês',
    );
  });

  testWidgets('the way out of a passage speaks english to an english room', (
    tester,
  ) async {
    final container = await pumpSala(tester, SalaHarness(lingua: 'en'));
    container.read(salaSessionProvider.notifier).goConversa();
    await tester.pump(const Duration(milliseconds: 200));

    expect(byLabel('Leave this passage and choose another'), findsOneWidget);
    expect(
      byLabel('Deixar esta passagem e escolher outra'),
      findsNothing,
      reason:
          'a saída da passagem se anunciava em português a um aparelho em '
          'inglês',
    );
  });

  testWidgets('the hand speaks english to an english room', (tester) async {
    final container = await pumpSala(tester, SalaHarness(lingua: 'en'));
    container.read(salaSessionProvider.notifier).goConversa();
    await tester.pump(const Duration(milliseconds: 200));

    expect(byLabel('Raise a hand'), findsOneWidget);
    expect(
      byLabel('Levantar a mão'),
      findsNothing,
      reason: 'a mão dizia "Levantar a mão" a um aparelho em inglês',
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
    container.read(salaSessionProvider.notifier).goConversa();
    await tester.pump(const Duration(milliseconds: 200));

    expect(byLabel("Hear the facilitator's answer"), findsOneWidget);
    expect(
      byLabel('Ouvir a resposta do facilitador'),
      findsNothing,
      reason:
          'a resposta do facilitador era oferecida em português a um '
          'aparelho em inglês',
    );
  });

  testWidgets('an armed question is cancelled in english in an english room', (
    tester,
  ) async {
    final container = await pumpSala(tester, SalaHarness(lingua: 'en'));
    final notifier = container.read(salaSessionProvider.notifier);
    notifier.goConversa();
    await tester.pump(const Duration(milliseconds: 200));

    notifier.handTap();
    await tester.pump(const Duration(milliseconds: 200));

    expect(container.read(salaSessionProvider).noteMode, isTrue);
    expect(byLabel('Cancel the question'), findsOneWidget);
    expect(
      byLabel('Cancelar a pergunta'),
      findsNothing,
      reason:
          'a mão armada dizia "Cancelar a pergunta" a um aparelho em inglês',
    );
  });

  testWidgets('a question sent waits in english in an english room', (
    tester,
  ) async {
    final container = await pumpSala(tester, SalaHarness(lingua: 'en'));
    final notifier = container.read(salaSessionProvider.notifier);
    notifier.goConversa();
    await tester.pump(const Duration(milliseconds: 200));

    notifier.handTap();
    notifier.conversaTap();
    await tester.pump(const Duration(milliseconds: 200));
    notifier.conversaTap();
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(salaSessionProvider).questionPending, isTrue);
    expect(byLabel('Question sent, waiting for an answer'), findsOneWidget);
    expect(
      byLabel('Pergunta enviada, aguardando resposta'),
      findsNothing,
      reason: 'a pergunta enviada esperava em português num aparelho em inglês',
    );
    closeTheRoom(container);
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
    notifier.goConversa();
    await tester.pump(const Duration(milliseconds: 200));

    harness.voice.holdNextLine();
    notifier.handTap();
    await tester.pump(const Duration(milliseconds: 200));

    expect(container.read(salaSessionProvider).playingReplyId, 'r1');
    expect(byLabel('The facilitator is answering'), findsOneWidget);
    expect(
      byLabel('O facilitador está respondendo'),
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
    container.read(salaSessionProvider.notifier).goConversa();
    await tester.pump(const Duration(milliseconds: 200));

    expect(byLabel('Ouvir a resposta do facilitador'), findsOneWidget);
    expect(byLabel('Levantar a mão'), findsNothing);
  });

  testWidgets(
    'the retro hangs one bead row and the conversa necklace stays away',
    (tester) async {
      final harness = SalaHarness();
      final container = await pumpSala(tester, harness);
      final notifier = container.read(salaSessionProvider.notifier);

      notifier.goConversa();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(ColarOverlay), findsOneWidget);
      expect(find.byType(BeadRow), findsNothing);

      notifier.goEnsaio();
      notifier.ensaioTap();
      notifier.ensaioTap();
      await tester.pump(const Duration(milliseconds: 200));
      notifier.takeKeep();
      notifier.startRetro();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 1400));

      expect(find.byType(BeadRow), findsOneWidget);
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

    notifier.goConversa();
    await tester.pump(const Duration(milliseconds: 200));
    notifier.goEnsaio();
    await tester.pump(const Duration(milliseconds: 200));

    expect(byLabel('Tocar para gravar o ensaio'), findsOneWidget);
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
      ..room.verdictFinding = BtFindingKind.addition
      ..room.verdictFindingSegmentId = 'trecho-1';
    final container = await pumpSala(tester, harness);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.goConversa();
    await tester.pump(const Duration(milliseconds: 200));
    notifier.goEnsaio();
    await tester.pump(const Duration(milliseconds: 100));
    notifier.ensaioTap();
    notifier.ensaioTap();
    await tester.pump(const Duration(milliseconds: 100));
    notifier.takeKeep();
    await letTheRehearsalReachTheRoom(tester);
    notifier.startRetro();
    await tester.pump(const Duration(milliseconds: 200));
    harness.playback.at = const Duration(seconds: 10);
    notifier.cortarTrecho();
    notifier.retroTap();
    await tester.pump(const Duration(milliseconds: 200));
    await confirmarATraducaoNaTela(tester, container);
    await tester.pump(const Duration(milliseconds: 600));
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 200));
    await notifier.finishBackTranslation();
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(salaSessionProvider).btPhase, BtPhase.findings);
    expect(
      byLabel('Gravar a parte de novo na língua materna'),
      findsOneWidget,
      reason:
          'as duas saídas continuam ali, mas agora como os dois microfones '
          'do achado, e é a equipe que diz qual voz precisa falar de novo',
    );
    expect(byLabel('Traduzir este trecho de novo'), findsOneWidget);
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
    final container = await pumpToFindings(tester, BtFindingKind.addition);

    expect(container.read(salaSessionProvider).btPhase, BtPhase.findings);
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
    expect(byLabel(continuarOEnsaio), findsOneWidget);
  });

  for (final kind in [BtFindingKind.missing, BtFindingKind.unclear]) {
    testWidgets('a ${kind.name} finding with no stretch offers the way on', (
      tester,
    ) async {
      final container = await pumpToFindings(tester, kind);

      expect(container.read(salaSessionProvider).btPhase, BtPhase.findings);
      expect(byLabel(wholeClipExit), findsNothing);
      expect(byLabel(continuarOEnsaio), findsOneWidget);
    });
  }

  for (final kind in <BtFindingKind?>[...BtFindingKind.values, null]) {
    testWidgets(
      'a ${kind?.name ?? 'kind this build does not know'} finding always '
      'leaves the team a way out',
      (tester) async {
        final container = await pumpToFindings(tester, kind);

        expect(container.read(salaSessionProvider).btPhase, BtPhase.findings);
        final offered =
            byLabel(retellExit).evaluate().length +
            byLabel(wholeClipExit).evaluate().length +
            byLabel(continuarOEnsaio).evaluate().length;
        expect(offered, greaterThan(0));
      },
    );
  }

  testWidgets('the ensaio lights its play once there is a part to hear', (
    tester,
  ) async {
    final container = await pumpSala(tester, SalaHarness());
    final notifier = container.read(salaSessionProvider.notifier);
    bool? tocavel() => tester
        .widget<Semantics>(byLabel('Ouvir o ensaio até aqui'))
        .properties
        .enabled;

    notifier.goEnsaio();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tocavel(), isFalse);

    notifier.ensaioTap();
    notifier.ensaioTap();
    await tester.pump(const Duration(milliseconds: 100));
    notifier.takeKeep();
    await tester.pump(const Duration(milliseconds: 800));

    expect(tocavel(), isTrue);
  });

  testWidgets('a long press unsticks a retro the room abandoned', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await pumpSala(tester, harness);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.goConversa();
    await tester.pump(const Duration(milliseconds: 200));
    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await tester.pump(const Duration(milliseconds: 200));
    notifier.takeKeep();
    await letTheRehearsalReachTheRoom(tester);
    notifier.startRetro();
    await tester.pump(const Duration(milliseconds: 300));

    harness.room.failWith = const RoomRefused();
    harness.playback.at = const Duration(seconds: 2);
    notifier.cortarTrecho();
    notifier.retroTap();
    await tester.pump(const Duration(milliseconds: 100));
    await confirmarATraducaoNaTela(tester, container);
    await tester.pump(const Duration(milliseconds: 300));
    expect(container.read(salaSessionProvider).needsPerson, isTrue);

    await tester.longPress(find.byType(FacilitatorCircle).first);
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      container.read(salaSessionProvider).voice,
      VoiceState.invite,
      reason: 'a retro travada não tinha saída nenhuma pela tela',
    );
  });

  testWidgets('the way forward does not vanish while the room replays a line', (
    tester,
  ) async {
    final harness = SalaHarness();
    final container = await pumpSala(tester, harness);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.openConvite();
    await tester.pump(const Duration(milliseconds: 400));
    expect(container.read(salaSessionProvider).showEntrada, isTrue);
    expect(
      find.byWidgetPredicate(
        (w) => w is RoundActionButton && w.mood != ButtonMood.lit,
      ),
      findsOneWidget,
    );

    harness.voice.holdNextLine();
    unawaited(notifier.hearAgain());
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      container.read(salaSessionProvider).showEntrada,
      isFalse,
      reason: 'a sala está falando, então o toque não vale agora',
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is RoundActionButton && w.mood != ButtonMood.lit,
      ),
      findsOneWidget,
      reason:
          'mas o alvo não pode sumir: ouvir o panorama de novo leva um a dois '
          'minutos, e a mão já estava a caminho do botão',
    );

    harness.voice.finishHeldLine();
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('the way out of the rehearsal survives playing it', (
    tester,
  ) async {
    final harness = SalaHarness();
    final container = await pumpSala(tester, harness);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.goConversa();
    await tester.pump(const Duration(milliseconds: 300));

    notifier.goEnsaio();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 2));
    notifier.ensaioTap();
    notifier.ensaioTap();
    await tester.pump(const Duration(milliseconds: 300));
    notifier.takeKeep();
    await tester.pump(const Duration(milliseconds: 300));
    expect(byLabel('Ir para a tradução'), findsOneWidget);

    notifier.playTheRehearsal();
    await tester.pump(const Duration(milliseconds: 200));

    expect(container.read(salaSessionProvider).playPing, isTrue);
    expect(
      tester
          .widget<Semantics>(byLabel('Ir para a tradução'))
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
                  of: byLabel('Ir para a tradução'),
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
      final container = await pumpSala(tester, SalaHarness());
      container.read(salaSessionProvider.notifier).conviteTap();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(seconds: 1));

      expect(
        container.read(salaSessionProvider).canHearAgain,
        isTrue,
        reason:
            'o caso precisa mesmo estar oferecendo ouvir de novo para '
            'poder olhar para ele',
      );

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
        pintado.any((cor) => sameTone(cor, ShemaBrand.verdeClaro)),
        isTrue,
        reason:
            'o repetir é verde e periférico: presente para quem procura, '
            'invisível para quem não está procurando',
      );

      expect(
        contrastOf(
          markAsSeen(tester, ouvir, SalaColors.light.paper),
          SalaColors.light.paper,
        ),
        greaterThanOrEqualTo(2.5),
        reason:
            'quieto não é invisível: com o disco fora, a marca ficou em '
            '1,65:1 sobre o papel, metade da barra que o medidor do microfone '
            'fixou em 2,5:1 depois de um laranja afinado no fundo escuro sumir '
            'num tablet ao sol, que é onde esta sala roda',
      );
    },
  );

  testWidgets(
    'the way out of a passage cannot be taken while the microphone is open',
    (tester) async {
      final container = await pumpSala(tester, SalaHarness());
      final notifier = container.read(salaSessionProvider.notifier);
      await notifier.goConversa(pericope: 'P01');
      await tester.pump(const Duration(milliseconds: 300));

      final sair = byLabel('Deixar esta passagem e escolher outra');
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
        .goConversa(pericope: 'P01');
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(
      byLabel('Deixar esta passagem e escolher outra'),
      warnIfMissed: false,
    );
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
      await notifier.goConversa(pericope: 'P01');
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
      container.read(salaSessionProvider.notifier).goConversa();
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
    },
  );

  testWidgets('the way out stays out of reach through every voice of a turn', (
    tester,
  ) async {
    final harness = SalaHarness();
    final container = await pumpSala(tester, harness);
    final notifier = container.read(salaSessionProvider.notifier);
    VoiceState voz() => container.read(salaSessionProvider).voice;
    await notifier.goConversa(pericope: 'P01');
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
      final harness = SalaHarness()..room.failWith = const RoomRefused();
      final container = await pumpSala(tester, harness);
      final notifier = container.read(salaSessionProvider.notifier);
      await notifier.goConversa(pericope: 'P01');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(seconds: 2));

      notifier.conversaTap();
      await tester.pump(const Duration(milliseconds: 200));
      notifier.conversaTap();
      for (var frame = 0; frame < 30; frame++) {
        await tester.pump(const Duration(milliseconds: 200));
        if (container.read(salaSessionProvider).needsPerson) break;
      }

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

    await tester.tap(byLabel('Falar com o facilitador'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      container.read(salaSessionProvider).conviteStep,
      ConviteStep.entrada,
      reason: 'o que vem abaixo só vale com a abertura já dita',
    );
    expect(
      await harness.finished.bookOpened('Ruth'),
      isTrue,
      reason:
          'o resumed só leva à roda num livro já aberto — sem a marca o teste '
          'passaria sem nunca chegar à porta que abria a roda',
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(byLabel('Falar com o facilitador'));
    await tester.pump(const Duration(milliseconds: 200));

    final state = container.read(salaSessionProvider);
    expect(
      state.stage,
      SalaStage.convite,
      reason: 'a volta ao primeiro plano abria a roda por cima do panorama',
    );
    expect(
      state.voice,
      VoiceState.listening,
      reason: 'o toque depois da abertura grava a resposta da equipe',
    );
  });
}
