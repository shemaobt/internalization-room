import 'package:flutter/material.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/onde_mora_grade.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';

const ouvirMaterna = 'Ouvir a voz de vocês, na língua materna';
const ouvirRetro = 'Ouvir o contar em português';
const micMaterna = 'Regravar a voz na língua materna — refaz também o contar';
const micRetro = 'Recontar só em português';
const contaApontada = 'Trecho apontado pelo analista';

Finder byLabel(String label) => find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == label,
    );

SalaHarness? harnessDaVez;

SalaSessionNotifier notifier(ProviderContainer c) =>
    c.read(salaSessionProvider.notifier);

/// A team that told two stretches back and got a finding on the first.
Future<ProviderContainer> pumpToPergunta(
  WidgetTester tester, {
  BtFindingKind finding = BtFindingKind.missing,
  String? trecho = 'trecho-1',
}) async {
  final harness = SalaHarness(filaEmMemoria: true)
    ..room.verdictChecked = false
    ..room.verdictFinding = finding
    ..room.verdictFindingSegmentId = trecho;
  harnessDaVez = harness;
  final container = harness.container();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await tester.pump(const Duration(milliseconds: 100));

  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.goConversa();
  await tester.pump(const Duration(milliseconds: 200));
  notifier.goEnsaio();
  notifier.ensaioTap();
  notifier.ensaioTap();
  await tester.pump(const Duration(milliseconds: 100));
  notifier.takeKeep();
  await letTheRehearsalReachTheRoom(tester);
  notifier.startRetro();
  await tester.pump(const Duration(milliseconds: 200));

  for (final at in const [Duration(seconds: 10), Duration(seconds: 20)]) {
    harness.playback.at = at;
    notifier.cortarTrecho();
    await tester.pump(const Duration(milliseconds: 200));
    notifier.retroTap();
    await tester.pump(const Duration(milliseconds: 600));
  }
  harness.playback.finishPlayback();
  await tester.pump(const Duration(milliseconds: 200));
  await notifier.finishBackTranslation();
  await tester.pump(const Duration(milliseconds: 300));
  return container;
}

Future<void> _pumpGrade(WidgetTester tester, {required bool podeOuvirRetro}) =>
    tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Center(
          child: OndeMoraGrade(
            onOuvirMaterna: () {},
            onOuvirRetro: () {},
            onRegravarMaterna: () {},
            onRecontar: () {},
            podeOuvirRetro: podeOuvirRetro,
          ),
        ),
      ),
    ));


/// How many times the room was asked for a verdict. Each entry is one such ask reaching
/// the room, which is the whole point: the team gets an answer only because somebody
/// asked for one.
int vereditosPedidos(SalaHarness harness) => harness.room.clipDurationsSent.length;

/// Close the microphone the room opened, which is what ends a telling.
Future<void> terminarACaptura(
  WidgetTester tester,
  ProviderContainer container,
) async {
  notifier(container).retroTap();
  await tester.pump(const Duration(milliseconds: 800));
}

/// The error was in the telling, so only the telling is redone — one step.
Future<void> recontarAExplicacao(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.tap(byLabel(micRetro));
  await tester.pump(const Duration(milliseconds: 300));
  await terminarACaptura(tester, container);
}

/// The error was in the mother tongue, so the recording is redone first. This is only the
/// first of the two steps that correction takes; the telling still has to follow.
Future<void> regravarAMaterna(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.tap(byLabel(micMaterna));
  await tester.pump(const Duration(milliseconds: 300));
  notifier(container).retroTap();
  await tester.pump(const Duration(milliseconds: 200));
  notifier(container).retroTap();
  await letTheRehearsalReachTheRoom(tester);
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('the blue player is dark when the tablet holds no telling',
      (tester) async {
    await _pumpGrade(tester, podeOuvirRetro: false);

    expect(tester.widget<Semantics>(byLabel(ouvirRetro)).properties.enabled,
        isFalse,
        reason: 'numa sessão retomada o contar existe no servidor e o arquivo '
            'não está aqui; um player aceso que responde com silêncio não tem '
            'como se explicar numa sala sem palavra escrita');
    expect(tester.widget<Semantics>(byLabel(micRetro)).properties.enabled,
        isTrue,
        reason: 'escolher não precisa do arquivo: a equipe sabe qual voz errou '
            'sem reouvi-la, e o contar novo é gravado do zero');
    expect(tester.widget<Semantics>(byLabel(ouvirMaterna)).properties.enabled,
        isTrue,
        reason: 'a voz de madeira é fatia do ensaio, que está no tablet');
  });

  testWidgets('both players are live when the tablet holds the telling',
      (tester) async {
    await _pumpGrade(tester, podeOuvirRetro: true);

    expect(tester.widget<Semantics>(byLabel(ouvirRetro)).properties.enabled,
        isTrue);
  });

  for (final kind in BtFindingKind.values) {
    testWidgets('both voices are offered when the finding is ${kind.name}',
        (tester) async {
      await pumpToPergunta(tester, finding: kind);

      expect(byLabel(micMaterna), findsOneWidget,
          reason: 'o tipo do achado decidia sozinho pela equipe, e três tipos '
              'escondiam a saída de recontar');
      expect(byLabel(micRetro), findsOneWidget);
      expect(byLabel(ouvirMaterna), findsOneWidget);
      expect(byLabel(ouvirRetro), findsOneWidget);
    });
  }

  testWidgets('choosing only the telling leaves the mother tongue untouched',
      (tester) async {
    final container = await pumpToPergunta(tester);

    final harness = harnessDaVez!;

    await tester.tap(byLabel(micRetro));
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(salaSessionProvider).btPhase, BtPhase.capturing,
        reason: 'só o contar escorregou, então o microfone abre para a equipe '
            'contar aquele trecho de novo');

    notifier(container).retroTap();
    await tester.pump(const Duration(milliseconds: 600));

    expect(harness.room.replacesAsked, ['trecho-1@gravacao-1:0-10000'],
        reason: 'a explicação nova cobre exatamente o mesmo recorte: mesma '
            'gravação, mesmo início, mesmo fim — a voz em língua materna '
            'daquele trecho não é tocada');
    expect(container.read(salaSessionProvider).stage, SalaStage.retro,
        reason: 'sair para o ensaio seria refazer a gravação materna');
  });

  testWidgets('choosing the voice too records the mother tongue first',
      (tester) async {
    final container = await pumpToPergunta(tester);

    await tester.tap(byLabel(micMaterna));
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(salaSessionProvider).btPhase, BtPhase.gravandoMaterna,
        reason: 'a ordem é regra de produto e não sugestão: regravar o nativo '
            'implica sempre refazer o contar depois, nessa ordem');
    expect(container.read(salaSessionProvider).btPhase,
        isNot(BtPhase.capturing),
        reason: 'a equipe não pode ser levada a contar antes de ter regravado: '
            'o microfone do contar não abre por este caminho');
    expect(harnessDaVez!.room.replacesAsked, isEmpty,
        reason: 'e nada é substituído enquanto a voz nova não existe');
  });

  testWidgets('a stretch back from the room keeps both halves of itself',
      (tester) async {
    final container = await pumpToPergunta(tester);
    final harness = harnessDaVez!;

    // Hearing the pointed stretch is what lets the team divide it where they are
    // listening, and dividing is what makes the room answer with stretches nobody has
    // explained yet — the case where the two halves of this construction disagree.
    await tester.tap(byLabel(ouvirMaterna));
    await tester.pump(const Duration(milliseconds: 300));
    harness.playback.at = const Duration(seconds: 4);
    await notifier(container).dividirTrecho();
    await tester.pump(const Duration(milliseconds: 300));

    final trechos = container.read(salaSessionProvider).btTrechos;
    expect(trechos, hasLength(3),
        reason: 'a leitura da sala é quem manda em quantos trechos existem');

    // The room's half: whether anyone has explained this stretch. It is what the first
    // round's gate consumes, and the app used to throw it away. The two new halves are
    // units the room counts and nobody has told back.
    expect(trechos.map((t) => t.contado).toList(), [false, false, true],
        reason: 'sem isto um trecho à espera é indistinguível de um já '
            'explicado, e o portão da primeira rodada não tem o que ler');

    // The tablet's half: the copy of the telling, which only this tablet holds. It was
    // thrown away on every reading, and the blue voice had nothing to play.
    expect(trechos.last.retroPath, isNotNull,
        reason: 'o trecho que ninguém tocou continua com a sua explicação aqui');
    expect(trechos.take(2).map((t) => t.retroPath).toList(), [null, null],
        reason: 'e uma metade que ninguém contou não guarda arquivo de uma '
            'explicação que não existe');

    // Both halves live in one construction: resolving that conflict by picking a side
    // would have lost the other in silence, and each branch was green on its own.
  });

  testWidgets('listening is free and decides nothing', (tester) async {
    final container = await pumpToPergunta(tester);

    final harness = harnessDaVez!;
    harness.playback.played.clear();

    await tester.tap(byLabel(ouvirMaterna));
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(salaSessionProvider).btPhase, BtPhase.findings,
        reason: 'ouvir não é escolher — a equipe precisa poder comparar as '
            'duas vozes sem se comprometer com nenhuma');
    expect(harness.playback.ranges, isNotEmpty,
        reason: 'e ouvir tem de ouvir: o player de madeira toca a fatia da '
            'gravação em língua materna');

    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    harness.playback.played.clear();

    await tester.tap(byLabel(ouvirRetro));
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(salaSessionProvider).btPhase, BtPhase.findings);
    expect(harness.playback.played, isNotEmpty,
        reason: 'o player azul toca o contar em português daquele trecho — '
            'sem isso a equipe compara uma voz com o silêncio');
  });

  for (final kind in [BtFindingKind.missing, BtFindingKind.addition]) {
    testWidgets(
        'a ${kind.name} finding that names no stretch still falls to the whole '
        'thing', (tester) async {
      final container = await pumpToPergunta(
        tester,
        finding: kind,
        trecho: null,
      );

      expect(byLabel(micMaterna), findsNothing,
          reason: 'sem trecho apontado não há o que substituir, e a grade '
              'pergunta sobre um trecho');
      expect(byLabel(micRetro), findsNothing);
      expect(container.read(salaSessionProvider).btPhase, BtPhase.findings,
          reason: 'o caminho de hoje para achado sem ponteiro não muda — e '
              'isso inclui o tipo continuar governando a queda, que é a '
              'única coisa que ele ainda governa');
    });
  }


  testWidgets('finishing a correction reaches its result on its own',
      (tester) async {
    final container = await pumpToPergunta(tester);
    final harness = harnessDaVez!;
    final antes = vereditosPedidos(harness);

    await recontarAExplicacao(tester, container);

    expect(vereditosPedidos(harness), antes + 1,
        reason: 'a equipe grava a correção e a sala fica muda: para saber se '
            'resolveu alguém precisa apertar "terminei" de novo, e ninguém '
            'diz isso a ela — do lugar onde ela está, corrigiu e nada '
            'aconteceu');
  });

  testWidgets('re-recording the mother tongue reaches the result only after '
      'the retelling', (tester) async {
    final container = await pumpToPergunta(tester);
    final harness = harnessDaVez!;
    final antes = vereditosPedidos(harness);

    await regravarAMaterna(tester, container);

    expect(vereditosPedidos(harness), antes,
        reason: 'a correção pela voz materna tem dois passos e o primeiro não '
            'a termina: pedir o resultado aqui seria julgar um trecho cuja '
            'explicação ainda está por gravar');
    expect(container.read(salaSessionProvider).btPhase, BtPhase.capturing,
        reason: 'e o que vem depois da voz nova é o microfone do contar, na '
            'ordem que o servidor exige');

    await terminarACaptura(tester, container);

    expect(vereditosPedidos(harness), antes + 1,
        reason: 'terminado o segundo passo a correção acabou, e é aí — uma vez '
            'só — que a equipe chega ao resultado dela');
  });

  for (final quebra in ['a sala recusa', 'a rede cai']) {
    testWidgets('a correction the room did not take asks for no verdict '
        '($quebra)', (tester) async {
      final container = await pumpToPergunta(tester);
      final harness = harnessDaVez!;
      final antes = vereditosPedidos(harness);
      if (quebra == 'a sala recusa') {
        harness.room.replaceCaptured = false;
      } else {
        harness.room.failReplaceWith = const RoomUnavailable('sem rede');
      }

      await recontarAExplicacao(tester, container);

      expect(vereditosPedidos(harness), antes,
          reason: 'a correção não chegou ao servidor, então não há o que '
              'julgar: pedir o veredito aqui gastaria uma leitura inteira da '
              'passagem para dizer à equipe que o erro continua lá');
      expect(container.read(salaSessionProvider).canFinishBackTranslation,
          isTrue,
          reason: 'e ela precisa ficar num lugar de onde consegue tentar de '
              'novo — uma correção que falhou não pode ser um beco');
    });
  }

  testWidgets('a correction never sends the team back to hear the whole '
      'recording', (tester) async {
    final container = await pumpToPergunta(tester);

    await recontarAExplicacao(tester, container);

    expect(container.read(salaSessionProvider).btClipEnded, isTrue,
        reason: 'a marca de que a gravação acabou é o que dispensa a equipe de '
            'reouvir o clipe inteiro; se a correção a apagasse, corrigir um '
            'trecho custaria ouvir tudo outra vez para poder seguir');
  });

  testWidgets('the pointed stretch is told apart from the others',
      (tester) async {
    await pumpToPergunta(tester);

    expect(byLabel(contaApontada), findsOneWidget,
        reason: 'a sala não tem texto na tela, então a equipe só descobre onde '
            'está o problema se a conta daquele trecho se distinguir');
  });
}
