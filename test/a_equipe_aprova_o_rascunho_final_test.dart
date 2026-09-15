import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';

const _aprovar = 'Aprovar como rascunho final';
const _ouvir = 'Ouvir a gravação';

FacilitatorCircle _circulo(WidgetTester tester) =>
    tester.widget<FacilitatorCircle>(find.byType(FacilitatorCircle));

Finder _byLabel(String label) => find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == label,
    );

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
  await tester.pump(const Duration(milliseconds: 200));
  sala.retroTap();
  await tester.pump(const Duration(milliseconds: 600));
  harness.playback.finishPlayback();
  await tester.pump(const Duration(milliseconds: 200));
  await sala.finishBackTranslation();
  await tester.pump(const Duration(milliseconds: 300));

  return _Conferida(harness, container);
}

Future<void> _aprovarEEsperar(WidgetTester tester) async {
  await tester.tap(_byLabel(_aprovar));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('o veredito limpo deixa a sala aberta com o botão de ouvir e o de aprovar',
      (tester) async {
    final it = await _ateAConferida(tester);

    expect(_estado(it.container).btPhase, BtPhase.conferida,
        reason: 'a sala deu a passagem por conferida — se não der, este cenário '
            'não chega ao que mede');
    expect(_byLabel(_ouvir), findsOneWidget,
        reason: 'a fala do veredito convida a equipe a ouvir a gravação mais '
            'uma vez, e o convite sem o gesto é uma tela sem saída');
    expect(_byLabel(_aprovar), findsOneWidget,
        reason: 'e a aprovação é o gesto que faltava: a passagem terminava '
            'sozinha, sem nada que registrasse que a equipe aprovou o que fez');

    await tester.pump(const Duration(seconds: 2));

    expect(_estado(it.container).stage, SalaStage.retro,
        reason: 'nenhum relógio fecha a sala: o fecho passou a ser coisa da '
            'aprovação, e 700ms depois da conferida a equipe era levada embora '
            'de uma tela que ela nunca chegou a tocar');
    expect(_estado(it.container).fimClosed, isFalse);
    expect(it.harness.finished.done, isNot(contains('Ruth/P01')),
        reason: 'uma passagem que a equipe ainda não aprovou não está feita');
    expect(it.harness.emAberto.rows, contains('Ruth/P01'),
        reason: 'e segue sendo ponto de retomada: fechar o app aqui tem de '
            'trazer a equipe de volta a este mesmo gesto');

    await tester.pump(it.harness.fimLinger + const Duration(seconds: 2));

    expect(_estado(it.container).stage, SalaStage.retro,
        reason: 'nem depois da demora do fim: não há corrente de relógios '
            'nenhuma pendurada na conferida');
  });

  testWidgets('aprovar manda a release com o aparelho, fala a linha P3 e só então fecha o colar',
      (tester) async {
    final it = await _ateAConferida(tester);
    final sessao = _estado(it.container).sessionId;
    final falasAntes = it.harness.voice.assets.length;

    it.harness.voice.holdNextLine();
    await tester.tap(_byLabel(_aprovar));
    await tester.pump(const Duration(milliseconds: 300));

    expect(it.harness.room.releasesAsked, [sessao],
        reason: 'um pedido, para a sessão desta passagem');
    expect(it.harness.voice.assets.skip(falasAntes),
        contains(fixedLineAsset(approvedLine, testLanguage)),
        reason: 'a linha da aprovação é a quarta das falas de processo da '
            'Marcia, tocada do pacote: a sala tem de poder dizê-la sem rede');
    // Passado o tempo inteiro que o fecho leva, com a fala ainda na boca da sala: o
    // colar fecha 700ms depois de ser mandado fechar, então medir logo após o toque diz
    // apenas que 700ms não passaram, e um fecho mandado antes da fala passaria por aqui.
    await tester.pump(const Duration(seconds: 2));

    expect(_estado(it.container).stage, SalaStage.retro,
        reason: 'e a fala vem antes do fecho: fechar por cima dela tiraria a '
            'equipe da tela no meio da frase que diz o que acabou de acontecer');

    it.harness.voice.finishHeldLine();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 700));

    expect(_estado(it.container).stage, SalaStage.fim,
        reason: 'dita a linha, o colar fecha como sempre fechou');

    await tester.pump(const Duration(seconds: 1));

    expect(_estado(it.container).fimClosed, isTrue);
    expect(it.harness.finished.done, contains('Ruth/P01'),
        reason: 'a passagem está feita porque a equipe a aprovou');
    expect(it.harness.emAberto.rows, isNot(contains('Ruth/P01')),
        reason: 'e não há mais a que voltar');

    closeTheRoom(it.container);
  });

  testWidgets('apertar duas vezes fala uma vez e manda um pedido só', (tester) async {
    final it = await _ateAConferida(tester);
    final falasAntes = it.harness.voice.assets.length;

    it.harness.room.holdNextRelease();
    await tester.tap(_byLabel(_aprovar));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(_byLabel(_aprovar));
    await tester.pump(const Duration(milliseconds: 100));

    expect(it.harness.room.releasesAsked, hasLength(1),
        reason: 'a segunda pressão cai num pedido que já está no ar: duas '
            'releases da mesma passagem é a equipe cunhando duas versões de um '
            'trabalho só');

    it.harness.room.finishHeldRelease();
    await tester.pump(const Duration(milliseconds: 300));

    final ditas = it.harness.voice.assets
        .skip(falasAntes)
        .where((asset) => asset == fixedLineAsset(approvedLine, testLanguage));
    expect(ditas, hasLength(1),
        reason: 'e uma fala só: a sala repetindo a linha da aprovação diz à '
            'equipe que aprovou duas vezes');
    expect(it.harness.room.releasesAsked, hasLength(1));

    closeTheRoom(it.container);
  });

  testWidgets('aprovar de novo depois de a release ter voltado não manda outra',
      (tester) async {
    final it = await _ateAConferida(tester);

    await _aprovarEEsperar(tester);
    expect(it.harness.room.releasesAsked, hasLength(1));
    expect(_estado(it.container).stage, SalaStage.retro,
        reason: 'a segunda pressão é feita antes de o colar fechar — depois do '
            'fecho seria a guarda de etapa a recusá-la, e não a da aprovação '
            'que já aconteceu');

    _notifier(it.container).aprovarRascunhoFinal();
    await tester.pump(const Duration(milliseconds: 300));

    expect(it.harness.room.releasesAsked, hasLength(1),
        reason: 'aprovada uma vez, aprovada: o gesto acabou e o fecho está a '
            'caminho');

    closeTheRoom(it.container);
  });

  testWidgets('uma recusa da release chama uma pessoa na hora', (tester) async {
    final it = await _ateAConferida(tester);
    final falasAntes = it.harness.voice.assets.length;
    it.harness.room.failReleaseWith = const ReleaseRefused();

    await _aprovarEEsperar(tester);

    expect(_circulo(tester).voice, VoiceState.needsPerson,
        reason: 'o círculo era a única coisa da tela que ainda podia dizer o '
            'que houve, e desenhá-lo verde por cima do halt dizia à equipe que '
            'estava tudo certo: dois botões que as guardas recusam, nenhum '
            'botão de sair, e a fala E0 como único sinal');
    expect(_circulo(tester).semanticLabel, 'Um momento para uma pessoa',
        reason: 'e a etiqueta acompanha, que é o que a sala tem no lugar de '
            'palavras na tela');

    expect(_estado(it.container).needsPerson, isTrue,
        reason: 'a recusa é um bloqueio que a equipe não resolve desta tela, '
            'então a sala chama alguém na primeira: pela escada comum ela só '
            'pararia na terceira, e a equipe apertaria um botão morto duas '
            'vezes antes disso');
    expect(it.harness.room.personsAsked, 1);
    expect(it.harness.voice.assets.skip(falasAntes),
        isNot(contains(fixedLineAsset(approvedLine, testLanguage))),
        reason: 'e nada foi aprovado, então a linha da aprovação não é dita');
    expect(_estado(it.container).stage, SalaStage.retro);
    expect(_estado(it.container).btPhase, BtPhase.conferida,
        reason: 'a fase não se move: é o que mantém a tela de pé debaixo da '
            'falha');

    closeTheRoom(it.container);
  });

  testWidgets('uma falha de rede passa pela escada e deixa o botão de pé',
      (tester) async {
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

    expect(_estado(it.container).needsPerson, isFalse,
        reason: 'uma sala lenta é uma sala que está lá: a escada trata disso e '
            'não chama ninguém na primeira');
    expect(_estado(it.container).btPhase, BtPhase.conferida);
    expect(_byLabel(_aprovar), findsOneWidget,
        reason: 'e o gesto continua na tela para a equipe apertar de novo');

    // Contadas, não engolidas. A escada desiste na terceira demora, e é por chegar lá que
    // se sabe que a falha entrou nela: um erro que a aprovação simplesmente deixasse cair
    // também deixaria a sala sem pessoa e o botão de pé.
    await _aprovarEEsperar(tester);
    await _aprovarEEsperar(tester);

    expect(_estado(it.container).offline, isTrue,
        reason: 'três demoras seguidas são a sala calada, que é o degrau em que '
            'a escada desiste e diz à equipe que não está conseguindo falar');
    expect(it.harness.room.releasesAsked, hasLength(3),
        reason: 'e cada pressão foi um pedido: a primeira falha não deixou '
            'tranca nenhuma para trás');

    closeTheRoom(it.container);
  });

  testWidgets('uma sessão que sumiu chama uma pessoa', (tester) async {
    final it = await _ateAConferida(tester);
    it.harness.room.failReleaseWith = const SessionGone();

    await _aprovarEEsperar(tester);

    expect(_estado(it.container).needsPerson, isTrue,
        reason: 'a passagem não tem mais para onde ir sozinha');

    closeTheRoom(it.container);
  });

  testWidgets('sem rede a aprovação cai no offline e o botão volta com a sala',
      (tester) async {
    final it = await _ateAConferida(tester);
    it.harness.room.reachable = false;
    it.harness.network.reachable = false;

    await _aprovarEEsperar(tester);

    expect(_circulo(tester).voice, VoiceState.offline,
        reason: 'a release é uma escrita da equipe como as outras, e a saída '
            'daqui é tocar no círculo: sem o desenho de sala sem rede não há '
            'nada que diga isso numa tela sem palavras');
    expect(_circulo(tester).semanticLabel, 'Tocar para tentar de novo');
    expect(_estado(it.container).needsPerson, isFalse);

    it.harness.room.reachable = true;
    it.harness.network.reachable = true;
    _notifier(it.container).retryNow();
    await tester.pump(const Duration(milliseconds: 300));

    expect(_byLabel(_aprovar), findsOneWidget,
        reason: 'e voltando a sala, o gesto está onde estava');

    closeTheRoom(it.container);
  });

  testWidgets('o botão de aprovar só existe em conferida', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true)
      ..room.verdictChecked = false
      ..room.verdictFinding = BtFindingKind.addition
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
      expect(container.read(salaSessionProvider).btPhase, esperada,
          reason: 'o caso tem de estar mesmo em $esperada para medir alguma '
              'coisa sobre $esperada');
      expect(_byLabel(_aprovar), findsNothing,
          reason: 'aprovar antes de a sala conferir é a equipe assinando um '
              'rascunho que o analista ainda não leu');
    }

    await semAprovar(BtPhase.playing);

    harness.playback.at = const Duration(seconds: 10);
    sala.cortarTrecho();
    await tester.pump(const Duration(milliseconds: 200));
    await semAprovar(BtPhase.capturing);

    harness.recorder.holdNextStop();
    sala.retroTap();
    await tester.pump(const Duration(milliseconds: 100));
    await semAprovar(BtPhase.thinking);
    harness.recorder.finishStop();
    await letTheRehearsalReachTheRoom(tester);
    await tester.pump(const Duration(milliseconds: 400));

    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 200));
    await sala.finishBackTranslation();
    await tester.pump(const Duration(milliseconds: 300));
    await semAprovar(BtPhase.findings);

    sala.regravarAVozMaterna();
    await tester.pump(const Duration(milliseconds: 200));
    await semAprovar(BtPhase.gravandoMaterna);

    await tester.pumpWidget(const SizedBox.shrink());
    final conferida = await _ateAConferida(tester);

    expect(_byLabel(_aprovar), findsOneWidget,
        reason: 'e em conferida, uma: é a única fase em que a passagem está '
            'pronta para a equipe aprovar');

    closeTheRoom(conferida.container);
  });

  testWidgets('uma gravação que não abre na última audição chama uma pessoa e '
      'deixa a equipe onde ela está', (tester) async {
    final it = await _ateAConferida(tester);

    await tester.tap(_byLabel(_ouvir));
    await tester.pump(const Duration(milliseconds: 100));
    it.harness.playback.failPlayback();
    await tester.pump(const Duration(milliseconds: 300));

    expect(_estado(it.container).needsPerson, isTrue,
        reason: 'um arquivo que não abre é uma pessoa, como em toda outra tela');
    expect(_estado(it.container).stage, SalaStage.retro,
        reason: 'mas a equipe fica onde está: jogada no ensaio ela sai de uma '
            'passagem que o servidor já conferiu, e o gesto que sobra ali é '
            'gravar a passagem inteira de novo por cima do trabalho dela');
    expect(_estado(it.container).btPhase, BtPhase.conferida,
        reason: 'e resolvido o halt a aprovação ainda é o que falta fazer');
    expect(_estado(it.container).btClipRodando, isFalse,
        reason: 'e a sala não pode ficar dizendo que toca o que não tocou: a '
            'equipe voltaria do halt a um glifo de pausa sobre o silêncio, e o '
            'primeiro toque seria gasto parando uma gravação que nunca começou');

    closeTheRoom(it.container);
  });

  testWidgets('a passagem seguinte não herda a aprovação da anterior',
      (tester) async {
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

    expect(_estado(it.container).stage, SalaStage.escolha,
        reason: 'a sala recomeça sozinha depois do fecho — se não recomeçar, '
            'este cenário não chega à segunda passagem');
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

    expect(_estado(it.container).btPhase, BtPhase.conferida,
        reason: 'a segunda passagem pousa no mesmo gesto que falta');

    await _aprovarEEsperar(tester);

    expect(it.harness.room.releasesAsked, hasLength(2),
        reason: 'as travas da aprovação são coisa da passagem, não da sessão: '
            'herdadas, a segunda passagem encontra o gesto morto e a equipe '
            'aperta e não recebe nada — nem pedido, nem fala, nem pessoa');

    closeTheRoom(it.container);
  });

  testWidgets('ouvir a gravação funciona depois de conferida', (tester) async {
    final it = await _ateAConferida(tester);
    final parte = _estado(it.container).partes.first.path;
    final tocadas = it.harness.playback.played.length;

    await tester.tap(_byLabel(_ouvir));
    await tester.pump(const Duration(milliseconds: 300));

    expect(it.harness.playback.played.skip(tocadas), [parte],
        reason: 'a última audição que a sala convida é esta: sem ela o botão '
            'de ouvir em conferida é um botão morto');
    expect(it.harness.playback.playedFrom.last, Duration.zero,
        reason: 'e do começo, que é o que a fala pede — "do começo ao fim"');
    expect(_estado(it.container).btClipRodando, isTrue);
    expect(_estado(it.container).btPhase, BtPhase.conferida,
        reason: 'ouvir não desfaz a conferência');
    expect(_byLabel(_aprovar), findsOneWidget,
        reason: 'e a aprovação segue ali, para quando a gravação acabar');

    closeTheRoom(it.container);
  });
}
