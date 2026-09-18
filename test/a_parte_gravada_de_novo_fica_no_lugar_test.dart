import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/onde_mora_grade.dart';
import 'package:internalization_room/features/sala/presentation/widgets/retro_cord.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'resto_da_historia_test.dart' as resto;
import 'um_ensaio_de_tres_partes.dart';

Finder byLabel(String label) => find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == label,
    );

const _aprovar = 'Aprovar como rascunho final';
const _ouvir = 'Ouvir a gravação';
const _sairDaPassagem = 'Deixar esta passagem e escolher outra';

/// A team standing on a finding the analyst addressed to the stretch of part 2, with the
/// three parts recorded, told back whole and nothing pressed yet.
Future<Sala> _oAchadoNaParteDois() async {
  final it = await umEnsaioDeTresPartesContadoInteiro();
  it.harness.room
    ..verdictChecked = false
    ..verdictFinding = BtFindingKind.missing
    ..verdictFindingPlace = 1;
  await pedirOVeredito(it);
  expect(it.estado.btPhase, BtPhase.findings,
      reason: 'o cenário só mede alguma coisa se a sala tiver mesmo devolvido '
          'um achado');
  expect(it.estado.btFindingTrecho?.parte, 1,
      reason: 'e se esse achado apontar a parte 2, que é a que a equipe grava '
          'de novo');
  return it;
}

/// Tell the rehearsal back again from the part just recorded, and stand on a finding the
/// analyst addresses to that same part — the way back to the microphone a second time.
Future<void> _oAchadoOutraVezNaParteDois(Sala it) async {
  // Antes do corte, e não depois: um trecho contado sobre uma parte que a sala ainda não
  // nomeou sobe pelo caminho sem nome e não entra no colar, e a espera abaixo mediria um
  // colar que nunca vai crescer.
  await waitFor(
    'a sala nomear a parte gravada de novo',
    () => it.partes[1].takeId != null,
  );
  it.harness.playback.lengths[it.partes[1].path] = partesDoEnsaio[1];
  it.sala.startRetro();
  await waitFor(
    'a tradução recomeçar na parte gravada de novo',
    () =>
        it.estado.stage == SalaStage.retro &&
        it.estado.btPhase == BtPhase.playing,
  );
  await ouvirETraduzirAParteInteira(it, partesDoEnsaio[1]);
  it.sala.proximaParte();
  await waitFor('a parte 3 entrar no ar', () => !it.estado.btParteFronteira);
  it.harness.playback.finishPlayback();
  await waitFor('a parte 3 acabar de tocar', () => it.estado.btClipEnded);
  it.harness.room.verdictFindingPlace = it.harness.room.segments.length - 1;
  await pedirOVeredito(it);
  expect(it.estado.btFindingTrecho?.parte, 1,
      reason: 'o cenário só mede alguma coisa se o achado voltar a apontar a '
          'parte 2');
}

/// Cut and tell one stretch of the part in the air, whether or not the room has named it:
/// a part with no name takes the nameless path and no stretch enters the cord.
Future<void> _contarUmTrecho(Sala it, Duration quanto) async {
  final antes = it.estado.btTrechos.length + it.estado.btChunkFailures.length;
  it.harness.playback.length = quanto;
  it.harness.playback.at = quanto;
  it.sala.cortarTrecho();
  await waitFor(
    'o microfone abrir no trecho',
    () => it.estado.btPhase == BtPhase.capturing,
  );
  it.sala.retroTap();
  await waitFor(
    'a sala responder pelo trecho',
    () =>
        it.estado.btTrechos.length + it.estado.btChunkFailures.length ==
        antes + 1,
  );
}

/// What the report the tablet sends says about each part, by the name the room gave it.
Map<String, List<List<int>>> _escutaRelatada(Sala it) => {
      for (final parte in it.harness.room.playedByTakeSent.last)
        parte['take_id']! as String:
            (parte['played_ranges']! as List).cast<List<int>>(),
    };

void main() {
  test('a parte dois gravada de novo fica no lugar da parte dois', () async {
    final it = await _oAchadoNaParteDois();
    final antes = it.partes;
    final enviadas = it.harness.room.takes.length;

    it.sala.gravarAParteDeNovo();
    await regravarAParte(it, 1);
    await waitFor(
      'a gravação nova chegar à sala',
      () => it.harness.room.takes.length > enviadas,
    );

    final agora = it.partes;
    expect(agora, hasLength(3),
        reason: 'gravar a parte 2 de novo é a parte 2 outra vez, não uma quarta');
    expect(agora[1].scopeId, KeptScope.parte(2));
    expect(agora[1].path, isNot(antes[1].path),
        reason: 'e é a gravação nova que ocupa o lugar');
    expect([agora[0].path, agora[0].takeId], [antes[0].path, antes[0].takeId],
        reason: 'as outras partes são trabalho da equipe que ninguém tocou');
    expect([agora[2].path, agora[2].takeId], [antes[2].path, antes[2].takeId]);

    expect(it.estado.takes, 3,
        reason: 'a conta do ensaio conta partes, e gravar a parte 2 de novo '
            'não dá ao ensaio uma quarta');

    final subiu = it.harness.room.takes.last;
    expect(subiu.scope, KeptScope.parte(2));
    expect(subiu.ordinal, 2,
        reason: 'a sala tem de receber a gravação sob o número que ela já tem, '
            'senão a parte 2 vira a parte 4 do lado de lá também');
    expect(it.harness.room.takePasses.last, 2,
        reason: 'a parte regravada sobe sob a passada seguinte à da gravação que '
            'ela substitui: sob a mesma, a sala só tem a ordem de chegada para '
            'escolher entre as duas, e a que a equipe abandonou pode chegar por último');
  });

  test('cada gravação da parte sobe sob a passada seguinte, e uma parte nova sob a '
      'primeira dela', () async {
    final it = await _oAchadoNaParteDois();
    expect(it.harness.room.takePasses, [1, 1, 1],
        reason: 'as três partes gravadas pela primeira vez são a primeira '
            'gravação de cada uma');

    it.sala.gravarAParteDeNovo();
    await regravarAParte(it, 1);
    await waitFor('a segunda gravação da parte 2 chegar à sala',
        () => it.harness.room.takePasses.length == 4);
    expect(it.harness.room.takePasses.last, 2);

    await _oAchadoOutraVezNaParteDois(it);
    it.sala.gravarAParteDeNovo();
    await regravarAParte(it, 1);
    await waitFor('a terceira gravação da parte 2 chegar à sala',
        () => it.harness.room.takePasses.length == 5);
    expect(it.harness.room.takePasses.last, 3,
        reason: 'a conta é da parte, e segue de onde a parte 2 parou');

    await gravarUmaParte(it);

    expect(it.harness.room.takesKept.last, 'ensaio/${KeptScope.parte(4)}');
    expect(it.harness.room.takePasses.last, 1,
        reason: 'uma parte gravada pela primeira vez é a primeira gravação dela, '
            'seja qual for a conta das outras partes');
  });

  test('a linha do lugar guarda a gravação em que cada parte está', () async {
    final it = await _oAchadoNaParteDois();

    it.sala.gravarAParteDeNovo();
    await regravarAParte(it, 1);
    await waitFor('o lugar da equipe ser escrito com o arquivo novo', () {
      final ponto = it.harness.emAberto.rows['Ruth/P01'];
      return ponto != null &&
          ponto.takes.length == 3 &&
          ponto.takes[1].path == it.partes[1].path;
    });

    expect(
      [for (final take in it.harness.emAberto.rows['Ruth/P01']!.takes) take.pass],
      [1, 2, 1],
      reason: 'a retomada precisa saber em que gravação de cada parte a equipe '
          'parou: sem isso a próxima regravação sobe sob uma passada que a sala '
          'já tem',
    );
  });

  test('a parte cuja linha pousa depois aprende o nome, e o trecho seguinte sobe '
      'nomeado', () async {
    final it = await _oAchadoNaParteDois();
    it.harness.room.refuseTake = 'ensaio/${KeptScope.parte(2)}';

    it.sala.gravarAParteDeNovo();
    await regravarAParte(it, 1);
    await waitFor(
      'a sala recusar a gravação nova',
      () => it.harness.room.calls.where((c) => c == 'sendTake').length > 3,
    );
    expect(it.partes[1].takeId, isNull,
        reason: 'a sala recusou, e a tomada não tem nome nenhum para adotar');

    it.harness.room.refuseTake = null;
    it.harness.playback.lengths[it.partes[1].path] = partesDoEnsaio[1];
    it.sala.startRetro();
    await waitFor(
      'a tradução recomeçar na parte gravada de novo',
      () =>
          it.estado.stage == SalaStage.retro &&
          it.estado.btPhase == BtPhase.playing,
    );
    await _contarUmTrecho(it, partesDoEnsaio[1]);
    expect(it.estado.btChunkFailures, hasLength(1),
        reason: 'o cenário é o do trecho contado sobre uma parte que a sala '
            'ainda não nomeou, que é o caminho sem nome');

    await waitFor(
      'a parte aprender o nome quando a linha dela pousa',
      () => it.partes[1].takeId != null,
    );
    expect(
      it.partes[1].takeId,
      it.harness.room.takes
          .lastWhere((take) =>
              take.kind == 'ensaio' && take.scope == KeptScope.parte(2))
          .takeId,
      reason: 'o nome é o que a sala deu a esta gravação da parte 2, e não o da '
          'retro sem nome que subiu no mesmo flush',
    );

    await _contarUmTrecho(it, partesDoEnsaio[1]);

    expect(it.harness.room.chunkTakes.last, it.partes[1].takeId,
        reason: 'sem readotar o nome, todo trecho contado sobre esta parte '
            'subiria como uma retro da passagem inteira, e a sala nunca a '
            'guardaria como trecho da parte 2');
  });

  test('a parte nova ganha o nome do servidor e nunca o da antiga', () async {
    final it = await _oAchadoNaParteDois();
    final antiga = it.partes[1].takeId;

    it.sala.gravarAParteDeNovo();
    await regravarAParte(it, 1);
    await waitFor('a sala nomear a parte nova', () => it.partes[1].takeId != null);

    expect(it.partes[1].takeId, it.harness.room.takeIds.last,
        reason: 'o nome que chega é o que a sala acabou de dar a este arquivo');
    expect(it.partes[1].takeId, isNot(antiga),
        reason: 'herdar o nome da antiga é mandar os trechos novos para a '
            'gravação que ninguém vai ouvir de novo');
    final nomes = [for (final take in it.estado.keptTakes) take.takeId];
    expect(nomes.toSet(), hasLength(nomes.length),
        reason: 'duas tomadas guardadas nunca dividem um nome');
  });

  test('o nome só pousa na parte nova, e só quando a sala responde por ela',
      () async {
    final it = await _oAchadoNaParteDois();
    final antes = [for (final parte in it.partes) parte.takeId];

    it.harness.room.holdNextTake(KeptScope.parte(2));
    it.sala.gravarAParteDeNovo();
    await regravarAParte(it, 1);
    await it.harness.room.untilTakeHeld();

    expect(it.partes[1].takeId, isNull,
        reason: 'enquanto a sala não responde, a parte nova não tem nome — e o '
            'da antiga não serve');
    expect([it.partes[0].takeId, it.partes[2].takeId], [antes[0], antes[2]]);

    it.harness.room.finishHeldTake();
    await waitFor('o nome novo pousar', () => it.partes[1].takeId != null);

    expect(it.partes[1].takeId, isNot(antes[1]));
    expect([it.partes[0].takeId, it.partes[2].takeId], [antes[0], antes[2]],
        reason: 'e pousa só nela');
  });

  test('os trechos das partes um e três ficam e os da parte dois saem',
      () async {
    final it = await _oAchadoNaParteDois();
    final antes = it.estado.btTrechos;
    final passes = it.estado.btChunkPasses;
    expect(antes, hasLength(3));

    it.sala.gravarAParteDeNovo();
    await regravarAParte(it, 1);

    final agora = it.estado.btTrechos;
    expect([for (final trecho in agora) trecho.parte], isNot(contains(1)),
        reason: 'o que foi contado sobre a gravação antiga não conta sobre a nova');
    expect(
      [for (final trecho in agora) trecho.segmentId],
      [antes[0].segmentId, antes[2].segmentId],
      reason: 'e os trechos das outras partes seguem sendo os mesmos trechos',
    );
    expect(
      [for (final trecho in agora) [trecho.lugarFrom, trecho.lugarTo]],
      [
        [antes[0].lugarFrom, antes[0].lugarTo],
        [antes[2].lugarFrom, antes[2].lugarTo],
      ],
      reason: 'cada um no lugar que sempre ocupou',
    );
    expect(it.estado.btChunkPasses, [passes[0], passes[2]],
        reason: 'a lista que anda ao lado dos trechos anda com eles');
  });

  test('a escuta das partes um e três sobrevive e a nova começa do zero',
      () async {
    final it = await _oAchadoNaParteDois();
    final antiga = it.partes[1].takeId;

    it.sala.gravarAParteDeNovo();
    await regravarAParte(it, 1);
    await waitFor('a sala nomear a parte nova', () => it.partes[1].takeId != null);
    final nomes = [for (final parte in it.partes) parte.takeId!];

    it.sala.startRetro();
    await waitFor(
      'a tradução voltar a tocar a parte 2',
      () => it.harness.playback.played.last == it.partes[1].path,
    );
    await ouvirETraduzirAParteInteira(it, partesDoEnsaio[1]);
    it.sala.proximaParte();
    await waitFor('a parte 3 entrar no ar', () => !it.estado.btParteFronteira);
    it.harness.playback.length = partesDoEnsaio[2];
    it.harness.playback.at = partesDoEnsaio[2];
    it.harness.playback.finishPlayback();
    await waitFor('a parte 3 terminar', () => it.estado.btClipEnded);
    await pedirOVeredito(it);

    final relato = _escutaRelatada(it);
    expect(relato.keys, containsAll(nomes),
        reason: 'as três partes do ensaio, uma entrada cada, sob o nome que '
            'cada uma tem agora');
    expect(relato.keys, isNot(contains(antiga)),
        reason: 'a gravação que a parte 2 deixou de ser não é evidência de nada');
    expect(
      [for (final nome in nomes) resto.ouvidoAteMs(relato[nome]!)],
      [
        partesDoEnsaio[0].inMilliseconds,
        partesDoEnsaio[1].inMilliseconds,
        partesDoEnsaio[2].inMilliseconds,
      ],
      reason: 'cada parte coberta do seu próprio zero ao seu próprio fim',
    );
  });

  test('a próxima tradução começa na parte gravada de novo', () async {
    final it = await _oAchadoNaParteDois();

    it.sala.gravarAParteDeNovo();
    await regravarAParte(it, 1);
    final nova = it.partes[1].path;
    final tocadas = it.harness.playback.played.length;

    it.sala.startRetro();
    await waitFor(
      'a tradução recomeçar',
      () => it.harness.playback.played.length > tocadas,
    );

    expect(it.harness.playback.played.last, nova,
        reason: 'o chão da parte 2 está por contar outra vez; a parte 1 está '
            'contada e a sala passa por cima dela');
  });

  test('a retomada traz as três partes na ordem, com o arquivo novo', () async {
    final it = await _oAchadoNaParteDois();
    final antes = it.partes;

    it.sala.gravarAParteDeNovo();
    await regravarAParte(it, 1);
    await waitFor('a sala nomear a parte nova', () => it.partes[1].takeId != null);
    final nova = it.partes[1];

    await waitFor('o lugar da equipe ser escrito', () {
      final ponto = it.harness.emAberto.rows['Ruth/P01'];
      return ponto != null &&
          ponto.takes.length == 3 &&
          ponto.takes[1].path == nova.path;
    });
    final ponto = it.harness.emAberto.rows['Ruth/P01']!;
    expect([for (final take in ponto.takes) take.scopeId],
        [KeptScope.parte(1), KeptScope.parte(2), KeptScope.parte(3)]);
    expect([for (final take in ponto.takes) take.path],
        [antes[0].path, nova.path, antes[2].path]);

    it.container.dispose();
    it.container = it.harness.container();
    addTearDown(it.container.dispose);
    await it.sala.abrirEscolha();
    await waitFor(
      'a roda dizer que esta passagem tem trabalho parado',
      () => it.estado.comecadas.contains('P01'),
    );
    await it.sala.goConversa(pericope: 'P01');
    await waitFor('a equipe voltar ao ensaio',
        () => it.estado.stage == SalaStage.ensaio);

    expect([for (final parte in it.partes) parte.path],
        [antes[0].path, nova.path, antes[2].path],
        reason: 'reabrir a passagem devolve as três partes na ordem, com a '
            'gravação nova no lugar da parte 2');
  });

  test('uma falta sem endereço continua acrescentando no fim', () async {
    final it = await umEnsaioDeTresPartesContadoInteiro();
    it.harness.room
      ..verdictChecked = false
      ..verdictFinding = BtFindingKind.missing
      ..verdictFindingSegmentId = null;
    await pedirOVeredito(it);
    expect(it.estado.btFindingTrecho, isNull);

    it.sala.continuarOEnsaio();
    await gravarUmaParte(it);

    expect(it.partes, hasLength(4),
        reason: 'a falta que não cabe em trecho nenhum é o fim da história que '
            'ninguém gravou: a tomada nova acrescenta-se');
    expect(it.partes.last.scopeId, KeptScope.parte(4));
  });

  test('descartar e gravar de novo ainda troca a parte dois', () async {
    final it = await _oAchadoNaParteDois();
    final antes = it.partes;

    it.sala.gravarAParteDeNovo();
    it.sala.ensaioTap();
    await waitFor('a gravação começar',
        () => it.estado.ensaio == EnsaioStatus.recording);
    it.sala.ensaioTap();
    await waitFor('a gravação terminar',
        () => it.estado.ensaio == EnsaioStatus.recorded);
    it.sala.takeRedo();
    await waitFor('o círculo ficar livre',
        () => it.estado.ensaio == EnsaioStatus.idle);

    await regravarAParte(it, 1);

    expect(it.partes, hasLength(3),
        reason: 'jogar fora uma tomada e gravar outra é a mesma gravação outra '
            'vez; a sala não pode esquecer qual parte a equipe veio refazer');
    expect(it.partes[1].scopeId, KeptScope.parte(2));
    expect(it.partes[1].path, isNot(antes[1].path));
  });

  test('depois da troca, guardar outra vez volta a acrescentar', () async {
    final it = await _oAchadoNaParteDois();

    it.sala.gravarAParteDeNovo();
    await regravarAParte(it, 1);
    await gravarUmaParte(it);

    expect(it.partes, hasLength(4),
        reason: 'a parte que a equipe veio refazer gasta-se no guardar: a '
            'gravação seguinte é uma parte nova, não a parte 2 outra vez');
    expect(it.partes.last.scopeId, KeptScope.parte(4));
    expect(it.estado.takes, 4);
  });

  test('sair do ensaio sem gravar solta a parte que a equipe veio refazer',
      () async {
    final it = await _oAchadoNaParteDois();
    final antes = it.partes;

    it.sala.gravarAParteDeNovo();
    it.sala.startRetro();
    await waitFor('a tradução voltar ao ar',
        () => it.estado.stage == SalaStage.retro);
    it.harness.room
      ..verdictChecked = false
      ..verdictFinding = BtFindingKind.missing
      ..verdictFindingSegmentId = null
      ..verdictFindingPlace = null;
    await pedirOVeredito(it);
    it.sala.continuarOEnsaio();
    await gravarUmaParte(it);

    expect(it.partes, hasLength(4),
        reason: 'a equipe mudou de ideia e foi traduzir: a parte que ela vinha '
            'refazer deixou de ser a parte que a próxima gravação ocupa');
    expect([for (final parte in it.partes) parte.path].sublist(0, 3),
        [for (final parte in antes) parte.path]);
  });

  test('um achado sobre gravação que o tablet não tem chama uma pessoa',
      () async {
    final harness = SalaHarness();
    final home = Directory.systemTemp.createTempSync('sala-parte-fantasma');
    addTearDown(() => home.deleteSync(recursive: true));
    final gravadas = [
      for (var parte = 1; parte <= 1; parte++)
        KeptTake(
          scopeId: KeptScope.parte(parte),
          path: (File('${home.path}/p$parte.m4a')..writeAsBytesSync([1, 2, 3]))
              .path,
          takeId: 'antiga-$parte',
        ),
    ];
    await harness.emAberto.remember(
      'Ruth',
      'P01',
      ResumePoint(
        sessionId: 'sessao-antiga',
        stage: SalaStage.retro,
        takes: gravadas,
      ),
    );
    // A stretch on a recording this tablet is not holding: the room keeps it, and the
    // tablet can say which part it sits in for none of them.
    harness.room
      ..retroSoFar = const BackTranslationProgress(segments: [
        SegmentView(
          segmentId: 'trecho-fantasma',
          takeId: 'gravacao-que-nao-esta-aqui',
          startsMs: 0,
          endsMs: 9000,
        ),
      ])
      ..verdictChecked = false
      ..verdictFinding = BtFindingKind.missing
      ..verdictFindingSegmentId = 'trecho-fantasma';
    harness.playback.length = resto.umaParteInteira;
    final container = harness.container();
    addTearDown(container.dispose);
    final it = Sala(harness, container);
    await it.sala.abrirEscolha();
    await waitFor('a roda dizer que há trabalho parado',
        () => it.estado.comecadas.contains('P01'));
    await it.sala.goConversa(pericope: 'P01');
    await waitFor('a tradução ser retomada',
        () => it.estado.stage == SalaStage.retro);
    harness.playback.finishPlayback();
    await waitFor('o ensaio acabar de tocar', () => it.estado.btClipEnded);
    await pedirOVeredito(it);
    expect(it.estado.btFindingTrecho?.parte, -1,
        reason: 'o cenário é justamente o do achado que não cai em parte '
            'nenhuma deste tablet');
    final enviadas = List.of(it.harness.room.takesKept);

    it.sala.gravarAParteDeNovo();
    await resto.settle();

    expect(it.estado.needsPerson, isTrue,
        reason: 'não há parte que gravar de novo, e não há como dizer isso sem '
            'palavras: o microfone que não leva a lado nenhum é um botão morto');
    expect(it.estado.stage, SalaStage.retro,
        reason: 'e a equipe fica onde está, e não no ensaio à espera de gravar '
            'uma parte que a sala não vai saber onde pôr');

    it.sala.ensaioTap();
    await resto.settle();
    expect(it.harness.room.takesKept, enviadas,
        reason: 'nada pode subir sob parte-0: a sala guardaria uma gravação '
            'que não é parte de ensaio nenhum');
  });

  testWidgets('o microfone da grade grava a parte de novo', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container =
        await resto.aHistoriaSemOFim(tester, harness, ondeFalta: 'trecho-2');
    final fases = <BtPhase>[];
    container.listen(
      salaSessionProvider,
      (_, agora) => fases.add(agora.btPhase),
      fireImmediately: true,
    );
    final antes = container.read(salaSessionProvider).partes;
    expect(antes, hasLength(3));

    await tester.tap(byLabel(micParteLabel));
    await tester.pump(const Duration(milliseconds: 400));

    expect(container.read(salaSessionProvider).stage, SalaStage.ensaio,
        reason: 'o microfone de madeira leva ao ensaio, onde a parte se grava');
    expect(
      [
        for (var onde = 0; onde < fases.length; onde++)
          if (onde == 0 || fases[onde] != fases[onde - 1]) fases[onde],
      ],
      [BtPhase.findings, BtPhase.playing],
      reason: 'do achado ao ensaio num gesto: o microfone de madeira não '
          'passa por posto nenhum pelo caminho',
    );

    await resto.gravarUmaParte(tester, container.read(salaSessionProvider.notifier));

    final agora = container.read(salaSessionProvider).partes;
    expect(agora, hasLength(3));
    expect(agora[1].path, isNot(antes[1].path));
    expect([agora[0].path, agora[2].path], [antes[0].path, antes[2].path]);
  });

  testWidgets('o colar mostra chão nu sobre a parte dois', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container =
        await resto.aHistoriaSemOFim(tester, harness, ondeFalta: 'trecho-2');
    final notifier = container.read(salaSessionProvider.notifier);
    for (final parte in container.read(salaSessionProvider).partes) {
      harness.playback.lengths[parte.path] = resto.umaParteInteira;
    }
    harness.playback.measured = const Duration(seconds: 12);

    await tester.tap(byLabel(micParteLabel));
    await tester.pump(const Duration(milliseconds: 400));
    await resto.gravarUmaParte(tester, notifier);

    expect(container.read(salaSessionProvider).btFimDasPartesMs,
        [30000, 42000, 72000],
        reason: 'a régua é onde cada parte acaba ao longo do cordão: a parte 2 '
            'é um arquivo do seu próprio tamanho, e desenhada com o da que ela '
            'substituiu o cordão fala de um ensaio que não existe mais');

    notifier.startRetro();
    await tester.pump(const Duration(milliseconds: 400));

    final cord = tester.widget<RetroCord>(find.byType(RetroCord));
    expect(cord.partes, 3, reason: 'o ensaio continua tendo três partes');
    expect([for (final trecho in cord.trechos) trecho.parte], isNot(contains(1)),
        reason: 'nenhuma faixa sobre a parte 2: o chão dela está por contar');
    expect(cord.apontado, isNull,
        reason: 'e nenhuma faixa vazia: vazia quer dizer à espera de conserto, '
            'e este chão não espera conserto nenhum, espera ser contado');

    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('a saída da passagem não fica ocupada em conferida sob parada',
      (tester) async {
    final it = await _ateAConferida(tester);
    it.harness.room.failReleaseWith = const ReleaseRefused();

    await tester.tap(byLabel(_aprovar));
    await tester.pump(const Duration(milliseconds: 400));

    expect(_estado(it.container).needsPerson, isTrue,
        reason: 'uma soltura recusada chama uma pessoa — se não chamar, não há '
            'parada que medir');
    expect(byLabel(_sairDaPassagem), findsOneWidget);
    expect(
      tester
          .widget<IgnorePointer>(find
              .ancestor(
                of: byLabel(_sairDaPassagem),
                matching: find.byType(IgnorePointer),
              )
              .first)
          .ignoring,
      isFalse,
      reason: 'nenhuma estação é beco sem saída: estar na árvore não é estar '
          'viva — apagada e surda, a saída é a mesma que não existir',
    );

    await tester.tap(byLabel(_sairDaPassagem));
    await tester.pump(const Duration(milliseconds: 400));

    expect(_estado(it.container).stage, SalaStage.escolha,
        reason: 'e o toque tem de valer, não ser engolido por um botão inerte');
  });

  testWidgets('sem gravação no tablet a conferida não oferece o ouvir',
      (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    harness.room.retroSoFar = const BackTranslationProgress(
      segments: [
        SegmentView(
          segmentId: 'trecho-retomado',
          takeId: 'gravacao-retomada',
          startsMs: 0,
          endsMs: 30000,
        ),
      ],
      checked: true,
    );
    harness.emAberto.rows['Ruth/P01'] = const ResumePoint(
      sessionId: 'sessao-de-ontem',
      stage: SalaStage.retro,
    );
    final container = harness.container();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SalaApp()),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();
    await tester.pump(const Duration(milliseconds: 200));
    await notifier.goConversa(pericope: 'P01');
    await tester.pump(const Duration(milliseconds: 400));

    expect(container.read(salaSessionProvider).btPhase, BtPhase.conferida);
    expect(container.read(salaSessionProvider).partes, isEmpty,
        reason: 'a sessão volta do servidor sem gravação nenhuma no tablet');
    expect(byLabel(_aprovar), findsOneWidget,
        reason: 'aprovar continua sendo o gesto da conferida');
    expect(byLabel(_ouvir), findsNothing,
        reason: 'um botão de ouvir sem nada para tocar é um botão morto numa '
            'sala onde ninguém pode ler por que ele não responde');
  });

  testWidgets('a aprovação conta a vez que não tocou', (tester) async {
    final it = await _ateAConferida(tester);
    it.harness.voice.refuses.add(fixedLineAsset(approvedLine, testLanguage));

    await tester.tap(byLabel(_aprovar));
    await tester.pump(const Duration(milliseconds: 400));

    expect(_estado(it.container).voice, VoiceState.invite,
        reason: 'uma fala que não sai devolve o gesto à equipe, como nas outras '
            'cinco vezes em que a sala fala');
    expect(_estado(it.container).btPhase, BtPhase.conferida,
        reason: 'e o colar não fecha sobre uma aprovação que a equipe não ouviu');
    expect(it.harness.room.releasesAsked, hasLength(1));

    await tester.tap(byLabel(_aprovar));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_estado(it.container).needsPerson, isFalse,
        reason: 'duas são aviso, não parada');
    expect(it.harness.room.releasesAsked, hasLength(1),
        reason: 'a soltura já é da sala; apertar de novo repete a fala, não o pedido');

    await tester.tap(byLabel(_aprovar));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_estado(it.container).needsPerson, isTrue,
        reason: 'na terceira a sala para por uma pessoa, como em toda outra fala');

    closeTheRoom(it.container);
  });

  testWidgets('com a fala de volta, a aprovação fecha o colar', (tester) async {
    final it = await _ateAConferida(tester, fimLinger: const Duration(milliseconds: 40));

    await tester.tap(byLabel(_aprovar));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 800));

    expect(it.harness.room.releasesAsked, hasLength(1));
    expect(_estado(it.container).stage, SalaStage.fim,
        reason: 'ouvida a fala, o colar fecha');

    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 200));
    closeTheRoom(it.container);
  });
}

SalaSessionState _estado(ProviderContainer container) =>
    container.read(salaSessionProvider);

class _Conferida {
  final SalaHarness harness;
  final ProviderContainer container;

  _Conferida(this.harness, this.container);
}

/// A team standing on a passage the room has just called checked, with nothing pressed.
Future<_Conferida> _ateAConferida(
  WidgetTester tester, {
  Duration fimLinger = const Duration(seconds: 30),
}) async {
  final harness = SalaHarness(filaEmMemoria: true, fimLinger: fimLinger)
    ..room.verdictChecked = true;
  harness.playback.length = resto.umaParteInteira;
  final container = harness.container();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await tester.pump(const Duration(milliseconds: 100));

  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.goConversa(pericope: 'P01');
  await tester.pump(const Duration(milliseconds: 200));
  notifier.goEnsaio();
  await tester.pump(const Duration(milliseconds: 100));
  await resto.gravarUmaParte(tester, notifier);
  notifier.startRetro();
  await tester.pump(const Duration(milliseconds: 200));
  harness.playback.at = resto.umaParteInteira;
  notifier.cortarTrecho();
  await tester.pump(const Duration(milliseconds: 200));
  notifier.retroTap();
  await tester.pump(const Duration(milliseconds: 600));
  harness.playback.finishPlayback();
  await tester.pump(const Duration(milliseconds: 200));
  await notifier.finishBackTranslation();
  await tester.pump(const Duration(milliseconds: 300));
  expect(container.read(salaSessionProvider).btPhase, BtPhase.conferida,
      reason: 'o cenário parte de uma passagem que a sala deu por conferida');
  return _Conferida(harness, container);
}
