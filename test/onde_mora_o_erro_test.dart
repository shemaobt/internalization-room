import 'package:flutter/material.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
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
  BtFindingKind finding = BtFindingKind.addition,
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

  // Todos menos um. O invariante deste laço — o tipo do achado não escolhe pela
  // equipe qual voz corrigir — continua valendo para os outros sete, e é por isso
  // que ele exclui um nome em vez de sumir.
  for (final kind
      in BtFindingKind.values.where((k) => k != BtFindingKind.missing)) {
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

  testWidgets('o achado de falta é a exceção, e a exceção é de produto',
      (tester) async {
    await pumpToPergunta(tester, finding: BtFindingKind.missing);

    // ENG-710. Esta exceção não é de implementação — nada aqui é difícil de
    // desenhar. É de produto: quando a equipe conta os trechos sem errar nada
    // mas conta de menos, não houve erro em nenhuma das duas vozes, houve
    // ausência. Perguntar em qual delas mora o erro é uma pergunta sem resposta:
    // a equipe escolhia uma, o que ela fizesse não resolvia, e a rodada voltava
    // gastando orçamento e outra chamada de modelo.
    //
    // Por isso o laço acima exclui este nome, e não o contrário. Se alguém
    // 'consertar' isto devolvendo missing ao laço, a pergunta sem resposta volta
    // com ele.
    expect(byLabel(micMaterna), findsNothing);
    expect(byLabel(micRetro), findsNothing);

    // Ouvir continua livre: ouvir não decide nada, e sem ouvir a própria voz a
    // equipe não tem como saber o que faltou.
    expect(byLabel(ouvirMaterna), findsOneWidget);
    expect(byLabel(ouvirRetro), findsOneWidget);
    expect(byLabel(refazerParteLabel), findsOneWidget);
  });

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


  testWidgets('a correction that runs the room out reaches the team',
      (tester) async {
    final container = await pumpToPergunta(tester);
    harnessDaVez!.room.replaceNeedsPerson = true;

    await recontarAExplicacao(tester, container);

    expect(container.read(salaSessionProvider).needsPerson, isTrue,
        reason: 'a sala parou de aceitar e a equipe não vê nada: continua '
            'tentando corrigir numa sala que já desistiu, e ninguém chama a '
            'pessoa que poderia destravá-la');
    expect(harnessDaVez!.room.personsAsked, 1,
        reason: 'e o facilitador precisa ser chamado, senão a equipe fica '
            'parada esperando alguém que não foi avisado');
    closeTheRoom(container);
  });

  testWidgets('the answer to that correction is not lost with the warning',
      (tester) async {
    final container = await pumpToPergunta(tester);
    harnessDaVez!.room.replaceNeedsPerson = true;

    await recontarAExplicacao(tester, container);

    expect(
      container.read(salaSessionProvider).btTrechos.map((t) => t.segmentId),
      ['trecho-1-v1', 'trecho-2'],
      reason: 'perder a resposta junto com o aviso seria pior que o problema: '
          'a equipe ficaria sem saber o que aconteceu com a gravação que '
          'acabou de fazer, justamente quando a sala parou',
    );
    closeTheRoom(container);
  });

  testWidgets('an ordinary correction changes nothing', (tester) async {
    final container = await pumpToPergunta(tester);

    await recontarAExplicacao(tester, container);

    expect(container.read(salaSessionProvider).needsPerson, isFalse,
        reason: 'ler um campo novo não pode mandar para uma pessoa quem só '
            'corrigiu um trecho como sempre se corrigiu');
    expect(harnessDaVez!.room.personsAsked, 0);
    expect(container.read(salaSessionProvider).btPhase, BtPhase.findings,
        reason: 'e a correção comum termina no veredito, que é onde a fatia '
            'anterior a faz terminar: quem só corrigiu um trecho continua '
            'sendo levado ao resultado dele');
  });

  testWidgets('a room that sends no such field sends nobody for a person',
      (tester) async {
    final container = await pumpToPergunta(tester);

    // Nothing is switched on: this is the server that is in production today, which does
    // not carry the field at all.
    await recontarAExplicacao(tester, container);

    expect(container.read(salaSessionProvider).needsPerson, isFalse,
        reason: 'o campo só passa a existir quando a ENG-685 for mesclada, e '
            'até lá toda resposta real chega sem ele — tratar essa ausência '
            'como aviso pararia a sala contra o servidor que está no ar');
    expect(harnessDaVez!.room.personsAsked, 0);
  });

  test('a correction answer with no such field asks for nobody', () {
    expect(TellingAgain.fromJson(const {'captured': true}).needsPerson, isFalse,
        reason: 'a ausência atravessa a leitura da resposta, não só o dublê: '
            'é aqui que um "sem notícia" viraria "pare tudo"');
    expect(
        TellingAgain.fromJson(const {'captured': true, 'needs_person': true})
            .needsPerson,
        isTrue,
        reason: 'e o controle positivo, para um campo que fosse lido do nome '
            'errado passar despercebido');
  });

  testWidgets('the room can run out on the first of the two mother-tongue steps',
      (tester) async {
    final container = await pumpToPergunta(tester);
    harnessDaVez!.room.replaceNeedsPerson = true;

    await regravarAMaterna(tester, container);

    expect(container.read(salaSessionProvider).needsPerson, isTrue,
        reason: 'a voz materna é substituída por uma chamada à mesma rota, e '
            'a sala pode desistir já nela: um aviso lido só no segundo passo '
            'abriria o microfone do contar numa sala que já parou');
    expect(container.read(salaSessionProvider).btPhase,
        isNot(BtPhase.capturing),
        reason: 'e ninguém é mandado contar depois disso');
    closeTheRoom(container);
  });

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

  // The two slices meet in the same method, and the order between them is the whole of
  // this: the answer to the recording they just made first, the room stopping second.

  testWidgets('a room still taking work carries a good correction to its result',
      (tester) async {
    final container = await pumpToPergunta(tester);
    final harness = harnessDaVez!;
    final antes = vereditosPedidos(harness);

    await recontarAExplicacao(tester, container);

    expect(vereditosPedidos(harness), antes + 1,
        reason: 'sem notícia de esgotamento a correção segue direto ao '
            'veredito: ler um campo novo não pode custar à equipe o caminho '
            'que ela já tinha');
    expect(container.read(salaSessionProvider).needsPerson, isFalse,
        reason: 'e nada nesse caminho pode parar uma sala que não parou');
  });

  testWidgets('a correction that runs the room out both answers and stops',
      (tester) async {
    final container = await pumpToPergunta(tester);
    final harness = harnessDaVez!;
    harness.room.replaceNeedsPerson = true;
    final antes = vereditosPedidos(harness);

    await recontarAExplicacao(tester, container);

    expect(vereditosPedidos(harness), antes + 1,
        reason: 'a equipe descobre o que aconteceu com a gravação que acabou '
            'de fazer: engolir o resultado junto com o aviso a deixaria parada '
            'sem saber sequer se a correção pegou');
    expect(
      container.read(salaSessionProvider).btTrechos.map((t) => t.segmentId),
      ['trecho-1-v1', 'trecho-2'],
      reason: 'e a resposta que chegou fica de pé — é ela o que a equipe '
          'perderia se o aviso viesse no lugar dela',
    );
    expect(container.read(salaSessionProvider).needsPerson, isTrue,
        reason: 'e o pedido de pessoa sobrevive ao caminho do veredito, que '
            'reescreve a voz da sessão de ponta a ponta: pedido antes dele, '
            'a sala volta a convidar a equipe a trabalhar numa sala parada');
    expect(harness.room.personsAsked, 1,
        reason: 'e alguém é de fato chamado, senão a sala para em silêncio');
    closeTheRoom(container);
  });

  testWidgets('the room running out on the mother tongue opens no microphone',
      (tester) async {
    final container = await pumpToPergunta(tester);
    final harness = harnessDaVez!;
    harness.room.replaceNeedsPerson = true;
    final antes = vereditosPedidos(harness);

    await regravarAMaterna(tester, container);

    expect(container.read(salaSessionProvider).needsPerson, isTrue,
        reason: 'a sala pode desistir já no primeiro dos dois passos da voz '
            'materna, e é aí que ela tem de parar');
    expect(container.read(salaSessionProvider).btPhase, isNot(BtPhase.capturing),
        reason: 'e o microfone não abre para uma contagem que o servidor já '
            'não aceitaria');
    expect(vereditosPedidos(harness), antes,
        reason: 'nem se pede veredito de uma correção que parou no meio: a '
            'explicação do trecho ainda está por gravar');
    closeTheRoom(container);
  });

  testWidgets('a room that sends no such field is carried to the result as ever',
      (tester) async {
    final container = await pumpToPergunta(tester);
    final harness = harnessDaVez!;
    final antes = vereditosPedidos(harness);

    // Nothing switched on: the server in production today does not carry the field.
    await recontarAExplicacao(tester, container);

    expect(container.read(salaSessionProvider).needsPerson, isFalse,
        reason: 'ausência é "sem notícia", e tratá-la como aviso pararia a '
            'sala contra o servidor que está no ar');
    expect(vereditosPedidos(harness), antes + 1,
        reason: 'e contra esse servidor a correção continua chegando ao '
            'resultado como a fatia anterior a deixou');
  });

  testWidgets('the call for a person outlives a verdict the network ate',
      (tester) async {
    final container = await pumpToPergunta(tester);
    final harness = harnessDaVez!;
    harness.room.replaceNeedsPerson = true;
    harness.room.failFinishWith = const RoomUnavailable('sem rede');

    await recontarAExplicacao(tester, container);

    expect(harness.room.personsAsked, 1,
        reason: 'a sala disse que parou de aceitar, e a rede caiu no pedido do '
            'veredito que vem logo depois: se o aviso morre junto com o '
            'veredito, ninguém é chamado para a sala que parou');
    expect(container.read(salaSessionProvider).needsPerson, isTrue,
        reason: 'e a equipe tem de ver a sala parada, senão é convidada de '
            'volta a contar trechos numa sala que não os aceita mais — a '
            'notícia não podia depender de o veredito ter chegado');
    closeTheRoom(container);
  });

  testWidgets('a passage the team walked out of calls nobody', (tester) async {
    final container = await pumpToPergunta(tester);
    final harness = harnessDaVez!;
    harness.room.replaceNeedsPerson = true;
    harness.room.duranteOVeredito =
        () => notifier(container).leaveThePassage();

    await recontarAExplicacao(tester, container);
    await tester.pump(const Duration(milliseconds: 400));

    expect(harness.room.personsAsked, 0,
        reason: 'a equipe saiu da passagem enquanto o veredito estava no ar: '
            'chamar um facilitador agora o manda para um tablet que já está '
            'escolhendo outra passagem, e a fila não distingue esse chamado '
            'de um pedido de verdade');
    expect(container.read(salaSessionProvider).needsPerson, isFalse,
        reason: 'e a sala que ela acabou de deixar não pode parar a próxima');
  });

  testWidgets('a passage that came back clean closes instead of calling anybody',
      (tester) async {
    final container = await pumpToPergunta(tester);
    final harness = harnessDaVez!;
    harness.room.replaceNeedsPerson = true;
    harness.room.verdictChecked = true;
    harness.room.verdictFinding = null;

    await recontarAExplicacao(tester, container);
    await tester.pump(const Duration(milliseconds: 900));

    expect(harness.room.personsAsked, 0,
        reason: 'o trabalho ficou correto, então o orçamento esgotado deixou '
            'de importar: não há mais o que corrigir, e convocar alguém para '
            'uma passagem concluída é ruído que corrói a confiança na fila do '
            'facilitador');
    expect(container.read(salaSessionProvider).stage, SalaStage.fim,
        reason: 'e a passagem termina como qualquer outra que ficou limpa — '
            'parar a sala aqui prenderia a equipe num fecho que já aconteceu');

    // The closing runs on its own timers; let them out so the test does not end holding
    // the room's clock.
    notifier(container).leaveThePassage();
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('a clean verdict on an ordinary budget closes as it always did',
      (tester) async {
    final container = await pumpToPergunta(tester);
    final harness = harnessDaVez!;
    harness.room.verdictChecked = true;
    harness.room.verdictFinding = null;

    await recontarAExplicacao(tester, container);
    await tester.pump(const Duration(milliseconds: 900));

    expect(harness.room.personsAsked, 0);
    expect(container.read(salaSessionProvider).stage, SalaStage.fim,
        reason: 'o controle: sem o campo em jogo o fecho é o de sempre, senão '
            'o caso acima passaria por um fecho que nunca acontece');

    notifier(container).leaveThePassage();
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('the pointed stretch is told apart from the others',
      (tester) async {
    await pumpToPergunta(tester);

    expect(byLabel(contaApontada), findsOneWidget,
        reason: 'a sala não tem texto na tela, então a equipe só descobre onde '
            'está o problema se a conta daquele trecho se distinguir');
  });
}
