import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/scene_question.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'resto_da_historia_test.dart' as resto;
import 'scenario_helpers.dart';
import 'um_ensaio_de_tres_partes.dart';

const _aprovar = 'Aprovar como rascunho final';
const _pronto = 'Pronto';
const micParteLabel = 'voltar e regravar uma parte';

/// A team standing on a finding the analyst addressed to the stretch of part 2, with the
/// three parts recorded, told back whole and nothing pressed yet.
Future<Sala> _oAchadoNaParteDois({WorkInProgress? emAbertoNoDisco}) async {
  final it = await umEnsaioDeTresPartesContadoInteiro(
    emAbertoNoDisco: emAbertoNoDisco,
  );
  it.harness.room
    ..verdictChecked = false
    ..verdictHasFinding = true
    ..verdictFindingPlace = 1;
  await pedirOVeredito(it);
  expect(
    it.estado.btPhase,
    BtPhase.playing,
    reason:
        'o cenário só mede alguma coisa se a sala tiver mesmo devolvido '
        'um achado',
  );
  expect(
    it.estado.btFindingTrecho?.parte,
    1,
    reason:
        'e se esse achado apontar a parte 2, que é a que a equipe grava '
        'de novo',
  );
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
  it.sala.ouvirGravacao();
  await waitFor('a parte 3 entrar no ar', () => !it.estado.btParteFronteira);
  it.harness.playback.finishPlayback();
  await waitFor('a parte 3 acabar de tocar', () => it.estado.btClipEnded);
  it.harness.room.verdictFindingPlace = it.harness.room.segments.length - 1;
  await pedirOVeredito(it);
  expect(
    it.estado.btFindingTrecho?.parte,
    1,
    reason:
        'o cenário só mede alguma coisa se o achado voltar a apontar a '
        'parte 2',
  );
}

/// Cut and tell one stretch of the part in the air, whether or not the room has named it:
/// a part with no name takes the nameless path and no stretch enters the cord.
Future<void> _contarUmTrecho(Sala it, Duration quanto) async {
  final antes = it.estado.btTrechos.length + it.estado.btChunkFailures.length;
  it.harness.playback.length = quanto;
  it.harness.playback.at = quanto;
  it.sala.retroTap();
  it.sala.retroTap();
  await waitFor(
    'o microfone abrir no trecho',
    () => it.estado.btPhase == BtPhase.capturing,
  );
  await confirmarATraducao(it.container);
  await waitFor(
    'a sala responder pelo trecho',
    () =>
        it.estado.btTrechos.length + it.estado.btChunkFailures.length ==
        antes + 1,
  );
}

/// Record the part, leave it pending, and record it over: its row's third and fourth
/// taps. Answers the file left pending, after checking the one it replaced left the tablet.
Future<String> _gravarPorCima(Sala it) async {
  it.sala.gravarACena(2);
  await waitFor(
    'a gravação começar',
    () => it.estado.ensaio == EnsaioStatus.recording,
  );
  it.sala.gravarACena(2);
  await waitFor(
    'a parte ficar pendente',
    () => it.estado.ensaio == EnsaioStatus.recorded,
  );
  final substituida = it.harness.recorder.lastPath!;
  it.sala.gravarACena(2);
  await waitFor(
    'a gravação por cima começar',
    () => it.estado.ensaio == EnsaioStatus.recording,
  );
  it.sala.gravarACena(2);
  await waitFor(
    'a gravação por cima ficar pendente',
    () =>
        it.estado.ensaio == EnsaioStatus.recorded &&
        it.harness.recorder.lastPath != substituida,
  );
  expect(
    it.harness.recorder.deleted,
    isNot(contains(substituida)),
    reason: 'ENG-1347: a parte gravada de novo fica no tablet como histórico',
  );
  return it.harness.recorder.lastPath!;
}

bool _discoAceso(WidgetTester tester) =>
    tester
        .widget<Semantics>(inTheHome('Traduzir a gravação'))
        .properties
        .enabled ==
    true;

/// Play the rehearsal so far to its end, answering what the player opened in order.
Future<List<String>> _ouvirOEnsaioAteAqui(Sala it) async {
  it.harness.playback.played.clear();
  it.sala.playTheRehearsal();
  await waitFor('o ensaio começar a tocar', () => it.estado.playPing);
  for (var vezes = 0; vezes < 12 && it.estado.playPing; vezes++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    it.harness.playback.finishPlayback();
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  expect(it.estado.playPing, isFalse, reason: 'o ensaio termina sozinho');
  return List.of(it.harness.playback.played);
}

Future<void> _tocar(WidgetTester tester, String label) async {
  await tester.ensureVisible(offTheRows(label));
  await tester.tap(offTheRows(label));
  await tester.pump(const Duration(milliseconds: 200));
}

/// Part 2's row records it again and stops it, and the check confirms it: every gesture a
/// gesture the team has on the rehearsal screen.
Future<void> _gravarAParteDoisPorCimaEConfirmar(WidgetTester tester) async {
  for (final controle in ['Gravar de novo', 'Parar']) {
    final daLinhaDois = find.descendant(
      of: linhaDoEnsaio(2),
      matching: byLabel(controle),
    );
    await tester.ensureVisible(daLinhaDois);
    await tester.tap(daLinhaDois);
    await tester.pump(const Duration(milliseconds: 200));
  }
  await _tocar(tester, 'Enviar a gravação');
  await letTheRehearsalReachTheRoom(tester);
}

/// What the report the tablet sends says about each part, by the name the room gave it.
Map<String, List<List<int>>> _escutaRelatada(Sala it) => {
  for (final parte in it.harness.room.playedByTakeSent.last)
    parte['take_id']! as String: (parte['played_ranges']! as List)
        .cast<List<int>>(),
};

void main() {
  test('a parte dois gravada de novo fica no lugar da parte dois', () async {
    final it = await _oAchadoNaParteDois();
    final antes = it.partes;
    final enviadas = it.harness.room.takes.length;

    it.sala.leaveTheBackTranslation();
    final porCima = await _gravarPorCima(it);
    it.sala.takeKeep();
    await waitFor(
      'a gravação confirmada tomar o lugar da parte 2',
      () => it.partes[1].path != antes[1].path,
    );
    expect(
      it.partes[1].path,
      porCima,
      reason: 'é a última gravação por cima que o check confirma',
    );
    expect(
      it.estado.btTrechos.where((trecho) => trecho.parte == 1),
      isEmpty,
      reason:
          'os trechos contados sobre a gravação substituída saem como chão '
          'por contar (ADR 0020)',
    );
    await waitFor(
      'a gravação nova chegar à sala',
      () => it.harness.room.takes.length > enviadas,
    );

    final agora = it.partes;
    expect(
      agora,
      hasLength(3),
      reason: 'gravar a parte 2 de novo é a parte 2 outra vez, não uma quarta',
    );
    expect(agora[1].scopeId, KeptScope.parte(2));
    expect(
      agora[1].path,
      isNot(antes[1].path),
      reason: 'e é a gravação nova que ocupa o lugar',
    );
    expect(
      [agora[0].path, agora[0].takeId],
      [antes[0].path, antes[0].takeId],
      reason: 'as outras partes são trabalho da equipe que ninguém tocou',
    );
    expect([agora[2].path, agora[2].takeId], [antes[2].path, antes[2].takeId]);

    expect(
      it.estado.partes.length,
      3,
      reason:
          'a conta do ensaio conta partes, e gravar a parte 2 de novo '
          'não dá ao ensaio uma quarta',
    );

    final subiu = it.harness.room.takes.last;
    expect(subiu.scope, KeptScope.parte(2));
    expect(
      subiu.ordinal,
      2,
      reason:
          'a sala tem de receber a gravação sob o número que ela já tem, '
          'senão a parte 2 vira a parte 4 do lado de lá também',
    );
    expect(
      it.harness.room.takePasses.last,
      2,
      reason:
          'a parte regravada sobe sob a passada seguinte à da gravação que '
          'ela substitui: sob a mesma, a sala só tem a ordem de chegada para '
          'escolher entre as duas, e a que a equipe abandonou pode chegar por último',
    );
  });

  test(
    'cada gravação da parte sobe sob a passada seguinte, e uma parte nova sob a '
    'primeira dela',
    () async {
      final it = await _oAchadoNaParteDois();
      expect(
        it.harness.room.takePasses,
        [1, 1, 1],
        reason:
            'as três partes gravadas pela primeira vez são a primeira '
            'gravação de cada uma',
      );

      it.sala.leaveTheBackTranslation();
      await regravarAParte(it, 1);
      await waitFor(
        'a segunda gravação da parte 2 chegar à sala',
        () => it.harness.room.takePasses.length == 4,
      );
      expect(it.harness.room.takePasses.last, 2);

      await _oAchadoOutraVezNaParteDois(it);
      it.sala.leaveTheBackTranslation();
      await regravarAParte(it, 1);
      await waitFor(
        'a terceira gravação da parte 2 chegar à sala',
        () => it.harness.room.takePasses.length == 5,
      );
      expect(
        it.harness.room.takePasses.last,
        3,
        reason: 'a conta é da parte, e segue de onde a parte 2 parou',
      );

      await gravarUmaParteDoEnsaio(it, 4);

      expect(it.harness.room.takesKept.last, 'ensaio/${KeptScope.parte(4)}');
      expect(
        it.harness.room.takePasses.last,
        1,
        reason:
            'uma parte gravada pela primeira vez é a primeira gravação dela, '
            'seja qual for a conta das outras partes',
      );
    },
  );

  test('a linha do lugar guarda a gravação em que cada parte está', () async {
    final it = await _oAchadoNaParteDois();

    it.sala.leaveTheBackTranslation();
    await regravarAParte(it, 1);
    await waitFor('o lugar da equipe ser escrito com o arquivo novo', () {
      final ponto = it.harness.emAberto.rows['Ruth/P01/pt'];
      return ponto != null &&
          ponto.takes.length == 3 &&
          ponto.takes[1].path == it.partes[1].path;
    });

    expect(
      [
        for (final take in it.harness.emAberto.rows['Ruth/P01/pt']!.takes)
          take.pass,
      ],
      [1, 2, 1],
      reason:
          'a retomada precisa saber em que gravação de cada parte a equipe '
          'parou: sem isso a próxima regravação sobe sob uma passada que a sala '
          'já tem',
    );
  });

  test(
    'a parte regravada cuja linha ainda não pousou deixa a conferência '
    'fechada, e depois de pousar o trecho contado sobre ela sobe nomeado',
    () async {
      final it = await _oAchadoNaParteDois();
      it.harness.room.holdNextTake(KeptScope.parte(2));

      it.sala.leaveTheBackTranslation();
      await regravarAParte(it, 1);
      await it.harness.room.untilTakeHeld();
      expect(
        it.partes[1].takeId,
        isNull,
        reason: 'a tomada não subiu, e não tem nome nenhum para adotar',
      );

      it.harness.playback.lengths[it.partes[1].path] = partesDoEnsaio[1];
      it.sala.startRetro();
      await settle();
      expect(
        it.estado.stage,
        SalaStage.ensaio,
        reason:
            'a conferência abria com a parte 2 ainda no ar, e contava trechos '
            'sobre uma parte que a sala não tinha',
      );

      it.harness.room.finishHeldTake();
      await waitFor(
        'a parte aprender o nome quando a linha dela pousa',
        () => it.partes[1].takeId != null,
      );
      expect(
        it.partes[1].takeId,
        it.harness.room.takes
            .lastWhere(
              (take) =>
                  take.kind == 'ensaio' && take.scope == KeptScope.parte(2),
            )
            .takeId,
        reason: 'o nome é o que a sala deu a esta gravação da parte 2',
      );

      it.sala.startRetro();
      await waitFor(
        'a tradução recomeçar na parte gravada de novo',
        () =>
            it.estado.stage == SalaStage.retro &&
            it.estado.btPhase == BtPhase.playing,
      );
      await _contarUmTrecho(it, partesDoEnsaio[1]);
      await waitFor(
        'o trecho subir com o nome da parte',
        () => it.harness.room.chunkTakes.isNotEmpty,
      );

      expect(
        it.harness.room.chunkTakes.last,
        it.partes[1].takeId,
        reason:
            'sem o nome, todo trecho contado sobre esta parte subiria como '
            'uma retro da passagem inteira, e a sala nunca a guardaria como '
            'trecho da parte 2',
      );
      expect(it.estado.btChunkFailures, isEmpty);
    },
  );

  test('a parte nova ganha o nome do servidor e nunca o da antiga', () async {
    final it = await _oAchadoNaParteDois();
    final antiga = it.partes[1].takeId;

    it.sala.leaveTheBackTranslation();
    await regravarAParte(it, 1);
    await waitFor(
      'a sala nomear a parte nova',
      () => it.partes[1].takeId != null,
    );

    expect(
      it.partes[1].takeId,
      it.harness.room.takeIds.last,
      reason: 'o nome que chega é o que a sala acabou de dar a este arquivo',
    );
    expect(
      it.partes[1].takeId,
      isNot(antiga),
      reason:
          'herdar o nome da antiga é mandar os trechos novos para a '
          'gravação que ninguém vai ouvir de novo',
    );
    final nomes = [for (final take in it.estado.keptTakes) take.takeId];
    expect(
      nomes.toSet(),
      hasLength(nomes.length),
      reason: 'duas tomadas guardadas nunca dividem um nome',
    );
  });

  test(
    'o nome só pousa na parte nova, e só quando a sala responde por ela',
    () async {
      final it = await _oAchadoNaParteDois();
      final antes = [for (final parte in it.partes) parte.takeId];

      it.harness.room.holdNextTake(KeptScope.parte(2));
      it.sala.leaveTheBackTranslation();
      await regravarAParte(it, 1);
      await it.harness.room.untilTakeHeld();

      expect(
        it.partes[1].takeId,
        isNull,
        reason:
            'enquanto a sala não responde, a parte nova não tem nome — e o '
            'da antiga não serve',
      );
      expect([it.partes[0].takeId, it.partes[2].takeId], [antes[0], antes[2]]);

      it.harness.room.finishHeldTake();
      await waitFor('o nome novo pousar', () => it.partes[1].takeId != null);

      expect(it.partes[1].takeId, isNot(antes[1]));
      expect(
        [it.partes[0].takeId, it.partes[2].takeId],
        [antes[0], antes[2]],
        reason: 'e pousa só nela',
      );
    },
  );

  test(
    'os trechos das partes um e três ficam e os da parte dois saem',
    () async {
      final it = await _oAchadoNaParteDois();
      final antes = it.estado.btTrechos;
      expect(antes, hasLength(3));

      it.sala.leaveTheBackTranslation();
      await regravarAParte(it, 1);

      final agora = it.estado.btTrechos;
      expect(
        [for (final trecho in agora) trecho.parte],
        isNot(contains(1)),
        reason:
            'o que foi contado sobre a gravação antiga não conta sobre a nova',
      );
      expect(
        [for (final trecho in agora) trecho.segmentId],
        [antes[0].segmentId, antes[2].segmentId],
        reason: 'e os trechos das outras partes seguem sendo os mesmos trechos',
      );
      expect(
        [
          for (final trecho in agora) [trecho.lugarFrom, trecho.lugarTo],
        ],
        [
          [antes[0].lugarFrom, antes[0].lugarTo],
          [antes[2].lugarFrom, antes[2].lugarTo],
        ],
        reason: 'cada um no lugar que sempre ocupou',
      );
    },
  );

  test(
    'a escuta das partes um e três sobrevive e a nova começa do zero',
    () async {
      final it = await _oAchadoNaParteDois();
      final antiga = it.partes[1].takeId;

      it.sala.leaveTheBackTranslation();
      await regravarAParte(it, 1);
      await waitFor(
        'a sala nomear a parte nova',
        () => it.partes[1].takeId != null,
      );
      final nomes = [for (final parte in it.partes) parte.takeId!];

      it.sala.startRetro();
      await waitFor(
        'a tradução voltar a tocar a parte 2',
        () => it.harness.playback.played.last == it.partes[1].path,
      );
      await ouvirETraduzirAParteInteira(it, partesDoEnsaio[1]);
      it.sala.ouvirGravacao();
      await waitFor(
        'a parte 3 entrar no ar',
        () => !it.estado.btParteFronteira,
      );
      it.harness.playback.length = partesDoEnsaio[2];
      it.harness.playback.at = partesDoEnsaio[2];
      it.harness.playback.finishPlayback();
      await waitFor('a parte 3 terminar', () => it.estado.btClipEnded);
      await pedirOVeredito(it);

      final relato = _escutaRelatada(it);
      expect(
        relato.keys,
        containsAll(nomes),
        reason:
            'as três partes do ensaio, uma entrada cada, sob o nome que '
            'cada uma tem agora',
      );
      expect(
        relato.keys,
        isNot(contains(antiga)),
        reason:
            'a gravação que a parte 2 deixou de ser não é evidência de nada',
      );
      expect(
        [for (final nome in nomes) resto.ouvidoAteMs(relato[nome]!)],
        [
          partesDoEnsaio[0].inMilliseconds,
          partesDoEnsaio[1].inMilliseconds,
          partesDoEnsaio[2].inMilliseconds,
        ],
        reason: 'cada parte coberta do seu próprio zero ao seu próprio fim',
      );
    },
  );

  test('a próxima tradução começa na parte gravada de novo', () async {
    final it = await _oAchadoNaParteDois();

    it.sala.leaveTheBackTranslation();
    await regravarAParte(it, 1);
    final nova = it.partes[1].path;
    final tocadas = it.harness.playback.played.length;
    await waitFor('a sala guardar a parte 1', () => it.estado.ensaioDone);

    it.sala.startRetro();
    await waitFor(
      'a tradução recomeçar',
      () => it.harness.playback.played.length > tocadas,
    );

    expect(
      it.harness.playback.played.last,
      nova,
      reason:
          'o chão da parte 2 está por contar outra vez; a parte 1 está '
          'contada e a sala passa por cima dela',
    );
  });

  test('a retomada traz as três partes na ordem, com o arquivo novo', () async {
    final it = await _oAchadoNaParteDois();
    final antes = it.partes;

    it.sala.leaveTheBackTranslation();
    await regravarAParte(it, 1);
    await waitFor(
      'a sala nomear a parte nova',
      () => it.partes[1].takeId != null,
    );
    final nova = it.partes[1];

    await waitFor('o lugar da equipe ser escrito', () {
      final ponto = it.harness.emAberto.rows['Ruth/P01/pt'];
      return ponto != null &&
          ponto.takes.length == 3 &&
          ponto.takes[1].path == nova.path;
    });
    final ponto = it.harness.emAberto.rows['Ruth/P01/pt']!;
    expect(
      [for (final take in ponto.takes) take.scopeId],
      [KeptScope.parte(1), KeptScope.parte(2), KeptScope.parte(3)],
    );
    expect(
      [for (final take in ponto.takes) take.path],
      [antes[0].path, nova.path, antes[2].path],
    );

    it.container.dispose();
    it.container = it.harness.container();
    addTearDown(it.container.dispose);
    await it.sala.abrirEscolha();
    await waitFor(
      'a roda dizer que esta passagem tem trabalho parado',
      () => it.estado.comecadas.contains('P01'),
    );
    await it.sala.goConversa(book: 'Ruth', pericope: 'P01');
    await intoTheRecordingHome(it.sala, () => it.estado);

    expect(
      [for (final parte in it.partes) parte.path],
      [antes[0].path, nova.path, antes[2].path],
      reason:
          'reabrir a passagem devolve as três partes na ordem, com a '
          'gravação nova no lugar da parte 2',
    );
  });

  test(
    'a cena que a sala perdeu, gravada depois da retomada pela bolinha, sobe '
    'acima da passada da sala, com uma correção guardada ao lado',
    () async {
      final harness = SalaHarness()
        ..playback.measured = partesDoEnsaio.first
        ..room.passageScenes = const [
          Scene(sceneId: 'S1', title: 'Cena um'),
          Scene(sceneId: 'S2', title: 'Cena dois'),
          Scene(sceneId: 'S3', title: 'Cena tres'),
        ];
      final casa = Directory.systemTemp.createTempSync('sala-passada-guardada');
      addTearDown(() => casa.deleteSync(recursive: true));
      KeptTake guardada(String scope, String takeId) => KeptTake(
        scopeId: scope,
        path: (File(
          '${casa.path}/$takeId.m4a',
        )..writeAsBytesSync([1, 2, 3])).path,
        takeId: takeId,
      );
      harness.room.takes.addAll([
        for (final n in [1, 3])
          TakeView(
            takeId: 'gravacao-$n',
            kind: 'ensaio',
            scope: KeptScope.parte(n),
            ordinal: n,
          ),
      ]);
      harness.emAberto.rows['Ruth/P01/pt'] = ResumePoint(
        sessionId: 'sessao-antiga',
        stage: SalaStage.ensaio,
        takes: [
          guardada(KeptScope.parte(1), 'gravacao-1'),
          guardada(KeptScope.parte(3), 'gravacao-3'),
          guardada('trecho-1', 'gravacao-4'),
        ],
        passesToGoAbove: const {2: 2},
      );
      final it = Sala(harness, harness.container());
      addTearDown(it.container.dispose);
      await it.sala.abrirEscolha();
      await it.sala.goConversa(book: 'Ruth', pericope: 'P01');
      await throughTheOrangeDot(it.sala, () => it.estado);

      await gravarUmaParteDoEnsaio(it, 2);
      await waitFor(
        'a cena 2 chegar à sala',
        () => harness.room.takesKept.contains('ensaio/${KeptScope.parte(2)}'),
      );

      expect(harness.room.takePasses.last, 3);
    },
  );

  test('o ensaio até aqui toca a parte regravada no lugar dela', () async {
    final it = await _oAchadoNaParteDois();
    final antes = it.partes;

    it.sala.leaveTheBackTranslation();
    final pendente = await _gravarPorCima(it);

    expect(
      await _ouvirOEnsaioAteAqui(it),
      [antes[0].path, pendente, antes[2].path],
      reason:
          'a regravação pendente toma o lugar da parte 2: a gravação antiga '
          'dela não toca, e nada toca no fim',
    );

    it.sala.takeKeep();
    await waitFor(
      'a gravação confirmada tomar o lugar da parte 2',
      () => it.partes[1].path == pendente,
    );
    await waitFor(
      'a sala guardar a parte 2',
      () => it.estado.canPlayTheRehearsal,
    );

    expect(
      await _ouvirOEnsaioAteAqui(it),
      [antes[0].path, pendente, antes[2].path],
      reason:
          'confirmada, a parte 2 é ouvida no lugar dela, pelo arquivo, já '
          'que os trechos dela saíram (ADR 0020)',
    );
  });

  test('gravar por cima duas vezes ainda troca a parte dois', () async {
    final it = await _oAchadoNaParteDois();
    final antes = it.partes;
    final enviadas = it.harness.room.takes.length;

    it.sala.leaveTheBackTranslation();
    await _gravarPorCima(it);
    it.sala.gravarACena(2);
    await waitFor(
      'a segunda gravação por cima começar',
      () => it.estado.ensaio == EnsaioStatus.recording,
    );
    it.sala.gravarACena(2);
    await waitFor(
      'a segunda gravação por cima ficar pendente',
      () => it.estado.ensaio == EnsaioStatus.recorded,
    );
    final ultima = it.harness.recorder.lastPath!;
    expect(
      it.harness.room.takes,
      hasLength(enviadas),
      reason: 'nada sobe antes do check',
    );

    it.sala.takeKeep();
    await waitFor(
      'a gravação nova tomar o lugar da parte 2',
      () => it.partes[1].path == ultima,
    );

    expect(
      it.partes,
      hasLength(3),
      reason:
          'gravar por cima é a mesma gravação outra vez; a sala não pode '
          'esquecer qual parte a equipe veio refazer',
    );
    expect(it.partes[1].scopeId, KeptScope.parte(2));
    expect(it.partes[1].path, isNot(antes[1].path));
  });

  test('depois da troca, guardar outra vez volta a acrescentar', () async {
    final it = await _oAchadoNaParteDois();

    it.sala.leaveTheBackTranslation();
    await regravarAParte(it, 1);
    await gravarUmaParteDoEnsaio(it, 4);

    expect(
      it.partes,
      hasLength(4),
      reason:
          'a parte que a equipe veio refazer gasta-se no guardar: a '
          'gravação seguinte é uma parte nova, não a parte 2 outra vez',
    );
    expect(it.partes.last.scopeId, KeptScope.parte(4));
    expect(it.estado.partes.length, 4);
  });

  testWidgets('o microfone de madeira do achado leva à casa, e a linha da '
      'parte a grava de novo no lugar', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await resto.aHistoriaSemOFim(
      tester,
      harness,
      ondeFalta: 'trecho-2',
    );
    final fases = <BtPhase>[];
    container.listen(
      salaSessionProvider,
      (_, agora) => fases.add(agora.btPhase),
      fireImmediately: true,
    );
    final antes = container.read(salaSessionProvider).partes;
    expect(antes, hasLength(3));

    await tester.ensureVisible(byLabel(micParteLabel));
    await tester.tap(byLabel(micParteLabel));
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      container.read(salaSessionProvider).stage,
      SalaStage.ensaio,
      reason: 'o microfone de madeira leva à casa, onde a parte se grava',
    );
    expect(
      [
        for (var onde = 0; onde < fases.length; onde++)
          if (onde == 0 || fases[onde] != fases[onde - 1]) fases[onde],
      ],
      [BtPhase.playing],
      reason:
          'do achado ao ensaio num gesto: o microfone de madeira não '
          'passa por posto nenhum pelo caminho',
    );

    await _gravarAParteDoisPorCimaEConfirmar(tester);

    final agora = container.read(salaSessionProvider).partes;
    expect(agora, hasLength(3));
    expect(agora[1].path, isNot(antes[1].path));
    expect([agora[0].path, agora[2].path], [antes[0].path, antes[2].path]);
  });

  testWidgets('«voltar e regravar uma parte» leva à casa sem parte marcada, '
      'toda linha acesa e o disco aceso', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await resto.aHistoriaSemOFim(
      tester,
      harness,
      ondeFalta: 'trecho-2',
    );

    await tester.ensureVisible(byLabel(micParteLabel));
    await tester.tap(byLabel(micParteLabel));
    await tester.pump(const Duration(milliseconds: 400));

    expect(container.read(salaSessionProvider).stage, SalaStage.ensaio);
    expect(
      naLinhaDoEnsaio(tester, 'Gravar de novo'),
      [true, true, true, null],
      reason:
          'o botão marcava a parte do achado e apagava as outras linhas; '
          'o dela volta à casa livre para gravar qualquer parte ou nenhuma',
    );
    expect(
      _discoAceso(tester),
      isTrue,
      reason: 'com toda cena gravada, o disco leva de novo à tradução',
    );
  });

  testWidgets('a parte gravada de novo pela linha e confirmada deixa toda '
      'linha acesa', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await resto.aHistoriaSemOFim(
      tester,
      harness,
      ondeFalta: 'trecho-2',
    );
    final antes = container.read(salaSessionProvider).partes;

    await tester.ensureVisible(byLabel(micParteLabel));
    await tester.tap(byLabel(micParteLabel));
    await tester.pump(const Duration(milliseconds: 400));
    await _gravarAParteDoisPorCimaEConfirmar(tester);

    expect(
      _discoAceso(tester),
      isTrue,
      reason: 'a parte 2 confirmada, o disco leva de volta à tradução',
    );
    expect(
      naLinhaDoEnsaio(tester, 'Gravar de novo'),
      [true, true, true, null],
      reason:
          'a parte 2 confirmada, nenhuma linha fica presa a ela, e a '
          'próxima gravação da equipe não vem tomar o lugar dela outra vez',
    );
    expect(
      container.read(salaSessionProvider).partes[1].pass,
      antes[1].pass + 1,
      reason: 'a parte regravada sobe sob a passada seguinte',
    );
    final agora = container.read(salaSessionProvider).partes;
    expect(
      agora,
      hasLength(3),
      reason: 'e a gravação nova não acrescentou uma parte ao ensaio',
    );
    expect(
      agora[1].path,
      isNot(antes[1].path),
      reason: 'a gravação nova ficou no lugar da parte 2 (ADR 0020)',
    );
  });

  testWidgets('o colar mostra chão nu sobre a parte dois', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await resto.aHistoriaSemOFim(
      tester,
      harness,
      ondeFalta: 'trecho-2',
    );
    for (final parte in container.read(salaSessionProvider).partes) {
      harness.playback.lengths[parte.path] = umaParteInteira;
    }
    harness.playback.measured = const Duration(seconds: 12);

    await tester.ensureVisible(byLabel(micParteLabel));
    await tester.tap(byLabel(micParteLabel));
    await tester.pump(const Duration(milliseconds: 400));
    await _gravarAParteDoisPorCimaEConfirmar(tester);

    expect(
      container.read(salaSessionProvider).btFimDasPartesMs,
      [30000, 42000, 72000],
      reason:
          'a régua é onde cada parte acaba ao longo do cordão: a parte 2 '
          'é um arquivo do seu próprio tamanho, e desenhada com o da que ela '
          'substituiu o cordão fala de um ensaio que não existe mais',
    );

    final partes = container.read(salaSessionProvider).partes;
    final medidasAntes = List.of(harness.playback.measurements);
    await tester.tap(inTheHome('Traduzir a gravação'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      container.read(salaSessionProvider).stage,
      SalaStage.retro,
      reason: 'o disco de madeira leva de volta à tradução',
    );

    final estado = container.read(salaSessionProvider);
    expect(
      estado.partes,
      hasLength(3),
      reason: 'o ensaio continua tendo três partes',
    );
    expect(
      container.read(salaSessionProvider).btFimDasPartesMs,
      [30000, 42000, 72000],
      reason:
          'e a entrada na tradução mede o ensaio inteiro antes de pôr '
          'parte nenhuma no ar: com a régua truncada na parte por contar, o '
          'colar deixava de desenhar as faixas da parte 3 até a parte 2 '
          'acabar de tocar',
    );
    expect(
      {for (final trecho in estado.btTrechos) trecho.parte},
      {0, 2},
      reason: 'nenhuma faixa sobre a parte 2: o chão dela está por contar',
    );
    expect(
      estado.btFindingTrecho,
      isNull,
      reason:
          'o achado seguia apontando um trecho à espera de conserto, e este '
          'chão não esperava conserto nenhum, esperava ser contado',
    );
    expect(
      harness.playback.played.last,
      partes[1].path,
      reason: 'a parte por contar é a que entra no ar',
    );
    expect(
      harness.playback.playedFrom.last,
      Duration.zero,
      reason:
          'e desde o começo dela: os trechos que a cobriam saíram com a '
          'gravação que ela substituiu',
    );
    expect(
      harness.playback.measurements.sublist(medidasAntes.length),
      containsAll([for (final parte in partes) parte.path]),
      reason: 'as três partes são medidas na entrada, sem serem tocadas',
    );

    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 200));
    closeTheRoom(container);
  });

  testWidgets(
    'com a leitura depois da aprovação perdida, uma parada ali deixa o pronto na '
    'tela, e sobe na conversa depois do pronto',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _ateAConferida(tester);
      it.harness.room.failStateOnceWith = const NetworkFailed('sem rede');

      await pressTheApproval(tester, _aprovar);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(byLabel(_pronto));
      await tester.pump(const Duration(milliseconds: 400));
      it.harness.room.readsChecked = true;
      final sala = it.container.read(salaSessionProvider.notifier);
      sala.openTheEnsaioFinal();
      await tester.pump(const Duration(seconds: 1));
      sala.startRetro();
      await tester.pump(const Duration(seconds: 1));
      expect(
        byLabel(_aprovar),
        findsOneWidget,
        reason:
            'sem a leitura depois da aprovação o selo não vem, e aprovar '
            'segue oferecido',
      );
      await pressTheApproval(tester, _aprovar);
      it.container.read(salaSessionProvider.notifier).haltForABrokenBuild();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(seconds: 2));

      expect(_estado(it.container).needsPerson, isFalse);
      expect(
        find.bySemanticsLabel(_pronto),
        findsOneWidget,
        reason: 'o sinal cobria a retro e escondia o pronto',
      );

      await tester.tap(byLabel(_pronto));
      await tester.pump(const Duration(milliseconds: 400));

      expect(_estado(it.container).stage, SalaStage.conversa);
      expect(
        _estado(it.container).needsPerson,
        isTrue,
        reason: 'a parada que esperava sobe quando o pronto leva à conversa',
      );
      closeTheRoom(it.container);
      semantics.dispose();
    },
  );

  testWidgets('a aprovação que não toca deixa silêncio', (tester) async {
    final it = await _ateAConferida(tester);
    it.harness.voice.refuses.add('P3');

    await pressTheApproval(tester, _aprovar);
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      _estado(it.container).voice,
      VoiceState.done,
      reason:
          'uma fala que não sai devolve o gesto à equipe, como nas outras '
          'cinco vezes em que a sala fala: na conferida o círculo diz acabado',
    );
    expect(
      _estado(it.container).btPhase,
      BtPhase.conferida,
      reason: 'a aprovação não tira a equipe da conferida',
    );
    expect(it.harness.room.releasesAsked, hasLength(1));

    expect(
      _estado(it.container).needsPerson,
      isFalse,
      reason: 'uma é silêncio, não parada',
    );

    expect(
      find.text('Ensaio salvo'),
      findsOneWidget,
      reason:
          'a fala que não sai não segura a tela do ensaio salvo: a aprovação '
          'já é da sala',
    );

    closeTheRoom(it.container);
  });

  testWidgets('com a fala de volta, a aprovação termina no ensaio salvo', (
    tester,
  ) async {
    final it = await _ateAConferida(tester);

    await pressTheApproval(tester, _aprovar);
    await tester.pump(const Duration(milliseconds: 400));

    expect(it.harness.room.releasesAsked, hasLength(1));
    expect(
      find.text('Ensaio salvo'),
      findsOneWidget,
      reason: 'ouvida a fala, a tela do ensaio salvo vem',
    );

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
Future<_Conferida> _ateAConferida(WidgetTester tester) async {
  final harness = SalaHarness(filaEmMemoria: true)..room.verdictChecked = true;
  harness.playback.length = umaParteInteira;
  final container = harness.container();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await tester.pump(const Duration(milliseconds: 100));

  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.goConversa(book: 'Ruth', pericope: 'P01');
  await tester.pump(const Duration(milliseconds: 200));
  notifier.goEnsaio();
  await tester.pump(const Duration(milliseconds: 100));
  await gravarUmaParte(tester, container, 1);
  notifier.startRetro();
  await tester.pump(const Duration(milliseconds: 200));
  harness.playback.at = umaParteInteira;
  notifier.retroTap();
  notifier.retroTap();
  await tester.pump(const Duration(milliseconds: 200));
  await confirmarATraducaoNaTela(tester, container);
  await tester.pump(const Duration(milliseconds: 600));
  harness.playback.finishPlayback();
  await tester.pump(const Duration(milliseconds: 200));
  await notifier.finishBackTranslation();
  await tester.pump(const Duration(milliseconds: 300));
  expect(
    container.read(salaSessionProvider).btPhase,
    BtPhase.conferida,
    reason: 'o cenário parte de uma passagem que a sala deu por conferida',
  );
  return _Conferida(harness, container);
}
