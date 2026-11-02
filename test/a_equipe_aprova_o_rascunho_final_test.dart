import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/approval_answer.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/halt.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/features/sala/presentation/widgets/way_back_button.dart';
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
  await sala.goConversa(book: 'Ruth', pericope: 'P01');
  await tester.pump(const Duration(milliseconds: 200));
  sala.goEnsaio();
  sala.gravarACena(1);
  sala.gravarACena(1);
  await tester.pump(const Duration(milliseconds: 100));
  sala.takeKeep();
  await theRoomNamesTheParts(tester, container, parts: 1);
  sala.startRetro();
  await tester.pump(const Duration(milliseconds: 200));

  harness.playback.at = const Duration(seconds: 10);
  sala.retroTap();
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

Future<void> _prontoEFora(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.tap(byLabel('Pronto'));
  await tester.pump(const Duration(milliseconds: 300));
  _notifier(container).leaveThePassage();
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _aprovarEEsperar(WidgetTester tester) async {
  await pressTheApproval(tester, _aprovar);
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets(
    'the retro opens on a part the room has named, not on one still in the air',
    (tester) async {
      final container = await _ateAConferida(
        tester,
        comEsta: SalaHarness(filaEmMemoria: true)
          ..room.takeLandsInRealTime = const Duration(milliseconds: 300),
      ).then((conferida) => conferida.container);

      expect(
        container.read(salaSessionProvider).partes.single.takeId,
        'gravacao-1',
        reason:
            'a parte entrava no retro antes de a sala dar o nome, e o '
            'trecho contado de volta não tinha de quem ser',
      );
    },
  );

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
        it.harness.emAberto.rows,
        contains('Ruth/P01/pt'),
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
    'aprovar manda a release com o aparelho, fala a linha P3 e só então mostra o ensaio salvo',
    (tester) async {
      final it = await _ateAConferida(tester);
      final sessao = _estado(it.container).sessionId;
      final falasAntes = it.harness.voice.fixedLines.length;

      it.harness.voice.holdNextLine();
      await pressTheApproval(tester, _aprovar);
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        it.harness.room.releasesAsked,
        [sessao],
        reason: 'um pedido, para a sessão desta passagem',
      );
      expect(
        it.harness.voice.fixedLines.skip(falasAntes),
        contains(('P3', testLanguage)),
        reason:
            'a linha da aprovação é a quarta das falas de processo da '
            'Marcia; tocada do pacote, falava do OBT Refine depois de ela mudar',
      );
      await tester.pump(const Duration(seconds: 2));

      expect(
        find.text('Ensaio salvo'),
        findsNothing,
        reason:
            'e a fala vem antes da tela do ensaio salvo: trocar a tela por '
            'cima dela tiraria a equipe da tradução no meio da frase que diz '
            'o que acabou de acontecer',
      );

      it.harness.voice.finishHeldLine();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text('Ensaio salvo'),
        findsOneWidget,
        reason: 'dita a linha, a tela do ensaio salvo vem',
      );
      expect(
        it.harness.emAberto.rows,
        contains('Ruth/P01/pt'),
        reason: 'e a passagem segue sendo o ponto de retomada',
      );

      closeTheRoom(it.container);
    },
  );

  testWidgets('apertar duas vezes fala uma vez e manda um pedido só', (
    tester,
  ) async {
    final it = await _ateAConferida(tester);
    final falasAntes = it.harness.voice.fixedLines.length;

    it.harness.room.holdNextRelease();
    await pressTheApproval(tester, _aprovar);
    await tester.pump(const Duration(milliseconds: 100));
    await pressTheApproval(tester, _aprovar);
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

    final ditas = it.harness.voice.fixedLines
        .skip(falasAntes)
        .where((line) => line == ('P3', testLanguage));
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
    'numa sessão em inglês a aprovação pede a P3 em inglês, nunca a portuguesa',
    (tester) async {
      final it = await _ateAConferida(
        tester,
        comEsta: SalaHarness(filaEmMemoria: true, lingua: 'en'),
      );
      final falasAntes = it.harness.voice.fixedLines.length;

      await pressTheApproval(tester, 'Approve as the final draft');
      await tester.pump(const Duration(milliseconds: 300));

      final ditas = it.harness.voice.fixedLines.skip(falasAntes).toList();
      expect(
        ditas,
        contains(('P3', 'en')),
        reason:
            'uma equipe que trabalha em inglês ouve a gêmea inglesa da linha '
            'da aprovação',
      );
      expect(
        ditas,
        isNot(contains(('P3', 'pt'))),
        reason: 'a frase portuguesa no meio de uma sessão em inglês',
      );

      closeTheRoom(it.container);
    },
  );

  testWidgets(
    'aprovar de novo depois de a release ter voltado não manda outra',
    (tester) async {
      final it = await _ateAConferida(tester);

      await _aprovarEEsperar(tester);
      expect(it.harness.room.releasesAsked, hasLength(1));
      expect(
        find.text('Ensaio salvo'),
        findsOneWidget,
        reason:
            'a segunda pressão é feita com a tela do ensaio salvo de pé, '
            'sobre a mesma tradução conferida',
      );

      _notifier(it.container).aprovarRascunhoFinal();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        it.harness.room.releasesAsked,
        hasLength(1),
        reason:
            'aprovada uma vez, aprovada: o gesto acabou e a tela do ensaio '
            'salvo é a resposta dele',
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
    testWidgets('a recusa por $codigo só escreve o motivo e deixa a '
        'conferida com o terminei, sem chamar ninguém', (tester) async {
      final it = await _ateAConferida(tester);
      final falasAntes = it.harness.voice.fixedLines.length;
      it.harness.room.releaseBlockers = [codigo];

      await _aprovarEEsperar(tester);

      expect(
        _circulo(tester).halt,
        isNot(isA<Blocking>()),
        reason:
            'uma recusa de um pedido que não é uma fala da equipe não é um '
            'dos seis casos do sinal da pessoa',
      );
      expect(_estado(it.container).needsPerson, isFalse);
      expect(it.harness.room.personsAsked, 0);
      expect(
        it.harness.voice.fixedLines.skip(falasAntes),
        isNot(contains(('P3', testLanguage))),
        reason: 'e nada foi aprovado, então a linha da aprovação não é dita',
      );
      expect(_estado(it.container).stage, SalaStage.retro);
      expect(_estado(it.container).canFinishBackTranslation, isTrue);
      expect(
        _estado(it.container).btPhase,
        BtPhase.conferida,
        reason:
            'a recusa devolvia a tradução para antes do terminei; a dela só '
            'escreve o motivo e deixa a conferida como estava',
      );
      expect(
        byLabel('terminei'),
        findsOneWidget,
        reason: 'a equipe segue com o terminei para conferir de novo',
      );

      closeTheRoom(it.container);
    });
  }

  testWidgets(
    'uma demora na aprovação não muda nada na sala e deixa o botão de pé',
    (tester) async {
      final it = await _ateAConferida(
        tester,
        comEsta: SalaHarness(
          filaEmMemoria: true,
          retryBackoff: const [Duration(seconds: 30)],
        ),
      );
      it.harness.room.failReleaseWith = const NetworkFailed('timeout');

      await _aprovarEEsperar(tester);

      expect(
        _estado(it.container).needsPerson,
        isFalse,
        reason: 'uma demora é a rede, e a rede sem fala não chama ninguém',
      );
      expect(_estado(it.container).btPhase, BtPhase.conferida);
      expect(
        byLabel(_aprovar),
        findsOneWidget,
        reason: 'e o gesto continua na tela para a equipe apertar de novo',
      );

      await tester.pump(const Duration(seconds: 40));

      expect(
        it.harness.room.releasesAsked,
        hasLength(1),
        reason: 'nada é mandado de novo sozinho',
      );

      closeTheRoom(it.container);
    },
  );

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
    'sem rede a aprovação não muda nada na sala e o botão fica de pé',
    (tester) async {
      final it = await _ateAConferida(tester);
      it.harness.room.reachable = false;

      await _aprovarEEsperar(tester);

      expect(_estado(it.container).needsPerson, isFalse);
      expect(byLabel(_aprovar), findsOneWidget);

      it.harness.room.reachable = true;
      await _aprovarEEsperar(tester);

      expect(
        it.harness.room.releasesAsked,
        hasLength(1),
        reason: 'é o aperto da equipe que pede de novo, e o pedido chega',
      );

      closeTheRoom(it.container);
    },
  );

  testWidgets('o botão de aprovar só existe em conferida', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true)
      ..room.verdictChecked = false
      ..room.verdictHasFinding = true
      ..room.verdictFindingSegmentId = 'trecho-1'
      ..room.takeLandsAfter = const Duration(milliseconds: 300);
    final container = harness.container();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SalaApp()),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final sala = _notifier(container);
    await sala.goConversa(book: 'Ruth', pericope: 'P01');
    await tester.pump(const Duration(milliseconds: 200));
    sala.goEnsaio();
    sala.gravarACena(1);
    sala.gravarACena(1);
    await tester.pump(const Duration(milliseconds: 100));
    sala.takeKeep();
    await theRoomNamesTheParts(tester, container, parts: 1);
    expect(
      container.read(salaSessionProvider).partes.single.takeId,
      'gravacao-1',
      reason:
          'a parte entrava no retro antes de a sala dar o nome, e o '
          'trecho contado de volta não tinha de quem ser',
    );
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
    sala.retroTap();
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
    await tester.pump(const Duration(milliseconds: 400));

    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 200));
    await sala.finishBackTranslation();
    await tester.pump(const Duration(milliseconds: 300));
    await semAprovar(BtPhase.playing);

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

  testWidgets('uma gravação que não abre na última audição não chama ninguém e '
      'deixa a equipe onde ela está', (tester) async {
    final it = await _ateAConferida(tester);

    await tester.tap(byLabel(_ouvir));
    await tester.pump(const Duration(milliseconds: 100));
    it.harness.playback.failPlayback();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      _estado(it.container).needsPerson,
      isFalse,
      reason: 'a primeira falha deixa o Canal em silêncio e não chama ninguém',
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
      reason: 'e a aprovação ainda é o que falta fazer',
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

  testWidgets(
    'the Choice after an approval marks the approved passage with its dot',
    (tester) async {
      final it = await _ateAConferida(
        tester,
        comEsta: SalaHarness(
          filaEmMemoria: true,
          fimLinger: const Duration(milliseconds: 40),
        ),
      );
      it.harness.room.passages = const [
        Passagem(
          pericope: 'P01',
          audioUrl: '/voice/p01',
          book: 'Ruth',
          reference: 'Ruth 1:1–5',
          approved: true,
        ),
        Passagem(
          pericope: 'P02',
          audioUrl: '/voice/p02',
          book: 'Ruth',
          reference: 'Ruth 1:6–14',
        ),
      ];

      await _aprovarEEsperar(tester);
      await _prontoEFora(tester, it.container);

      expect(_estado(it.container).stage, SalaStage.escolha);
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('Rute 1:1–5'),
            matching: find.byType(Row),
          ),
          matching: find.text('●'),
        ),
        findsOneWidget,
      );

      closeTheRoom(it.container);
    },
  );

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
    // escrita antes da saída porque a roda lê quais passagens já foram começadas ao
    // reabrir.
    final pasta = Directory.systemTemp.createTempSync('sala-p02');
    addTearDown(() => pasta.deleteSync(recursive: true));
    it.harness.emAberto.rows['Ruth/P02/${it.harness.lingua}'] = ResumePoint(
      sessionId: 'sessao-da-p02',
      stage: SalaStage.retro,
      takes: [
        KeptTake(
          scopeId: KeptScope.parte(1),
          path: (File(
            '${pasta.path}/p1.m4a',
          )..writeAsBytesSync([1, 2, 3])).path,
          takeId: 'gravacao-p02',
        ),
      ],
    );

    await _aprovarEEsperar(tester);
    await _prontoEFora(tester, it.container);

    expect(
      _estado(it.container).stage,
      SalaStage.escolha,
      reason:
          'a equipe sai pela saída da passagem depois do ensaio salvo — se '
          'não sair, este cenário não chega à segunda passagem',
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
    unawaited(
      _notifier(it.container).goConversa(book: 'Ruth', pericope: 'P02'),
    );
    await intoTheBackTranslation(
      _notifier(it.container),
      () => _estado(it.container),
      step: () => letTheRehearsalReachTheRoom(tester),
    );
    await waitFor(
      'a conferida voltar',
      () => _estado(it.container).btPhase == BtPhase.conferida,
      step: () => letTheRehearsalReachTheRoom(tester),
    );

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

  for (final codigo in const [
    'untold_part',
    'playback_did_not_cover_the_clip',
  ]) {
    test('a recusa por $codigo só escreve o motivo e deixa a conferida, '
        'não uma parte tocando', () async {
      final it = await _tresPartesAteAConferida();
      final falasAntes = it.harness.voice.fixedLines.length;
      it.harness.room.releaseBlockers = [codigo];

      await it.sala.aprovarRascunhoFinal();

      expect(it.estado.needsPerson, isFalse);
      expect(
        it.estado.btPhase,
        BtPhase.conferida,
        reason:
            'a recusa devolvia a tradução para antes do terminei; a dela só '
            'escreve o motivo e deixa a conferida como estava',
      );
      expect(
        it.estado.canFinishBackTranslation,
        isTrue,
        reason:
            'a recusa punha a parte nomeada no ar e o terminei só voltava no '
            'fim dela; a dela não toca nada, e o caminho para conferir de '
            'novo fica a um toque',
      );
      expect(
        it.harness.voice.fixedLines.skip(falasAntes),
        isNot(contains(('P3', testLanguage))),
        reason: 'nada foi aprovado, então a linha da aprovação não é dita',
      );
      expect(
        it.harness.emAberto.rows,
        contains('Ruth/P01/pt'),
        reason: 'ela segue na roda, com a linha de retomada de pé',
      );

      final pedidos = it.harness.room.releasesAsked.length;
      await it.sala.aprovarRascunhoFinal();

      expect(
        it.harness.room.releasesAsked,
        hasLength(pedidos + 1),
        reason:
            'o botão saía com a fase; o dela fica aceso, e um segundo aperto '
            'pergunta à sala de novo',
      );
    });
  }

  testWidgets('a recusa por trecho não contado deixa a equipe na conferida '
      'com o terminei, não no trecho que a sala nomeou', (tester) async {
    final it = await _ateAConferida(tester);

    expect(
      _estado(it.container).btTrechos.single.segmentId,
      'trecho-1',
      reason:
          'uma passagem que chegou a conferida num veredito limpo carregava '
          'trechos que a sala nunca nomeou, e nenhuma frase dela podia ser '
          'traduzida de novo',
    );

    it.harness.room.releaseBlockers = const ['untold_stretch'];

    await _aprovarEEsperar(tester);

    expect(_estado(it.container).needsPerson, isFalse);
    expect(
      _estado(it.container).btTrechoTocando,
      isFalse,
      reason:
          'a recusa punha no ar a voz materna do trecho nomeado; a dela não '
          'toca nada',
    );
    expect(_estado(it.container).canFinishBackTranslation, isTrue);
    expect(byLabel('terminei'), findsOneWidget);

    closeTheRoom(it.container);
  });

  for (final codigo in const [
    'untold_stretch',
    'untold_part',
    'playback_did_not_cover_the_clip',
    'telling_back_not_checked',
    'something_new',
  ]) {
    test('a refused approval naming $codigo says no line of the room\'s own, '
        'only writes why', () async {
      final it = await _tresPartesAteAConferida();
      it.harness.room.releaseBlockers = [codigo];
      final sons = it.harness.sounds.length;

      await it.sala.aprovarRascunhoFinal();
      await settle();

      expect(
        it.harness.sounds
            .skip(sons)
            .where((som) => som.startsWith('voice:') && som != 'voice:stop'),
        isEmpty,
        reason:
            'a dela não diz nada numa recusa: só o motivo fica escrito, e uma '
            'fala da sala ali seria o tablet falando por um servidor que não '
            'falou',
      );
    });
  }

  test('a refused approval naming a stretch reads nothing back from the room, '
      'not the names it would lead to', () async {
    final it = await _tresPartesAteAConferida();
    it.harness.room.releaseBlockers = const ['untold_stretch'];
    final leituras = it.harness.room.calls
        .where((call) => call == 'fetchState')
        .length;

    await it.sala.aprovarRascunhoFinal();

    expect(
      it.harness.room.calls.where((call) => call == 'fetchState'),
      hasLength(leituras),
      reason:
          'a recusa lia os nomes dos trechos de volta só para levar a equipe '
          'ao que nomeava; a dela não lê nada, e uma leitura que falhava '
          'virava a falha da aprovação',
    );
  });

  for (final codigo in const [
    'telling_back_not_checked',
    'telling_back_never_analysed',
  ]) {
    testWidgets('a recusa por $codigo deixa a conferida com o terminei '
        'de pé, mesmo cortando a última audição', (tester) async {
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
      expect(_estado(it.container).btPhase, BtPhase.conferida);
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

  testWidgets('um código que este tablet não conhece só escreve o motivo e '
      'deixa a conferida, sem chamar ninguém', (tester) async {
    final it = await _ateAConferida(tester);
    it.harness.room.releaseBlockers = const ['something_new'];

    await _aprovarEEsperar(tester);

    expect(
      _estado(it.container).needsPerson,
      isFalse,
      reason:
          'um portão que aprendeu a recusar por um motivo novo não leva a '
          'equipe a uma porta escolhida no escuro, e uma recusa da aprovação '
          'não é um dos seis casos do sinal',
    );
    expect(it.harness.room.personsAsked, 0);
    expect(_estado(it.container).canFinishBackTranslation, isTrue);
    expect(
      _estado(it.container).btPhase,
      BtPhase.conferida,
      reason:
          'a recusa devolvia a tradução para antes do terminei; a dela só '
          'escreve o motivo e deixa a conferida como estava',
    );
    expect(byLabel('terminei'), findsOneWidget);

    closeTheRoom(it.container);
  });

  testWidgets('um trecho não contado sem o trecho nomeado só escreve o motivo '
      'e deixa a conferida, sem chamar ninguém', (tester) async {
    final it = await _ateAConferida(tester);
    it.harness.room.releaseBlockers = const ['untold_stretch'];

    await _aprovarEEsperar(tester);

    expect(
      _estado(it.container).needsPerson,
      isFalse,
      reason:
          'o código diz que há um buraco e o chão dele não veio: não há a que '
          'levar a equipe, e adivinhar um trecho manda a equipe contar de '
          'novo o que já estava contado',
    );
    expect(it.harness.room.personsAsked, 0);
    expect(_estado(it.container).canFinishBackTranslation, isTrue);
    expect(
      _estado(it.container).btPhase,
      BtPhase.conferida,
      reason:
          'a recusa devolvia a tradução para antes do terminei; a dela só '
          'escreve o motivo e deixa a conferida como estava',
    );
    expect(byLabel('terminei'), findsOneWidget);

    closeTheRoom(it.container);
  });

  testWidgets('uma parte não contada sem a gravação nomeada só escreve o '
      'motivo e deixa a conferida, sem chamar ninguém', (tester) async {
    final it = await _ateAConferida(tester);
    it.harness.room.releaseBlockers = const ['untold_part'];

    await _aprovarEEsperar(tester);

    expect(
      _estado(it.container).needsPerson,
      isFalse,
      reason: 'pelo mesmo motivo do trecho: o buraco sem chão não tem porta',
    );
    expect(it.harness.room.personsAsked, 0);
    expect(_estado(it.container).canFinishBackTranslation, isTrue);
    expect(
      _estado(it.container).btPhase,
      BtPhase.conferida,
      reason:
          'a recusa devolvia a tradução para antes do terminei; a dela só '
          'escreve o motivo e deixa a conferida como estava',
    );
    expect(byLabel('terminei'), findsOneWidget);

    closeTheRoom(it.container);
  });

  testWidgets('uma resposta sem versão e sem buracos não fecha a passagem, '
      'deixa a conferida e não chama ninguém', (tester) async {
    final it = await _ateAConferida(tester);
    it.harness.room.release = const ApprovalAnswer();

    await _aprovarEEsperar(tester);

    expect(
      _estado(it.container).needsPerson,
      isFalse,
      reason: 'uma resposta que não é uma fala da equipe não traz o sinal',
    );
    expect(it.harness.room.personsAsked, 0);
    expect(
      _estado(it.container).stage,
      SalaStage.retro,
      reason:
          'nada foi cunhado e nada foi nomeado: lê-la como aprovação fecharia '
          'a passagem por cima de nada',
    );
    expect(_estado(it.container).canFinishBackTranslation, isTrue);
    expect(
      _estado(it.container).btPhase,
      BtPhase.conferida,
      reason:
          'a recusa devolvia a tradução para antes do terminei; a dela só '
          'escreve o motivo e deixa a conferida como estava',
    );

    closeTheRoom(it.container);
  });

  for (final codigo in const ['no_project', 'untold_stretch']) {
    testWidgets('uma recusa atrasada por $codigo não muda nada', (
      tester,
    ) async {
      final it = await _ateAConferida(tester);
      it.harness.room
        ..releaseBlockers = [codigo]
        ..holdNextRelease();

      await pressTheApproval(tester, _aprovar);
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

  test('nomeados três buracos, a recusa escreve o motivo do trecho, não o da '
      'parte não ouvida', () async {
    final it = await _tresPartesAteAConferida();
    it.harness.room.releaseBlockers = const [
      'telling_back_not_checked',
      'untold_stretch',
      'playback_did_not_cover_the_clip',
    ];

    await it.sala.aprovarRascunhoFinal();

    expect(
      it.estado.btRecusa,
      CheckRefusal.notConferida,
      reason:
          'a ordem das portas é da sala e não a ordem em que o portão '
          'levantou os códigos: o trecho vem antes da parte não ouvida',
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
    expect(
      it.estado.btPhase,
      BtPhase.conferida,
      reason:
          'a recusa devolvia a tradução para antes do terminei; a dela só '
          'escreve o motivo e deixa a conferida como estava',
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
      'a aprovação terminar no ensaio salvo',
      () => it.estado.ensaioSalvo != null,
    );

    expect(
      it.harness.room.releasesAsked,
      hasLength(2),
      reason:
          'a recusa não gastou o aperto: nem a trava do pedido no ar '
          'nem a da release já dada ficam de pé depois dela, e a equipe que '
          'tapou o buraco tem de poder aprovar de verdade — com a primeira '
          'trava presa o botão fica morto, com a segunda a sala fala a '
          'linha e salva o ensaio sobre uma release que nunca foi cunhada',
    );
  });

  test('nomeadas a parte não contada e a não ouvida, a recusa escreve o motivo '
      'da não contada', () async {
    final it = await _tresPartesAteAConferida();
    it.harness.room.releaseBlockers = const [
      'untold_part',
      'playback_did_not_cover_the_clip',
    ];

    await it.sala.aprovarRascunhoFinal();

    expect(
      it.estado.btRecusa,
      CheckRefusal.notConferida,
      reason:
          'a parte que ninguém contou vem antes da que ninguém ouviu: pela '
          'outra porta a equipe leria que falta ouvir',
    );
  });

  test(
    'um buraco sem porta ao lado de um com porta não chama ninguém',
    () async {
      final it = await _tresPartesAteAConferida();
      it.harness.room.releaseBlockers = const [
        'no_telling_back',
        'untold_part',
      ];

      await it.sala.aprovarRascunhoFinal();

      expect(
        it.estado.needsPerson,
        isFalse,
        reason:
            'a equipe tapa o buraco que dá para tapar: parar a sala '
            'porque um dos códigos não tem porta deixa parada uma passagem '
            'que a própria equipe destravaria',
      );
      expect(
        it.estado.btRecusa,
        CheckRefusal.notConferida,
        reason:
            'o código sem porta não apaga o que tem: a equipe lê o motivo '
            'que sabe tapar, e não o de tentar de novo',
      );
    },
  );

  testWidgets('a passage the room called checked is announced in english to an '
      'english room', (tester) async {
    final it = await _ateAConferida(
      tester,
      comEsta: SalaHarness(filaEmMemoria: true, lingua: 'en'),
    );

    expect(_estado(it.container).btPhase, BtPhase.conferida);
    expect(
      _circulo(tester).semanticLabel,
      'translated and checked',
      reason:
          'a passagem conferida era anunciada "Traduzida" a uma sala em '
          'inglês',
    );

    closeTheRoom(it.container);
  });

  testWidgets('a halt raised on the retro\'s checked screen draws no sign '
      'there, as hers', (tester) async {
    final it = await _ateAConferida(tester);

    _notifier(it.container).haltForABrokenBuild();
    await tester.pump(const Duration(milliseconds: 300));

    expect(_circulo(tester).halt, isA<NoHalt>());
    expect(
      thePersonSign,
      findsNothing,
      reason:
          'o sinal cobria a tela conferida, e o Drafting dela nunca o mostra',
    );

    closeTheRoom(it.container);
  });

  testWidgets(
    'a halt raised on the retro\'s checked screen leaves the way back standing',
    (tester) async {
      final it = await _ateAConferida(tester);
      double passageButton() => tester
          .widget<AnimatedOpacity>(
            find.descendant(
              of: find.byType(WayBackButton),
              matching: find.byType(AnimatedOpacity),
            ),
          )
          .opacity;
      expect(
        passageButton(),
        1,
        reason: 'na tela conferida, sem parada, a saída da passagem aparece',
      );

      _notifier(it.container).haltForABrokenBuild();
      await tester.pump(const Duration(milliseconds: 600));

      expect(
        passageButton(),
        1,
        reason: 'a parada escondia a saída da passagem na tela conferida',
      );
      closeTheRoom(it.container);
    },
  );
}
