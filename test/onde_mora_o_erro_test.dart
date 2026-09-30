import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';

const ouvirOTrecho = 'Ouvir o trecho e a tradução';
const micParteLabel = 'Gravar a parte de novo na língua materna';
const micRetro = 'Traduzir este trecho de novo';
const confirmar = 'Confirmar a tradução e seguir';

SalaHarness? harnessDaVez;

SalaSessionNotifier notifier(ProviderContainer c) =>
    c.read(salaSessionProvider.notifier);

/// A team that told two stretches back and got a finding on the first.
Future<ProviderContainer> pumpToPergunta(
  WidgetTester tester, {
  String? trecho = 'trecho-1',
}) async {
  final harness = SalaHarness(filaEmMemoria: true)
    ..room.verdictChecked = false
    ..room.verdictHasFinding = true
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
    notifier.retroTap();
    await tester.pump(const Duration(milliseconds: 200));
    await confirmarATraducaoNaTela(tester, container);
    await tester.pump(const Duration(milliseconds: 600));
  }
  harness.playback.finishPlayback();
  await tester.pump(const Duration(milliseconds: 200));
  await notifier.finishBackTranslation();
  await tester.pump(const Duration(milliseconds: 300));
  return container;
}

/// How many times the room was asked for a verdict. Each entry is one such ask reaching
/// the room, which is the whole point: the team gets an answer only because somebody
/// asked for one.
int vereditosPedidos(SalaHarness harness) =>
    harness.room.playedByTakeSent.length;

/// Close the microphone the room opened, which is what ends a telling.
Future<void> terminarACaptura(
  WidgetTester tester,
  ProviderContainer container,
) async {
  notifier(container).retroTap();
  await tester.pump(const Duration(milliseconds: 800));
}

/// The error was in the telling, so only the telling is redone: the azul microphone lands
/// on the translation, the circle records over the old telling, the check sends it.
Future<void> traduzirDeNovo(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.tap(byLabel(micRetro));
  await tester.pump(const Duration(milliseconds: 300));
  notifier(container).retroTap();
  await tester.pump(const Duration(milliseconds: 300));
  await terminarACaptura(tester, container);
  await tester.tap(byLabel(confirmar));
  await tester.pump(const Duration(milliseconds: 800));
}

/// What one correction leaves behind, read the way the team meets it.
typedef CorrecaoFeita = ({
  BtPhase phase,
  VoiceState voice,
  bool warning,
  bool needsPerson,
  int pessoasChamadas,
});

/// Take the short way once, with or without the room asking for a person, and read what
/// the room was left in.
Future<CorrecaoFeita> correcaoComResposta(
  WidgetTester tester, {
  required bool aSalaPedeUmaPessoa,
}) async {
  final container = await pumpToPergunta(tester);
  final harness = harnessDaVez!;
  harness.room.replaceNeedsPerson = aSalaPedeUmaPessoa;

  await traduzirDeNovo(tester, container);

  final state = container.read(salaSessionProvider);
  final feita = (
    phase: state.btPhase,
    voice: state.voice,
    warning: state.warning,
    needsPerson: state.needsPerson,
    pessoasChamadas: harness.room.personsAsked,
  );
  // A tela sai antes da sala: deixá-la montada sobre um container fechado faria o
  // gesto seguinte procurar botões numa árvore que já não tem sessão nenhuma.
  await tester.pumpWidget(const SizedBox.shrink());
  closeTheRoom(container);
  return feita;
}

void main() {
  testWidgets('both voices are offered when there is a finding', (
    tester,
  ) async {
    await pumpToPergunta(tester);

    expect(
      byLabel(micParteLabel),
      findsOneWidget,
      reason:
          'o tipo do achado decidia sozinho pela equipe, e um tipo '
          'escondia a saída de traduzir de novo',
    );
    expect(byLabel(micRetro), findsOneWidget);
    expect(byLabel(ouvirOTrecho), findsOneWidget);
  });

  testWidgets('choosing only the telling leaves the mother tongue untouched', (
    tester,
  ) async {
    final container = await pumpToPergunta(tester);

    final harness = harnessDaVez!;

    await tester.tap(byLabel(micRetro));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      container.read(salaSessionProvider).btPhase,
      BtPhase.playing,
      reason:
          'só o contar escorregou, então a equipe cai na tradução daquele '
          'trecho para contá-lo de novo',
    );

    notifier(container).retroTap();
    await tester.pump(const Duration(milliseconds: 300));
    await terminarACaptura(tester, container);
    await tester.tap(byLabel(confirmar));
    await tester.pump(const Duration(milliseconds: 600));

    expect(
      harness.room.replacesAsked,
      ['trecho-1@gravacao-1:0-10000'],
      reason:
          'a explicação nova cobre exatamente o mesmo recorte: mesma '
          'gravação, mesmo início, mesmo fim — a voz em língua materna '
          'daquele trecho não é tocada',
    );
    expect(
      container.read(salaSessionProvider).stage,
      SalaStage.retro,
      reason: 'sair para o ensaio seria refazer a gravação materna',
    );
  });

  testWidgets('listening is free and decides nothing', (tester) async {
    final container = await pumpToPergunta(tester);

    final harness = harnessDaVez!;
    harness.playback.played.clear();

    await tester.tap(byLabel(ouvirOTrecho));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      container.read(salaSessionProvider).btPhase,
      BtPhase.findings,
      reason:
          'ouvir não é escolher — a equipe precisa poder comparar as '
          'duas vozes sem se comprometer com nenhuma',
    );
    expect(
      harness.playback.ranges,
      isNotEmpty,
      reason:
          'e ouvir tem de ouvir: o player de madeira toca a fatia da '
          'gravação em língua materna',
    );

    harness.playback.played.clear();
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(salaSessionProvider).btPhase, BtPhase.findings);
    expect(
      harness.playback.played,
      isNotEmpty,
      reason:
          'depois da materna o play toca o contar em português daquele '
          'trecho — sem isso a equipe compara uma voz com o silêncio',
    );
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets(
    'a finding that names no stretch still falls to the whole thing',
    (tester) async {
      final container = await pumpToPergunta(tester, trecho: null);

      expect(
        tester.widget<Semantics>(byLabel(micParteLabel)).properties.enabled,
        isFalse,
        reason:
            'sem trecho apontado não há o que substituir, e o achado '
            'pergunta sobre um trecho: o microfone fica apagado, nunca '
            'escondido (ADR 0040)',
      );
      expect(
        tester.widget<Semantics>(byLabel(micRetro)).properties.enabled,
        isFalse,
      );
      expect(
        container.read(salaSessionProvider).btPhase,
        BtPhase.findings,
        reason: 'o caminho de hoje para achado sem ponteiro não muda',
      );
    },
  );

  testWidgets('a correction that runs the room out warns and stops nothing', (
    tester,
  ) async {
    final comum = await correcaoComResposta(tester, aSalaPedeUmaPessoa: false);
    final avisada = await correcaoComResposta(tester, aSalaPedeUmaPessoa: true);

    expect(
      avisada.warning,
      isTrue,
      reason:
          'o orçamento esgotado é um aviso em toda rota por onde chega: '
          'alguém é chamado para vir olhar e nada é recusado à equipe',
    );
    expect(
      avisada.needsPerson,
      isFalse,
      reason:
          'uma parada bloqueante prende a equipe até a mesa atender, e '
          'a mesa não é chamada por um aviso',
    );
    expect(
      avisada.needsPerson,
      isFalse,
      reason: 'o círculo tem de ficar na cor do aviso, não na da parada',
    );
    expect(
      avisada.pessoasChamadas,
      0,
      reason:
          'a sala já pediu a pessoa ao marcar o aviso; o pedido do '
          'tablet marca a parada como bloqueante e viraria o aviso na '
          'parada que a regra proíbe',
    );
    expect(
      (avisada.phase, avisada.voice),
      (comum.phase, comum.voice),
      reason:
          'a sala fica onde a mesma correção sem o campo a deixa — é '
          'essa igualdade que diz que nada foi recusado à equipe',
    );
  });

  testWidgets('the answer to that correction is not lost with the warning', (
    tester,
  ) async {
    final container = await pumpToPergunta(tester);
    harnessDaVez!.room.replaceNeedsPerson = true;

    await traduzirDeNovo(tester, container);

    expect(
      container.read(salaSessionProvider).btTrechos.map((t) => t.segmentId),
      ['trecho-1-v1', 'trecho-2'],
      reason:
          'perder a resposta junto com o aviso seria pior que o problema: '
          'a equipe ficaria sem saber o que aconteceu com a gravação que '
          'acabou de fazer, justamente quando a sala avisou',
    );
    expect(
      container.read(salaSessionProvider).warning,
      isTrue,
      reason:
          'e o aviso chega junto com ela: guardar a resposta e engolir '
          'o aviso deixaria ninguém a caminho de uma sala que pediu alguém',
    );
    closeTheRoom(container);
  });

  testWidgets('a correction the room made nothing of also only warns', (
    tester,
  ) async {
    final container = await pumpToPergunta(tester);
    final harness = harnessDaVez!;
    final trechosAntes = container
        .read(salaSessionProvider)
        .btTrechos
        .map((t) => t.segmentId);
    harness.room
      ..replaceCaptured = false
      ..replaceNeedsPerson = true;

    await traduzirDeNovo(tester, container);

    final state = container.read(salaSessionProvider);
    expect(
      state.btTrechos.map((t) => t.segmentId),
      trechosAntes,
      reason:
          'a sala não fez nada da correção, então os trechos ficam como '
          'estavam — uma explicação não se troca por uma vazia',
    );
    expect(
      state.warning,
      isTrue,
      reason:
          'e o aviso que veio com a recusa vale na mesma: o orçamento '
          'foi gasto pela gravação que a equipe acabou de fazer',
    );
    expect(
      state.btPhase,
      BtPhase.playing,
      reason: 'a equipe volta a ouvir e a contar, como volta sem o campo',
    );
    expect(
      state.voice,
      VoiceState.invite,
      reason: 'e é convidada a falar, não deixada diante de uma sala parada',
    );
    expect(
      harness.room.personsAsked,
      0,
      reason: 'ninguém é chamado pelo tablet sobre um aviso',
    );
    closeTheRoom(container);
  });

  testWidgets('an ordinary correction changes nothing', (tester) async {
    final container = await pumpToPergunta(tester);

    await traduzirDeNovo(tester, container);

    expect(
      container.read(salaSessionProvider).needsPerson,
      isFalse,
      reason:
          'ler um campo novo não pode mandar para uma pessoa quem só '
          'corrigiu um trecho como sempre se corrigiu',
    );
    expect(harnessDaVez!.room.personsAsked, 0);
    expect(
      container.read(salaSessionProvider).btPhase,
      BtPhase.findings,
      reason:
          'e a correção comum termina no veredito, que é onde a fatia '
          'anterior a faz terminar: quem só corrigiu um trecho continua '
          'sendo levado ao resultado dele',
    );
  });

  testWidgets('a room that sends no such field sends nobody for a person', (
    tester,
  ) async {
    final container = await pumpToPergunta(tester);

    // Nothing is switched on: this is the server that is in production today, which does
    // not carry the field at all.
    await traduzirDeNovo(tester, container);

    expect(
      container.read(salaSessionProvider).warning,
      isFalse,
      reason:
          'ausência é "sem notícia": acender o aviso sobre toda correção '
          'poria um verde permanente no círculo e a fila do facilitador '
          'encheria de salas que nunca pediram nada',
    );
    expect(harnessDaVez!.room.personsAsked, 0);
  });

  test('a correction answer with no such field asks for nobody', () {
    expect(
      TellingAgain.fromJson(const {'captured': true}).needsPerson,
      isFalse,
      reason:
          'a ausência atravessa a leitura da resposta, não só o dublê: '
          'é aqui que um "sem notícia" viraria "pare tudo"',
    );
    expect(
      TellingAgain.fromJson(const {
        'captured': true,
        'needs_person': true,
      }).needsPerson,
      isTrue,
      reason:
          'e o controle positivo, para um campo que fosse lido do nome '
          'errado passar despercebido',
    );
  });

  testWidgets('finishing a correction reaches its result on its own', (
    tester,
  ) async {
    final container = await pumpToPergunta(tester);
    final harness = harnessDaVez!;
    final antes = vereditosPedidos(harness);

    await traduzirDeNovo(tester, container);

    expect(
      vereditosPedidos(harness),
      antes + 1,
      reason:
          'a equipe grava a correção e a sala fica muda: para saber se '
          'resolveu alguém precisa apertar "terminei" de novo, e ninguém '
          'diz isso a ela — do lugar onde ela está, corrigiu e nada '
          'aconteceu',
    );
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
        harness.room.failReplaceWith = const NetworkFailed('sem rede');
      }

      await traduzirDeNovo(tester, container);

      expect(
        vereditosPedidos(harness),
        antes,
        reason:
            'a correção não chegou ao servidor, então não há o que '
            'julgar: pedir o veredito aqui gastaria uma leitura inteira da '
            'passagem para dizer à equipe que o erro continua lá',
      );
      expect(
        container.read(salaSessionProvider).canFinishBackTranslation,
        isTrue,
        reason:
            'e ela precisa ficar num lugar de onde consegue tentar de '
            'novo — uma correção que falhou não pode ser um beco',
      );
    });
  }

  testWidgets('a correction never sends the team back to hear the whole '
      'recording', (tester) async {
    final container = await pumpToPergunta(tester);

    await traduzirDeNovo(tester, container);

    expect(
      container.read(salaSessionProvider).btClipEnded,
      isTrue,
      reason:
          'a marca de que a gravação acabou é o que dispensa a equipe de '
          'reouvir o clipe inteiro; se a correção a apagasse, corrigir um '
          'trecho custaria ouvir tudo outra vez para poder seguir',
    );
  });

  // The two slices meet in the same method, and the order between them is the whole of
  // this: the answer to the recording they just made first, the room stopping second.

  testWidgets(
    'a room still taking work carries a good correction to its result',
    (tester) async {
      final container = await pumpToPergunta(tester);
      final harness = harnessDaVez!;
      final antes = vereditosPedidos(harness);

      await traduzirDeNovo(tester, container);

      expect(
        vereditosPedidos(harness),
        antes + 1,
        reason:
            'sem notícia de esgotamento a correção segue direto ao '
            'veredito: ler um campo novo não pode custar à equipe o caminho '
            'que ela já tinha',
      );
      expect(
        container.read(salaSessionProvider).needsPerson,
        isFalse,
        reason: 'e nada nesse caminho pode parar uma sala que não parou',
      );
    },
  );

  testWidgets('a correction that runs the room out both answers and warns', (
    tester,
  ) async {
    final container = await pumpToPergunta(tester);
    final harness = harnessDaVez!;
    harness.room.replaceNeedsPerson = true;
    final antes = vereditosPedidos(harness);

    await traduzirDeNovo(tester, container);

    expect(
      vereditosPedidos(harness),
      antes + 1,
      reason:
          'a equipe descobre o que aconteceu com a gravação que acabou '
          'de fazer: engolir o resultado junto com o aviso a deixaria parada '
          'sem saber sequer se a correção pegou',
    );
    expect(
      container.read(salaSessionProvider).btTrechos.map((t) => t.segmentId),
      ['trecho-1-v1', 'trecho-2'],
      reason:
          'e a resposta que chegou fica de pé — é ela o que a equipe '
          'perderia se o aviso viesse no lugar dela',
    );
    expect(
      container.read(salaSessionProvider).warning,
      isTrue,
      reason:
          'e o aviso sobrevive ao caminho do veredito, que reescreve a '
          'voz da sessão de ponta a ponta: perdido nele, ninguém vem olhar '
          'uma sala que pediu alguém',
    );
    expect(
      container.read(salaSessionProvider).needsPerson,
      isFalse,
      reason:
          'e a sala não para: o veredito chegou e a equipe segue com '
          'ele, que é a diferença entre um aviso e uma parada',
    );
    expect(
      harness.room.personsAsked,
      0,
      reason:
          'quem pediu a pessoa foi a sala, ao marcar o aviso; o pedido '
          'do tablet marcaria a parada como bloqueante',
    );
    closeTheRoom(container);
  });

  testWidgets(
    'a room that sends no such field is carried to the result as ever',
    (tester) async {
      final container = await pumpToPergunta(tester);
      final harness = harnessDaVez!;
      final antes = vereditosPedidos(harness);

      // Nothing switched on: the server in production today does not carry the field.
      await traduzirDeNovo(tester, container);

      expect(
        container.read(salaSessionProvider).warning,
        isFalse,
        reason:
            'ausência é "sem notícia", e acendê-la como aviso chamaria '
            'alguém a toda correção comum',
      );
      expect(
        vereditosPedidos(harness),
        antes + 1,
        reason:
            'e contra esse servidor a correção continua chegando ao '
            'resultado como a fatia anterior a deixou',
      );
    },
  );

  testWidgets('the warning outlives a verdict the network ate', (tester) async {
    final container = await pumpToPergunta(tester);
    final harness = harnessDaVez!;
    harness.room.replaceNeedsPerson = true;
    harness.room.failFinishWith = const NetworkFailed('sem rede');

    await traduzirDeNovo(tester, container);

    expect(
      container.read(salaSessionProvider).warning,
      isTrue,
      reason:
          'a sala pediu alguém, e a rede caiu no pedido do veredito que '
          'vem logo depois: se o aviso morre junto com o veredito, ninguém '
          'vem olhar uma sala que chamou',
    );
    expect(
      harness.room.personsAsked,
      0,
      reason:
          'e nem uma rede caída faz o tablet pedir a pessoa, que é o '
          'pedido que marca a parada como bloqueante',
    );
    expect(
      container.read(salaSessionProvider).needsPerson,
      isFalse,
      reason:
          'a rede que comeu o veredito não é a mesa: só ela prende a '
          'equipe',
    );
    closeTheRoom(container);
  });

  testWidgets('a passage the team walked out of calls nobody', (tester) async {
    final container = await pumpToPergunta(tester);
    final harness = harnessDaVez!;
    harness.room.replaceNeedsPerson = true;
    harness.room.duranteOVeredito = () => notifier(container).leaveThePassage();

    await traduzirDeNovo(tester, container);
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      harness.room.personsAsked,
      0,
      reason:
          'a equipe saiu da passagem enquanto o veredito estava no ar: '
          'chamar um facilitador agora o manda para um tablet que já está '
          'escolhendo outra passagem, e a fila não distingue esse chamado '
          'de um pedido de verdade',
    );
    expect(
      container.read(salaSessionProvider).warning,
      isFalse,
      reason:
          'e o aviso da sala que ela acabou de deixar não pode acender o '
          'círculo da próxima: verde permanente sobre uma passagem que '
          'ninguém avisou é a mentira de sempre na cor oposta',
    );
  });

  testWidgets(
    'a passage that came back clean closes instead of calling anybody',
    (tester) async {
      final container = await pumpToPergunta(tester);
      final harness = harnessDaVez!;
      harness.room.replaceNeedsPerson = true;
      harness.room.verdictChecked = true;
      harness.room.verdictHasFinding = false;

      await traduzirDeNovo(tester, container);
      await tester.pump(const Duration(milliseconds: 900));

      expect(
        harness.room.personsAsked,
        0,
        reason:
            'o trabalho ficou correto, então o orçamento esgotado deixou '
            'de importar: não há mais o que corrigir, e convocar alguém para '
            'uma passagem concluída é ruído que corrói a confiança na fila do '
            'facilitador',
      );

      await notifier(container).aprovarRascunhoFinal();
      await tester.pump(const Duration(seconds: 1));

      expect(
        container.read(salaSessionProvider).stage,
        SalaStage.fim,
        reason:
            'e a passagem termina como qualquer outra que ficou limpa — '
            'parar a sala aqui prenderia a equipe num fecho que já aconteceu',
      );
      expect(
        container.read(salaSessionProvider).warning,
        isTrue,
        reason:
            'o aviso é escrito antes do veredito, e um fecho limpo não o '
            'apaga: quem foi chamado a vir olhar continua a ser esperado',
      );

      // The closing runs on its own timers; let them out so the test does not end holding
      // the room's clock.
      notifier(container).leaveThePassage();
      await tester.pump(const Duration(milliseconds: 200));
    },
  );

  testWidgets('a clean verdict on an ordinary budget closes as it always did', (
    tester,
  ) async {
    final container = await pumpToPergunta(tester);
    final harness = harnessDaVez!;
    harness.room.verdictChecked = true;
    harness.room.verdictHasFinding = false;

    await traduzirDeNovo(tester, container);
    await tester.pump(const Duration(milliseconds: 900));

    expect(harness.room.personsAsked, 0);

    await notifier(container).aprovarRascunhoFinal();
    await tester.pump(const Duration(seconds: 1));

    expect(
      container.read(salaSessionProvider).stage,
      SalaStage.fim,
      reason:
          'o controle: sem o campo em jogo o fecho é o de sempre, senão '
          'o caso acima passaria por um fecho que nunca acontece',
    );

    notifier(container).leaveThePassage();
    await tester.pump(const Duration(milliseconds: 200));
  });
}
