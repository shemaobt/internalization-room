import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/approval_answer.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'um_ensaio_de_tres_partes.dart';
import 'scenario_helpers.dart';

const _aprovar = 'Aprovar como rascunho final';
const _ouvir = 'Ouvir a gravação';

FacilitatorCircle _circulo(WidgetTester tester) =>
    tester.widget<FacilitatorCircle>(find.byType(FacilitatorCircle));

SalaSessionNotifier _notifier(ProviderContainer c) =>
    c.read(salaSessionProvider.notifier);

SalaSessionState _estado(ProviderContainer c) => c.read(salaSessionProvider);

class _Conferida {
  final SalaHarness harness;
  final ProviderContainer container;

  _Conferida(this.harness, this.container);
}

/// A team standing on a passage the room has just called checked, with nothing pressed.
Future<_Conferida> _ateAConferida(
  WidgetTester tester, {
  SalaHarness? comEsta,
}) async {
  final harness = comEsta ?? SalaHarness(filaEmMemoria: true);
  harness.room.verdictChecked = true;
  final container = harness.container();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await tester.pump(const Duration(milliseconds: 100));

  final sala = _notifier(container);
  await sala.goConversa(pericope: 'P01');
  await tester.pump(const Duration(milliseconds: 200));
  sala.goEnsaio();
  sala.ensaioTap();
  sala.ensaioTap();
  await tester.pump(const Duration(milliseconds: 100));
  sala.takeKeep();
  await letTheRehearsalReachTheRoom(tester);
  sala.startRetro();
  await tester.pump(const Duration(milliseconds: 200));

  harness.playback.at = const Duration(seconds: 10);
  sala.cortarTrecho();
  sala.retroTap();
  await tester.pump(const Duration(milliseconds: 200));
  await confirmarATraducaoNaTela(tester, container);
  await tester.pump(const Duration(milliseconds: 600));
  harness.playback.finishPlayback();
  await tester.pump(const Duration(milliseconds: 200));
  await sala.finishBackTranslation();
  await tester.pump(const Duration(milliseconds: 300));

  return _Conferida(harness, container);
}

/// Three parts of a rehearsal told back whole and the check clean: the room standing on the
/// approval press, holding parts a refusal can name by their own recording and stretches
/// this tablet cut itself, which the room has never named back.
Future<Sala> _tresPartesAteAConferida() async {
  final it = await umEnsaioDeTresPartesContadoInteiro();
  it.harness.room.verdictChecked = true;
  await pedirOVeredito(it);
  expect(
    it.estado.btPhase,
    BtPhase.conferida,
    reason:
        'o cenário só mede alguma coisa se a sala chegar ao gesto de '
        'aprovar',
  );
  return it;
}

Future<void> _aprovarEEsperar(WidgetTester tester) async {
  await tester.tap(byLabel(_aprovar));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets(
    'o veredito limpo deixa a sala aberta com o botão de ouvir e o de aprovar',
    (tester) async {
      final it = await _ateAConferida(tester);

      expect(
        _estado(it.container).btPhase,
        BtPhase.conferida,
        reason:
            'a sala deu a passagem por conferida — se não der, este cenário '
            'não chega ao que mede',
      );
      expect(
        byLabel(_ouvir),
        findsOneWidget,
        reason:
            'a fala do veredito convida a equipe a ouvir a gravação mais '
            'uma vez, e o convite sem o gesto é uma tela sem saída',
      );
      expect(
        byLabel(_aprovar),
        findsOneWidget,
        reason:
            'e a aprovação é o gesto que faltava: a passagem terminava '
            'sozinha, sem nada que registrasse que a equipe aprovou o que fez',
      );

      await tester.pump(const Duration(seconds: 2));

      expect(
        _estado(it.container).stage,
        SalaStage.retro,
        reason:
            'nenhum relógio fecha a sala: o fecho passou a ser coisa da '
            'aprovação, e 700ms depois da conferida a equipe era levada embora '
            'de uma tela que ela nunca chegou a tocar',
      );
      expect(
        it.harness.finished.done,
        isNot(contains('Ruth/P01')),
        reason: 'uma passagem que a equipe ainda não aprovou não está feita',
      );
      expect(
        it.harness.emAberto.rows,
        contains('Ruth/P01'),
        reason:
            'e segue sendo ponto de retomada: fechar o app aqui tem de '
            'trazer a equipe de volta a este mesmo gesto',
      );

      await tester.pump(it.harness.fimLinger + const Duration(seconds: 2));

      expect(
        _estado(it.container).stage,
        SalaStage.retro,
        reason:
            'nem depois da demora do fim: não há corrente de relógios '
            'nenhuma pendurada na conferida',
      );
    },
  );

  testWidgets(
    'aprovar manda a release com o aparelho, fala a linha P3 e só então fecha o colar',
    (tester) async {
      final it = await _ateAConferida(tester);
      final sessao = _estado(it.container).sessionId;
      final falasAntes = it.harness.voice.assets.length;

      it.harness.voice.holdNextLine();
      await tester.tap(byLabel(_aprovar));
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        it.harness.room.releasesAsked,
        [sessao],
        reason: 'um pedido, para a sessão desta passagem',
      );
      expect(
        it.harness.voice.assets.skip(falasAntes),
        contains(fixedLineAsset(approvedLine, testLanguage)),
        reason:
            'a linha da aprovação é a quarta das falas de processo da '
            'Marcia, tocada do pacote: a sala tem de poder dizê-la sem rede',
      );
      // Passado o tempo inteiro que o fecho leva, com a fala ainda na boca da sala: o
      // colar fecha 700ms depois de ser mandado fechar, então medir logo após o toque diz
      // apenas que 700ms não passaram, e um fecho mandado antes da fala passaria por aqui.
      await tester.pump(const Duration(seconds: 2));

      expect(
        _estado(it.container).stage,
        SalaStage.retro,
        reason:
            'e a fala vem antes do fecho: fechar por cima dela tiraria a '
            'equipe da tela no meio da frase que diz o que acabou de acontecer',
      );

      it.harness.voice.finishHeldLine();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 700));

      expect(
        _estado(it.container).stage,
        SalaStage.fim,
        reason: 'dita a linha, o colar fecha como sempre fechou',
      );

      expect(
        it.harness.finished.done,
        contains('Ruth/P01'),
        reason: 'a passagem está feita porque a equipe a aprovou',
      );
      expect(
        it.harness.emAberto.rows,
        isNot(contains('Ruth/P01')),
        reason: 'e não há mais a que voltar',
      );

      closeTheRoom(it.container);
    },
  );

  testWidgets('apertar duas vezes fala uma vez e manda um pedido só', (
    tester,
  ) async {
    final it = await _ateAConferida(tester);
    final falasAntes = it.harness.voice.assets.length;

    it.harness.room.holdNextRelease();
    await tester.tap(byLabel(_aprovar));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(byLabel(_aprovar));
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      it.harness.room.releasesAsked,
      hasLength(1),
      reason:
          'a segunda pressão cai num pedido que já está no ar: duas '
          'releases da mesma passagem é a equipe cunhando duas versões de um '
          'trabalho só',
    );

    it.harness.room.finishHeldRelease();
    await tester.pump(const Duration(milliseconds: 300));

    final ditas = it.harness.voice.assets
        .skip(falasAntes)
        .where((asset) => asset == fixedLineAsset(approvedLine, testLanguage));
    expect(
      ditas,
      hasLength(1),
      reason:
          'e uma fala só: a sala repetindo a linha da aprovação diz à '
          'equipe que aprovou duas vezes',
    );
    expect(it.harness.room.releasesAsked, hasLength(1));

    closeTheRoom(it.container);
  });

  testWidgets(
    'aprovar de novo depois de a release ter voltado não manda outra',
    (tester) async {
      final it = await _ateAConferida(tester);

      await _aprovarEEsperar(tester);
      expect(it.harness.room.releasesAsked, hasLength(1));
      expect(
        _estado(it.container).stage,
        SalaStage.retro,
        reason:
            'a segunda pressão é feita antes de o colar fechar — depois do '
            'fecho seria a guarda de etapa a recusá-la, e não a da aprovação '
            'que já aconteceu',
      );

      _notifier(it.container).aprovarRascunhoFinal();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        it.harness.room.releasesAsked,
        hasLength(1),
        reason:
            'aprovada uma vez, aprovada: o gesto acabou e o fecho está a '
            'caminho',
      );

      closeTheRoom(it.container);
    },
  );

  for (final codigo in const [
    'no_project',
    'panorama_sessions_never_release',
    'no_rehearsal_audio',
    'coverage_floor_not_met',
    'comprehension_needs_more_work',
    'no_telling_back',
  ]) {
    testWidgets('a recusa por $codigo chama uma pessoa na hora', (
      tester,
    ) async {
      final it = await _ateAConferida(tester);
      final falasAntes = it.harness.voice.assets.length;
      it.harness.room.releaseBlockers = [codigo];

      await _aprovarEEsperar(tester);

      expect(
        _circulo(tester).voice,
        VoiceState.needsPerson,
        reason:
            'o círculo era a única coisa da tela que ainda podia dizer o '
            'que houve, e desenhá-lo verde por cima do halt dizia à equipe que '
            'estava tudo certo: dois botões que as guardas recusam, nenhum '
            'botão de sair, e a fala E0 como único sinal',
      );
      expect(
        _circulo(tester).semanticLabel,
        'Um momento para uma pessoa',
        reason:
            'e a etiqueta acompanha, que é o que a sala tem no lugar de '
            'palavras na tela',
      );

      expect(
        _estado(it.container).needsPerson,
        isTrue,
        reason:
            'é um buraco que a equipe não tapa desta tela: não há porta '
            'para ele, e deixar a passagem de pé sem dizer nada é o botão '
            'morto que a equipe apertava duas vezes antes de alguém vir',
      );
      expect(it.harness.room.personsAsked, 1);
      expect(
        it.harness.voice.assets.skip(falasAntes),
        isNot(contains(fixedLineAsset(approvedLine, testLanguage))),
        reason: 'e nada foi aprovado, então a linha da aprovação não é dita',
      );
      expect(_estado(it.container).stage, SalaStage.retro);
      expect(
        _estado(it.container).btPhase,
        BtPhase.conferida,
        reason:
            'a fase não se move: é o que mantém a tela de pé debaixo da '
            'falha',
      );

      closeTheRoom(it.container);
    });
  }

  testWidgets('uma falha de rede passa pela escada e deixa o botão de pé', (
    tester,
  ) async {
    // A espera entre tentativas é longa de propósito: com a de sempre, a sala já teria
    // voltado sozinha dentro do pump, e o degrau em que ela desistiu não seria legível.
    final it = await _ateAConferida(
      tester,
      comEsta: SalaHarness(
        filaEmMemoria: true,
        retryBackoff: const [Duration(seconds: 30)],
      ),
    );
    it.harness.room.failReleaseWith = const RoomSlow();

    await _aprovarEEsperar(tester);

    expect(
      _estado(it.container).needsPerson,
      isFalse,
      reason:
          'uma sala lenta é uma sala que está lá: a escada trata disso e '
          'não chama ninguém na primeira',
    );
    expect(_estado(it.container).btPhase, BtPhase.conferida);
    expect(
      byLabel(_aprovar),
      findsOneWidget,
      reason: 'e o gesto continua na tela para a equipe apertar de novo',
    );

    // Contadas, não engolidas. A escada desiste na terceira demora, e é por chegar lá que
    // se sabe que a falha entrou nela: um erro que a aprovação simplesmente deixasse cair
    // também deixaria a sala sem pessoa e o botão de pé.
    await _aprovarEEsperar(tester);
    await _aprovarEEsperar(tester);

    expect(
      _estado(it.container).offline,
      isTrue,
      reason:
          'três demoras seguidas são a sala calada, que é o degrau em que '
          'a escada desiste e diz à equipe que não está conseguindo falar',
    );
    expect(
      it.harness.room.releasesAsked,
      hasLength(3),
      reason:
          'e cada pressão foi um pedido: a primeira falha não deixou '
          'tranca nenhuma para trás',
    );

    closeTheRoom(it.container);
  });

  testWidgets('uma sessão que sumiu volta para a roda, sem chamar uma pessoa', (
    tester,
  ) async {
    final it = await _ateAConferida(tester);
    it.harness.room.failReleaseWith = const SessionGone();

    await _aprovarEEsperar(tester);

    expect(
      _estado(it.container).stage,
      SalaStage.escolha,
      reason:
          'a sessão sumiu — a equipe volta para escolher de novo, como '
          'em qualquer outro ponto da conversa em que isso acontece',
    );
    expect(_estado(it.container).needsPerson, isFalse);

    closeTheRoom(it.container);
  });

  testWidgets(
    'sem rede a aprovação cai no offline e o botão volta com a sala',
    (tester) async {
      final it = await _ateAConferida(tester);
      it.harness.room.reachable = false;
      it.harness.network.reachable = false;

      await _aprovarEEsperar(tester);

      expect(
        _circulo(tester).voice,
        VoiceState.offline,
        reason:
            'a release é uma escrita da equipe como as outras, e a saída '
            'daqui é tocar no círculo: sem o desenho de sala sem rede não há '
            'nada que diga isso numa tela sem palavras',
      );
      expect(_circulo(tester).semanticLabel, 'Tocar para tentar de novo');
      expect(_estado(it.container).needsPerson, isFalse);

      it.harness.room.reachable = true;
      it.harness.network.reachable = true;
      _notifier(it.container).retryNow();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        byLabel(_aprovar),
        findsOneWidget,
        reason: 'e voltando a sala, o gesto está onde estava',
      );

      closeTheRoom(it.container);
    },
  );

  testWidgets('o botão de aprovar só existe em conferida', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true)
      ..room.verdictChecked = false
      ..room.verdictHasFinding = true
      ..room.verdictFindingSegmentId = 'trecho-1';
    final container = harness.container();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SalaApp()),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final sala = _notifier(container);
    await sala.goConversa(pericope: 'P01');
    await tester.pump(const Duration(milliseconds: 200));
    sala.goEnsaio();
    sala.ensaioTap();
    sala.ensaioTap();
    await tester.pump(const Duration(milliseconds: 100));
    sala.takeKeep();
    await letTheRehearsalReachTheRoom(tester);
    sala.startRetro();
    await tester.pump(const Duration(milliseconds: 200));

    Future<void> semAprovar(BtPhase esperada) async {
      expect(
        container.read(salaSessionProvider).btPhase,
        esperada,
        reason:
            'o caso tem de estar mesmo em $esperada para medir alguma '
            'coisa sobre $esperada',
      );
      expect(
        byLabel(_aprovar),
        findsNothing,
        reason:
            'aprovar antes de a sala conferir é a equipe assinando um '
            'rascunho que o analista ainda não leu',
      );
    }

    await semAprovar(BtPhase.playing);

    harness.playback.at = const Duration(seconds: 10);
    sala.cortarTrecho();
    sala.retroTap();
    await tester.pump(const Duration(milliseconds: 200));
    await semAprovar(BtPhase.capturing);

    harness.recorder.holdNextStop();
    sala.retroTap();
    await tester.pump(const Duration(milliseconds: 100));
    await semAprovar(BtPhase.thinking);
    harness.recorder.finishStop();
    await letTheRehearsalReachTheRoom(tester);
    await tester.pump(const Duration(milliseconds: 400));
    await sala.confirmarTraducao();
    await tester.pump(const Duration(milliseconds: 400));

    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 200));
    await sala.finishBackTranslation();
    await tester.pump(const Duration(milliseconds: 300));
    await semAprovar(BtPhase.findings);

    await tester.pumpWidget(const SizedBox.shrink());
    final conferida = await _ateAConferida(tester);

    expect(
      byLabel(_aprovar),
      findsOneWidget,
      reason:
          'e em conferida, uma: é a única fase em que a passagem está '
          'pronta para a equipe aprovar',
    );

    closeTheRoom(conferida.container);
  });

  testWidgets('uma gravação que não abre na última audição chama uma pessoa e '
      'deixa a equipe onde ela está', (tester) async {
    final it = await _ateAConferida(tester);

    await tester.tap(byLabel(_ouvir));
    await tester.pump(const Duration(milliseconds: 100));
    it.harness.playback.failPlayback();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      _estado(it.container).needsPerson,
      isTrue,
      reason: 'um arquivo que não abre é uma pessoa, como em toda outra tela',
    );
    expect(
      _estado(it.container).stage,
      SalaStage.retro,
      reason:
          'mas a equipe fica onde está: jogada no ensaio ela sai de uma '
          'passagem que o servidor já conferiu, e o gesto que sobra ali é '
          'gravar a passagem inteira de novo por cima do trabalho dela',
    );
    expect(
      _estado(it.container).btPhase,
      BtPhase.conferida,
      reason: 'e resolvido o halt a aprovação ainda é o que falta fazer',
    );
    expect(
      _estado(it.container).btClipRodando,
      isFalse,
      reason:
          'e a sala não pode ficar dizendo que toca o que não tocou: a '
          'equipe voltaria do halt a um glifo de pausa sobre o silêncio, e o '
          'primeiro toque seria gasto parando uma gravação que nunca começou',
    );

    closeTheRoom(it.container);
  });

  testWidgets('a passagem seguinte não herda a aprovação da anterior', (
    tester,
  ) async {
    final it = await _ateAConferida(
      tester,
      comEsta: SalaHarness(
        filaEmMemoria: true,
        fimLinger: const Duration(milliseconds: 40),
      ),
    );

    // A segunda passagem é uma que a equipe deixou conferida sem aprovar, que é o estado
    // que este ticket cria: ela tem de poder ser aprovada como a primeira. A linha é
    // escrita antes do fecho porque a roda lê quais passagens já foram começadas ao
    // reabrir, e o recomeço reabre a roda sozinho.
    it.harness.emAberto.rows['Ruth/P02'] = const ResumePoint(
      sessionId: 'sessao-da-p02',
      stage: SalaStage.retro,
    );

    await _aprovarEEsperar(tester);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      _estado(it.container).stage,
      SalaStage.escolha,
      reason:
          'a sala recomeça sozinha depois do fecho — se não recomeçar, '
          'este cenário não chega à segunda passagem',
    );
    expect(it.harness.room.releasesAsked, hasLength(1));

    it.harness.room.retroSoFar = const BackTranslationProgress(
      segments: [
        SegmentView(
          segmentId: 'trecho-p02',
          takeId: 'gravacao-p02',
          startsMs: 0,
          endsMs: 30000,
        ),
      ],
      checked: true,
    );
    await _notifier(it.container).goConversa(pericope: 'P02');
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      _estado(it.container).btPhase,
      BtPhase.conferida,
      reason: 'a segunda passagem pousa no mesmo gesto que falta',
    );

    await _aprovarEEsperar(tester);

    expect(
      it.harness.room.releasesAsked,
      hasLength(2),
      reason:
          'as travas da aprovação são coisa da passagem, não da sessão: '
          'herdadas, a segunda passagem encontra o gesto morto e a equipe '
          'aperta e não recebe nada — nem pedido, nem fala, nem pessoa',
    );

    closeTheRoom(it.container);
  });

  testWidgets('ouvir a gravação funciona depois de conferida', (tester) async {
    final it = await _ateAConferida(tester);
    final parte = _estado(it.container).partes.first.path;
    final tocadas = it.harness.playback.played.length;

    await tester.tap(byLabel(_ouvir));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      it.harness.playback.played.skip(tocadas),
      [parte],
      reason:
          'a última audição que a sala convida é esta: sem ela o botão '
          'de ouvir em conferida é um botão morto',
    );
    expect(
      it.harness.playback.playedFrom.last,
      Duration.zero,
      reason: 'e do começo, que é o que a fala pede — "do começo ao fim"',
    );
    expect(_estado(it.container).btClipRodando, isTrue);
    expect(
      _estado(it.container).btPhase,
      BtPhase.conferida,
      reason: 'ouvir não desfaz a conferência',
    );
    expect(
      byLabel(_aprovar),
      findsOneWidget,
      reason: 'e a aprovação segue ali, para quando a gravação acabar',
    );

    closeTheRoom(it.container);
  });

  test(
    'a recusa por parte não contada pousa a equipe nela, sem chamar ninguém',
    () async {
      final it = await _tresPartesAteAConferida();
      final segunda = it.partes[1];
      final falasAntes = it.harness.voice.assets.length;
      it.harness.room
        ..releaseBlockers = const ['telling_back_not_checked', 'untold_part']
        ..releaseUntoldTakeIds = [segunda.takeId!];

      await it.sala.aprovarRascunhoFinal();

      expect(
        it.estado.needsPerson,
        isFalse,
        reason:
            'há o que a equipe faça daqui: chamar uma pessoa para um '
            'buraco que a sala sabe tapar é parar a sala por nada',
      );
      expect(
        it.estado.btPhase,
        BtPhase.playing,
        reason: 'sair da conferida é o que devolve o toque à equipe',
      );
      expect(
        it.harness.playback.played.last,
        segunda.path,
        reason:
            'a equipe cai na parte que a recusa nomeou, e não na que o '
            'primeiro código da lista aponta: a ordem das portas é da sala, e '
            'esta recusa chega com a conferência na frente',
      );
      expect(
        it.harness.playback.playedFrom.last,
        Duration.zero,
        reason:
            'do começo da parte: não há nada contado sobre ela, e começar '
            'depois de um chão que não existe toca silêncio',
      );
      expect(
        it.harness.voice.assets.skip(falasAntes),
        isNot(contains(fixedLineAsset(approvedLine, testLanguage))),
        reason: 'nada foi aprovado, então a linha da aprovação não é dita',
      );
      expect(
        it.harness.finished.done,
        isNot(contains('Ruth/P01')),
        reason:
            'e a passagem não está feita: fechar o colar por cima de uma '
            'recusa tira a equipe de uma passagem que segue por aprovar',
      );
      expect(
        it.harness.emAberto.rows,
        contains('Ruth/P01'),
        reason: 'ela segue na roda, com a linha de retomada de pé',
      );

      final pedidos = it.harness.room.releasesAsked.length;
      await it.sala.aprovarRascunhoFinal();

      expect(
        it.harness.room.releasesAsked,
        hasLength(pedidos),
        reason:
            'e o gesto ficou para trás com a fase: daqui a equipe conta a '
            'parte e confere de novo, não aperta o mesmo botão outra vez',
      );
    },
  );

  test('a recusa por parte não ouvida pousa numa parte do meio e devolve o '
      'terminei no fim dela', () async {
    final it = await _tresPartesAteAConferida();
    final segunda = it.partes[1];
    it.harness.room
      ..releaseBlockers = const ['playback_did_not_cover_the_clip']
      ..releaseUnheardTakeIds = [segunda.takeId!];

    await it.sala.aprovarRascunhoFinal();

    expect(it.estado.needsPerson, isFalse);
    expect(it.estado.btPhase, BtPhase.playing);
    expect(
      it.harness.playback.played.last,
      segunda.path,
      reason: 'a equipe cai na parte que a recusa nomeou',
    );
    expect(
      it.harness.playback.playedFrom.last,
      Duration.zero,
      reason:
          'a recusa é sobre ouvir, não sobre contar: começar depois do '
          'chão já traduzido tocaria silêncio, o relato diria a parte '
          'inteira ouvida e a mesma aprovação seria recusada de novo',
    );

    it.harness.playback.finishPlayback();
    await waitFor('a parte do meio acabar', () => it.estado.btClipEnded);

    expect(
      it.estado.canFinishBackTranslation,
      isTrue,
      reason:
          'no fim de uma parte do meio o terminei volta aceso, que é a '
          'trava do pouso: sem ela a equipe fica numa parte que acabou, '
          'diante de um botão morto, sem nada para apertar',
    );
  });

  testWidgets('a recusa por trecho não contado lê os nomes de volta antes de '
      'levar a equipe', (tester) async {
    final it = await _ateAConferida(tester);

    expect(
      _estado(it.container).btTrechos.single.segmentId,
      isNull,
      reason:
          'uma passagem que chegou a conferida num veredito limpo '
          'carrega trechos que este tablet cortou e a sala nunca nomeou — se '
          'já viessem nomeados, o cenário não mediria a leitura de volta',
    );

    it.harness.room
      ..releaseBlockers = const ['untold_stretch']
      ..releaseUntoldSegmentId = 'trecho-1';

    await _aprovarEEsperar(tester);

    expect(
      _estado(it.container).needsPerson,
      isFalse,
      reason: 'o trecho existe e a sala sabe levar a equipe até ele',
    );
    expect(
      _estado(it.container).btTrechoTocando,
      isTrue,
      reason:
          'a sala toca a voz materna do trecho que falta, para a equipe '
          'saber qual é antes de contá-lo',
    );
    expect(
      it.harness.playback.ranges.last,
      '0-10000',
      reason:
          'nos limites do trecho nomeado: o nome só resolve contra a '
          'lista lida de volta, e sem ela a recusa acabaria numa pessoa',
    );

    closeTheRoom(it.container);
  });

  for (final codigo in const [
    'telling_back_not_checked',
    'telling_back_never_analysed',
  ]) {
    testWidgets('a recusa por $codigo devolve a fase de tocar com '
        'o terminei de pé', (tester) async {
      final it = await _ateAConferida(tester);
      await tester.tap(byLabel(_ouvir));
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        _estado(it.container).btClipEnded,
        isFalse,
        reason:
            'a última audição derruba o fim do clipe — é daqui que a porta '
            'tem de erguer o terminei, e não do estado limpo da conferida',
      );
      expect(
        it.harness.playback.sounding,
        isTrue,
        reason: 'com a gravação ainda na boca da sala',
      );

      it.harness.room.releaseBlockers = [codigo];

      await _aprovarEEsperar(tester);

      expect(_estado(it.container).needsPerson, isFalse);
      expect(_estado(it.container).btPhase, BtPhase.playing);
      expect(
        it.harness.playback.sounding,
        isFalse,
        reason: 'o gesto que move a sala a cala primeiro',
      );
      expect(
        _estado(it.container).canFinishBackTranslation,
        isTrue,
        reason:
            'a conferência é a errada da própria equipe: a sala devolve o '
            'terminei em vez de chamar alguém para apertá-lo',
      );

      final relatosAntes = it.harness.room.playedByTakeSent.length;
      await _notifier(it.container).finishBackTranslation();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        it.harness.room.playedByTakeSent,
        hasLength(relatosAntes + 1),
        reason: 'e um botão vivo é um botão que chega à sala',
      );

      closeTheRoom(it.container);
    });
  }

  testWidgets('um segundo aperto enquanto a recusa ainda desce não manda outro '
      'pedido', (tester) async {
    final it = await _ateAConferida(tester);
    it.harness.room
      ..releaseBlockers = const ['untold_stretch']
      ..releaseUntoldSegmentId = 'trecho-1'
      ..holdNextState();
    final trechosNoAr = it.harness.playback.ranges.length;

    await tester.tap(byLabel(_aprovar));
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      _estado(it.container).btPhase,
      BtPhase.conferida,
      reason:
          'a fase não se mexe enquanto a sala lê os nomes de volta — é o '
          'que mantém o botão desenhado, e por isso a trava do aperto tem de '
          'durar até a porta abrir',
    );

    await tester.tap(byLabel(_aprovar));
    await tester.pump(const Duration(milliseconds: 200));

    it.harness.room.finishHeldState();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      it.harness.room.releasesAsked,
      hasLength(1),
      reason:
          'um aperto, um pedido: o segundo manda a sala aprovar de novo '
          'uma passagem cuja recusa ainda está a caminho, e as duas '
          'aterragens disputam o clipe debaixo da equipe',
    );
    expect(
      it.harness.playback.ranges,
      hasLength(trechosNoAr + 1),
      reason: 'e a porta abre uma vez só',
    );

    closeTheRoom(it.container);
  });

  testWidgets('um código que este tablet não conhece é da pessoa', (
    tester,
  ) async {
    final it = await _ateAConferida(tester);
    it.harness.room.releaseBlockers = const ['something_new'];

    await _aprovarEEsperar(tester);

    expect(
      _estado(it.container).needsPerson,
      isTrue,
      reason:
          'um portão que aprendeu a recusar por um motivo novo não pode '
          'levar a equipe a uma porta escolhida no escuro',
    );
    expect(it.harness.room.personsAsked, 1);
    expect(_estado(it.container).btPhase, BtPhase.conferida);

    closeTheRoom(it.container);
  });

  testWidgets('um trecho não contado sem o trecho nomeado é da pessoa', (
    tester,
  ) async {
    final it = await _ateAConferida(tester);
    it.harness.room.releaseBlockers = const ['untold_stretch'];

    await _aprovarEEsperar(tester);

    expect(
      _estado(it.container).needsPerson,
      isTrue,
      reason:
          'o código diz que há um buraco e o chão dele não veio: não há '
          'a que levar a equipe, e adivinhar um trecho manda a equipe contar '
          'de novo o que já estava contado',
    );
    expect(_estado(it.container).btPhase, BtPhase.conferida);

    closeTheRoom(it.container);
  });

  testWidgets('uma parte não contada sem a gravação nomeada é da pessoa', (
    tester,
  ) async {
    final it = await _ateAConferida(tester);
    it.harness.room.releaseBlockers = const ['untold_part'];

    await _aprovarEEsperar(tester);

    expect(
      _estado(it.container).needsPerson,
      isTrue,
      reason:
          'pelo mesmo motivo do trecho: o buraco com chão sem chão não '
          'tem porta',
    );
    expect(_estado(it.container).btPhase, BtPhase.conferida);

    closeTheRoom(it.container);
  });

  testWidgets('uma resposta sem versão e sem buracos é da pessoa', (
    tester,
  ) async {
    final it = await _ateAConferida(tester);
    it.harness.room.release = const ApprovalAnswer();

    await _aprovarEEsperar(tester);

    expect(
      _estado(it.container).needsPerson,
      isTrue,
      reason:
          'nada foi cunhado e nada foi nomeado: é uma resposta que este '
          'tablet não conhece, e lê-la como aprovação fecharia a passagem '
          'por cima de nada',
    );
    expect(
      _estado(it.container).stage,
      SalaStage.retro,
      reason: 'o colar não fecha',
    );

    closeTheRoom(it.container);
  });

  for (final caso in const [
    (codigo: 'no_project', trecho: null),
    (codigo: 'untold_stretch', trecho: 'trecho-1'),
  ]) {
    testWidgets('uma recusa atrasada por ${caso.codigo} não muda nada', (
      tester,
    ) async {
      final it = await _ateAConferida(tester);
      it.harness.room
        ..releaseBlockers = [caso.codigo]
        ..releaseUntoldSegmentId = caso.trecho
        ..holdNextRelease();

      await tester.tap(byLabel(_aprovar));
      await tester.pump(const Duration(milliseconds: 100));
      _notifier(it.container).leaveThePassage();
      await tester.pump(const Duration(milliseconds: 300));
      final tocadas = it.harness.playback.played.length;

      it.harness.room.finishHeldRelease();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        _estado(it.container).stage,
        SalaStage.escolha,
        reason: 'a equipe saiu da passagem enquanto o pedido estava no ar',
      );
      expect(
        it.harness.playback.played,
        hasLength(tocadas),
        reason:
            'a resposta que chega depois é de uma pergunta que já não '
            'está de pé, e pôr uma parte no ar por causa dela tira a equipe '
            'da roda para dentro de uma passagem que ela deixou',
      );
      expect(
        _estado(it.container).needsPerson,
        isFalse,
        reason:
            'e nem para uma pessoa: a roda não tem passagem que parar, e '
            'a parada ficaria sobre a equipe seguinte até o balcão vir',
      );
      expect(
        it.harness.room.personsAsked,
        0,
        reason: 'ninguém é chamado a uma sala que ninguém parou',
      );

      closeTheRoom(it.container);
    });
  }

  test('nomeados três buracos, a equipe entra pela porta do trecho', () async {
    final it = await _tresPartesAteAConferida();
    final terceira = it.partes[2];
    it.harness.room
      ..releaseBlockers = const [
        'telling_back_not_checked',
        'untold_stretch',
        'playback_did_not_cover_the_clip',
      ]
      ..releaseUntoldSegmentId = 'trecho-1'
      ..releaseUnheardTakeIds = [terceira.takeId!];

    await it.sala.aprovarRascunhoFinal();

    expect(
      it.estado.btTrechoTocando,
      isTrue,
      reason:
          'a ordem das portas é da sala e não a ordem em que o portão '
          'levantou os códigos: o trecho vem antes de tudo',
    );
    expect(
      it.harness.playback.played.last,
      it.partes[0].path,
      reason:
          'o trecho-1 mora na primeira parte, e é nela que a equipe cai '
          '— não na terceira, que a recusa por ouvir nomeia',
    );
    expect(it.estado.needsPerson, isFalse);
  });

  test('recusada a conferência, a equipe confere de novo e a aprovação '
      'seguinte é um pedido novo', () async {
    final it = await _tresPartesAteAConferida();
    it.harness.room.releaseBlockers = const ['telling_back_not_checked'];

    await it.sala.aprovarRascunhoFinal();

    expect(
      it.estado.canFinishBackTranslation,
      isTrue,
      reason:
          'o cenário só mede alguma coisa se a porta devolver o '
          'terminei à equipe',
    );

    it.harness.room.releaseBlockers = const [];
    await pedirOVeredito(it);

    expect(
      it.estado.btPhase,
      BtPhase.conferida,
      reason:
          'e se a conferência refeita trouxer a passagem de volta ao '
          'gesto de aprovar',
    );

    await it.sala.aprovarRascunhoFinal();
    await waitFor(
      'a passagem fechar',
      () => it.harness.finished.done.contains('Ruth/P01'),
    );

    expect(
      it.harness.room.releasesAsked,
      hasLength(2),
      reason:
          'a recusa não gastou o aperto: nem a trava do pedido no ar '
          'nem a da release já dada ficam de pé depois dela, e a equipe que '
          'tapou o buraco tem de poder aprovar de verdade — com a primeira '
          'trava presa o botão fica morto, com a segunda a sala fala a '
          'linha e fecha o colar sobre uma release que nunca foi cunhada',
    );
  });

  test('nomeados o trecho e a parte não contada, a equipe entra pela porta do '
      'trecho', () async {
    final it = await _tresPartesAteAConferida();
    it.harness.room
      ..releaseBlockers = const ['untold_stretch', 'untold_part']
      ..releaseUntoldSegmentId = 'trecho-2'
      ..releaseUntoldTakeIds = [it.partes[0].takeId!];

    await it.sala.aprovarRascunhoFinal();

    expect(
      it.estado.btTrechoTocando,
      isTrue,
      reason: 'o trecho vem antes da parte na ordem da sala',
    );
    expect(
      it.harness.playback.played.last,
      it.partes[1].path,
      reason:
          'o trecho-2 mora na parte 2; pela porta da parte a equipe '
          'cairia na parte 1, que é a que a recusa nomeia por gravação',
    );
  });

  test('nomeadas a parte não contada e a não ouvida, a equipe entra pela porta '
      'da não contada', () async {
    final it = await _tresPartesAteAConferida();
    it.harness.room
      ..releaseBlockers = const [
        'untold_part',
        'playback_did_not_cover_the_clip',
      ]
      ..releaseUntoldTakeIds = [it.partes[0].takeId!]
      ..releaseUnheardTakeIds = [it.partes[2].takeId!];

    await it.sala.aprovarRascunhoFinal();

    expect(it.estado.btTrechoTocando, isFalse);
    expect(
      it.harness.playback.played.last,
      it.partes[0].path,
      reason:
          'a parte que ninguém contou vem antes da que ninguém ouviu: '
          'pela outra porta a equipe cairia na parte 3',
    );
    expect(
      it.harness.playback.playedFrom.last,
      Duration.zero,
      reason:
          'e do começo dela, que é o que a porta da parte não contada '
          'faz com o cursor',
    );
  });

  test(
    'um buraco sem porta ao lado de um com porta não chama ninguém',
    () async {
      final it = await _tresPartesAteAConferida();
      it.harness.room
        ..releaseBlockers = const ['no_telling_back', 'untold_part']
        ..releaseUntoldTakeIds = [it.partes[1].takeId!];

      await it.sala.aprovarRascunhoFinal();

      expect(
        it.estado.needsPerson,
        isFalse,
        reason:
            'a equipe tapa o buraco que dá para tapar: parar a sala '
            'porque um dos códigos não tem porta deixa parada uma passagem '
            'que a própria equipe destravaria',
      );
      expect(it.harness.playback.played.last, it.partes[1].path);
    },
  );

  testWidgets('uma sala que não responde a leitura dos nomes desce pela '
      'escada, e não vira uma parada', (tester) async {
    // A espera entre tentativas é longa de propósito, como na irmã desta: com a de sempre
    // a sala já teria voltado sozinha dentro do pump, e o degrau em que ela desistiu não
    // seria legível.
    final it = await _ateAConferida(
      tester,
      comEsta: SalaHarness(
        filaEmMemoria: true,
        retryBackoff: const [Duration(seconds: 30)],
      ),
    );
    it.harness.room
      ..releaseBlockers = const ['untold_stretch']
      ..releaseUntoldSegmentId = 'trecho-1'
      ..failStateOnceWith = const RoomSlow();

    await _aprovarEEsperar(tester);

    expect(
      _estado(it.container).needsPerson,
      isFalse,
      reason:
          'uma sala que não respondeu não é um buraco cujo chão não '
          'veio: o nome existe e a passagem tem para onde ir, e chamar uma '
          'pessoa põe uma parada que só o balcão levanta sobre uma falha '
          'que o próximo aperto resolve',
    );
    expect(it.harness.room.personsAsked, 0);
    expect(
      _estado(it.container).btPhase,
      BtPhase.conferida,
      reason: 'a fase não se move, que é o que mantém o botão desenhado',
    );
    expect(
      byLabel(_aprovar),
      findsOneWidget,
      reason: 'e o gesto continua ali para ser repetido',
    );

    // Contadas, não engolidas. A escada desiste na terceira demora, e é por chegar lá que
    // se sabe que a falha entrou nela: uma leitura que simplesmente deixasse a falha cair
    // também deixaria a sala sem pessoa e o botão de pé. A manivela é de um tiro só, então
    // cada aperto rearma a sua.
    it.harness.room.failStateOnceWith = const RoomSlow();
    await _aprovarEEsperar(tester);
    it.harness.room.failStateOnceWith = const RoomSlow();
    await _aprovarEEsperar(tester);

    expect(
      _estado(it.container).offline,
      isTrue,
      reason:
          'três demoras seguidas são a sala calada, que é o degrau em '
          'que a escada desiste e diz à equipe que não está conseguindo '
          'falar',
    );
    expect(
      it.harness.room.releasesAsked,
      hasLength(3),
      reason:
          'e cada pressão foi um pedido: a primeira falha não deixou '
          'tranca nenhuma para trás',
    );

    closeTheRoom(it.container);
  });

  testWidgets('a passage the room called checked is announced in english to an '
      'english room', (tester) async {
    final it = await _ateAConferida(
      tester,
      comEsta: SalaHarness(filaEmMemoria: true, lingua: 'en'),
    );

    expect(_estado(it.container).btPhase, BtPhase.conferida);
    expect(
      _circulo(tester).semanticLabel,
      'Translated',
      reason:
          'a passagem conferida era anunciada "Traduzida" a uma sala em '
          'inglês',
    );

    closeTheRoom(it.container);
  });

  testWidgets(
    'a retro that lost the network asks an english room to try again in '
    'english',
    (tester) async {
      final it = await _ateAConferida(
        tester,
        comEsta: SalaHarness(filaEmMemoria: true, lingua: 'en'),
      );
      it.harness.room.reachable = false;
      it.harness.network.reachable = false;

      await tester.tap(byLabel('Approve as the final draft'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(_circulo(tester).voice, VoiceState.offline);
      expect(
        _circulo(tester).semanticLabel,
        'Tap to try again',
        reason:
            'sem rede, o retro pedia "Tocar para tentar de novo" a uma sala '
            'em inglês',
      );

      closeTheRoom(it.container);
    },
  );

  testWidgets(
    'a retro that calls a person says so in english to an english room',
    (tester) async {
      final it = await _ateAConferida(
        tester,
        comEsta: SalaHarness(filaEmMemoria: true, lingua: 'en'),
      );
      it.harness.room.releaseBlockers = ['no_project'];

      await tester.tap(byLabel('Approve as the final draft'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(_circulo(tester).voice, VoiceState.needsPerson);
      expect(
        _circulo(tester).semanticLabel,
        'A moment for someone',
        reason:
            'o retro chamando uma pessoa dizia "Um momento para uma pessoa" '
            'a uma sala em inglês',
      );

      closeTheRoom(it.container);
    },
  );
}
