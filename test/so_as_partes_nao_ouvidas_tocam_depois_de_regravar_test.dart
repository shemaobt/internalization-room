import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'um_ensaio_de_tres_partes.dart';

const _cincoPartes = [
  Duration(seconds: 10),
  Duration(seconds: 8),
  Duration(seconds: 12),
  Duration(seconds: 6),
  Duration(seconds: 9),
];

/// The part at [onde] recorded again the way ADR 0020 has it, through a finding on it,
/// and kept. With [semNome] its upload is held, so the room has not named it yet.
Future<void> _regravada(
  Sala it,
  int onde,
  Duration quanto, {
  bool semNome = false,
}) async {
  it.harness.room
    ..verdictChecked = false
    ..verdictHasFinding = true
    ..verdictFindingPlace = onde;
  await pedirOVeredito(it);
  expect(
    it.estado.btFindingTrecho?.parte,
    onde,
    reason: 'o cenário só mede alguma coisa se o achado apontar essa parte',
  );
  if (semNome) it.harness.room.holdNextTake('parte-${onde + 1}');
  it.sala.gravarAParteDeNovo();
  await regravarAParte(it, onde);
  if (!semNome) {
    await waitFor(
      'a sala nomear a parte gravada de novo',
      () => it.partes[onde].takeId != null,
    );
  }
  it.harness.playback.lengths[it.partes[onde].path] = quanto;
  it.harness.room
    ..verdictHasFinding = false
    ..verdictFindingPlace = null;
}

/// Into the back-translation, up to the first part going in the air.
Future<void> _entrar(Sala it) async {
  final tocadas = it.harness.playback.played.length;
  it.sala.startRetro();
  await waitFor(
    'uma parte entrar no ar',
    () =>
        it.harness.playback.played.length > tocadas &&
        it.estado.btPhase == BtPhase.playing,
  );
}

int _leituras(Sala it) =>
    it.harness.room.calls.where((call) => call == 'fetchState').length;

List<String> _linhas(Sala it, int desde) => [
  for (final (linha, _) in it.harness.voice.fixedLines.skip(desde)) linha,
];

void main() {
  test(
    'a parte gravada de novo numa passagem de cinco toca sozinha depois da fala dela',
    () async {
      final it = await umEnsaioContadoInteiro(_cincoPartes);
      await _regravada(it, 2, _cincoPartes[2], semNome: true);
      final terceira = it.partes[2].path;
      it.harness.room.listeningUnheardTakeIds = const [];
      final linhas = it.harness.voice.fixedLines.length;
      final sons = it.harness.sounds.length;
      final tocadas = it.harness.playback.played.length;

      await _entrar(it);

      expect(
        it.harness.voice.fixedLines.skip(linhas),
        [('P2', testLanguage)],
        reason:
            'quatro partes seguem ouvidas: a sala diz a P2 dela, «Ainda falta '
            'ouvir um trecho da gravação antes de eu conferir.», e não a abertura',
      );
      final depois = it.harness.sounds.skip(sons).toList();
      expect(depois, contains('voice:fixed'));
      expect(
        depois.indexOf('voice:fixed'),
        lessThan(depois.lastIndexOf('playback:play')),
        reason: 'a fala vem antes do som da parte',
      );
      expect(it.harness.playback.played.skip(tocadas), [terceira]);
      expect(it.harness.playback.playedFrom.last, Duration.zero);

      await ouvirAteOFim(it, _cincoPartes[2]);

      expect(
        it.estado.canFinishBackTranslation,
        isTrue,
        reason: 'ouvida a parte que faltava, terminei acende',
      );
      expect(
        it.estado.btParteFronteira,
        isFalse,
        reason: 'a quarta parte já foi ouvida: não há travessia para ela',
      );
      expect(it.harness.playback.played.skip(tocadas), [terceira]);
    },
  );

  test(
    'um sinal no meio da parte que falta guarda onde ela chegou, e ouvir depois do toque segue dali',
    () async {
      final it = await umEnsaioContadoInteiro(_cincoPartes);
      await _regravada(it, 2, _cincoPartes[2], semNome: true);
      final terceira = it.partes[2].path;
      it.harness.room.listeningUnheardTakeIds = const [];
      await _entrar(it);
      it.harness.playback.at = const Duration(seconds: 4);

      it.sala.haltForABrokenBuild();
      await waitFor('o sinal', () => it.estado.needsPerson);
      it.sala.teamTapped();
      final tocadas = it.harness.playback.playedFrom.length;
      it.sala.ouvirGravacao();
      await waitFor(
        'a parte voltar a tocar',
        () => it.harness.playback.playedFrom.length > tocadas,
      );

      expect(it.harness.playback.played.last, terceira);
      expect(
        it.harness.playback.playedFrom.last,
        const Duration(seconds: 4),
        reason: 'de onde a parte tinha chegado quando o sinal subiu',
      );
    },
  );

  test(
    'a sala pedindo uma pessoa durante a fala dela não mostra o sinal, e a parte que falta toca e para nela',
    () async {
      final it = await umEnsaioContadoInteiro(
        _cincoPartes,
        numaSala: SalaHarness(watchesWithoutAHalt: true),
      );
      await _regravada(it, 2, _cincoPartes[2]);
      final terceira = it.partes[2].path;
      it.harness.room.listeningUnheardTakeIds = [it.partes[2].takeId!];
      it.harness.voice.holdNextLine();
      final tocadas = it.harness.playback.played.length;

      it.sala.startRetro();
      await waitFor(
        'a P2 começar',
        () => it.harness.voice.fixedLines.any((linha) => linha.$1 == 'P2'),
      );
      it.harness.room.serverStatus = 'needs_person';
      final lidas = _leituras(it);
      await waitFor('a sala ler a sessão', () => _leituras(it) > lidas);
      it.harness.voice.finishHeldLine();
      await waitFor(
        'a parte que falta entrar no ar',
        () => it.harness.playback.played.length > tocadas,
      );
      expect(
        it.estado.needsPerson,
        isFalse,
        reason: 'uma leitura nunca levanta o sinal da pessoa',
      );
      expect(it.harness.playback.played.skip(tocadas), [terceira]);

      await ouvirAteOFim(it, _cincoPartes[2]);

      expect(
        it.estado.btParteFronteira,
        isFalse,
        reason: 'a quarta parte já foi ouvida: o replay para na que faltava',
      );
      expect(it.estado.canFinishBackTranslation, isTrue);
    },
  );

  test(
    'duas partes não ouvidas tocam em ordem e nunca seguem para uma já ouvida',
    () async {
      final it = await umEnsaioContadoInteiro(_cincoPartes);
      await _regravada(it, 3, _cincoPartes[3]);
      final segunda = it.partes[1];
      final quarta = it.partes[3];
      it.harness.room.listeningUnheardTakeIds = [
        quarta.takeId!,
        segunda.takeId!,
      ];
      final tocadas = it.harness.playback.played.length;

      await _entrar(it);
      expect(it.harness.playback.played.skip(tocadas), [segunda.path]);

      await ouvirAteOFim(it, _cincoPartes[1]);
      expect(
        it.estado.btParteFronteira,
        isTrue,
        reason: 'falta a quarta: a travessia leva a ela',
      );
      it.sala.ouvirGravacao();
      await waitFor(
        'a próxima parte não ouvida entrar no ar',
        () => it.harness.playback.played.length == tocadas + 2,
      );
      expect(
        it.harness.playback.played.skip(tocadas),
        [segunda.path, quarta.path],
        reason: 'a travessia pula a terceira, já ouvida, para a quarta',
      );
      expect(it.harness.playback.playedFrom.last, Duration.zero);

      await ouvirAteOFim(it, _cincoPartes[3]);
      expect(it.estado.canFinishBackTranslation, isTrue);
      expect(
        it.estado.btParteFronteira,
        isFalse,
        reason: 'a quinta já foi ouvida: depois da última que faltava, para',
      );
    },
  );

  test(
    'uma passagem de uma parte gravada de novo ouve a abertura e a gravação inteira',
    () async {
      const umaParte = [Duration(seconds: 10)];
      final it = await umEnsaioContadoInteiro(umaParte);
      await _regravada(it, 0, umaParte[0], semNome: true);
      it.harness.room.listeningUnheardTakeIds = const [];
      final linhas = it.harness.voice.fixedLines.length;
      final tocadas = it.harness.playback.played.length;

      await _entrar(it);

      expect(
        _linhas(it, linhas),
        ['P0'],
        reason:
            'nenhuma parte segue ouvida: a abertura e a gravação inteira, '
            'não a P2',
      );
      expect(it.harness.playback.played.skip(tocadas), [it.partes[0].path]);
      expect(it.harness.playback.playedFrom.last, Duration.zero);
    },
  );

  test(
    'todas as partes não ouvidas de novo ouvem a abertura e a gravação inteira',
    () async {
      final it = await umEnsaioDeTresPartesContadoInteiro();
      await _regravada(it, 1, partesDoEnsaio[1]);
      it.harness.room.listeningUnheardTakeIds = [
        for (final parte in it.partes) parte.takeId!,
      ];
      final linhas = it.harness.voice.fixedLines.length;
      final tocadas = it.harness.playback.played.length;
      final desde = it.harness.playback.playedFrom.length;

      await _entrar(it);
      expect(_linhas(it, linhas), ['P0']);
      expect(it.harness.playback.played.skip(tocadas), [it.partes[0].path]);

      await ouvirAteOFim(it, partesDoEnsaio[0]);
      expect(it.estado.btParteFronteira, isTrue);
      it.sala.ouvirGravacao();
      await waitFor(
        'a segunda parte entrar no ar',
        () => it.harness.playback.played.length == tocadas + 2,
      );
      await ouvirAteOFim(it, partesDoEnsaio[1]);
      expect(it.estado.btParteFronteira, isTrue);
      it.sala.ouvirGravacao();
      await waitFor(
        'a terceira parte entrar no ar',
        () => it.harness.playback.played.length == tocadas + 3,
      );

      expect(
        it.harness.playback.played.skip(tocadas),
        [for (final parte in it.partes) parte.path],
        reason: 'a gravação inteira, parte por parte',
      );
      expect(
        it.harness.playback.playedFrom.skip(desde),
        [Duration.zero, Duration.zero, Duration.zero],
        reason:
            'depois da abertura cada parte toca do seu começo: a terceira, já '
            'contada, começava no fim do chão contado, muda, e contava como ouvida',
      );
    },
  );

  test('a abertura também mostra o que falta ouvir', () async {
    final it = await umEnsaioDeTresPartesContadoInteiro();
    await _regravada(it, 1, partesDoEnsaio[1]);
    it.harness.room.listeningUnheardTakeIds = [
      for (final parte in it.partes) parte.takeId!,
    ];
    CheckRefusal? naTelaDuranteAFala;
    it.harness.voice.aoFalar = () => naTelaDuranteAFala = it.estado.btRecusa;

    await _entrar(it);

    expect(
      naTelaDuranteAFala,
      CheckRefusal.partUnheard,
      reason: 'quando algo falta ouvir, a tela diz, com a P0 também',
    );
  });

  test('a sala pedindo uma pessoa no meio do replay não mostra o sinal, e o '
      'relato tem só o que soou', () async {
    final it = await umEnsaioContadoInteiro(
      _cincoPartes,
      numaSala: SalaHarness(watchesWithoutAHalt: true),
    );
    await _regravada(it, 3, _cincoPartes[3]);
    final quarta = it.partes[3];
    it.harness.room.listeningUnheardTakeIds = [quarta.takeId!];
    await _entrar(it);
    await theClipOpens(it.harness);
    it.harness.playback.at = const Duration(seconds: 2);
    final tocadas = it.harness.playback.played.length;
    it.harness.room.serverStatus = 'needs_person';
    final lidas = _leituras(it);
    await waitFor('a sala ler a sessão', () => _leituras(it) > lidas);
    expect(
      it.estado.needsPerson,
      isFalse,
      reason: 'uma leitura nunca levanta o sinal da pessoa',
    );
    expect(
      it.harness.playback.played.length,
      tocadas,
      reason: 'a parte segue no ar, sem ser posta de novo',
    );
    it.harness.playback.at = const Duration(seconds: 3);
    it.sala.ouvirGravacao();
    await waitFor('a parte parar', () => !it.estado.btClipRodando);

    it.sala.theAppWentAway();

    expect(
      it.harness.room.listeningReports.last.where(
        (parte) => parte['take_id'] == quarta.takeId,
      ),
      [
        {
          'take_id': quarta.takeId,
          'played_ranges': [
            [0, 3000],
          ],
          'clip_duration_ms': 0,
        },
      ],
      reason: 'a parte nova soou de nought a 3 s: nada além disso foi ouvido',
    );
  });

  test(
    'o aviso fica enquanto falta tocar uma parte nomeada e sai depois da última',
    () async {
      final it = await umEnsaioContadoInteiro(_cincoPartes);
      await _regravada(it, 1, _cincoPartes[1]);
      final quarta = it.partes[3];
      it.harness.room.listeningUnheardTakeIds = [
        it.partes[1].takeId!,
        quarta.takeId!,
      ];
      await _entrar(it);

      await ouvirETraduzirAParteInteira(it, _cincoPartes[1]);
      expect(
        it.estado.btRecusa,
        CheckRefusal.partUnheard,
        reason: 'contar a segunda não ouve a quarta: o aviso fica',
      );
      expect(it.estado.btParteFronteira, isTrue);

      it.sala.ouvirGravacao();
      await waitFor(
        'a quarta entrar no ar',
        () => it.harness.playback.played.last == quarta.path,
      );
      expect(it.estado.btRecusa, CheckRefusal.partUnheard);

      await ouvirAteOFim(it, _cincoPartes[3]);
      expect(
        it.estado.btRecusa,
        isNull,
        reason: 'tocada a última que faltava, o aviso sai',
      );
    },
  );

  testWidgets(
    'a tela mostra «ainda falta ouvir um trecho da gravação» enquanto a P2 '
    'soa',
    (tester) async {
      late Sala it;
      await tester.runAsync(() async {
        it = await umEnsaioContadoInteiro(
          _cincoPartes,
          numaSala: SalaHarness(filaEmMemoria: true),
        );
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: it.container,
          child: const SalaApp(),
        ),
      );
      await tester.runAsync(() async {
        await _regravada(it, 2, _cincoPartes[2]);
        it.harness.room.listeningUnheardTakeIds = [it.partes[2].takeId!];
        it.harness.voice.holdNextLine();
        it.sala.startRetro();
        await waitFor(
          'a P2 começar',
          () => it.harness.voice.fixedLines.any((linha) => linha.$1 == 'P2'),
        );
      });
      await tester.pump();

      expect(
        find.text('ainda falta ouvir um trecho da gravação'),
        findsOneWidget,
      );
      it.harness.voice.finishHeldLine();
      closeTheRoom(it.container);
    },
  );

  test(
    'uma sala antiga que não nomeia nada mantém o caminho de hoje',
    () async {
      final it = await umEnsaioContadoInteiro(_cincoPartes);
      await _regravada(it, 2, _cincoPartes[2], semNome: true);
      it.harness.room.listeningUnheardTakeIds = null;
      final linhas = it.harness.voice.fixedLines.length;
      final tocadas = it.harness.playback.played.length;

      await _entrar(it);

      expect(
        _linhas(it, linhas),
        isEmpty,
        reason: 'sem resposta da sala, o tablet não conta sozinho nem fala',
      );
      expect(it.estado.btRecusa, isNull);
      expect(
        it.harness.playback.played.skip(tocadas),
        [it.partes[2].path],
        reason:
            'o caminho de hoje começa no primeiro chão que ninguém contou, '
            'que é a parte gravada de novo',
      );
    },
  );

  test(
    'uma cena gravada de novo no ensaio antes da primeira entrada deixa a entrada como hoje',
    () async {
      final it = await umEnsaioDeTresPartesGravado();
      final antiga = it.partes[1].path;
      it.sala.gravarACena(2);
      await waitFor(
        'a cena 2 gravar',
        () => it.estado.ensaio == EnsaioStatus.recording,
      );
      it.sala.gravarACena(2);
      await waitFor(
        'a cena 2 ficar pendente',
        () => it.estado.ensaio == EnsaioStatus.recorded,
      );
      it.sala.takeKeep();
      await waitFor(
        'a cena 2 nova tomar o lugar da parte 2 e ganhar nome',
        () => it.partes[1].path != antiga && it.partes[1].takeId != null,
      );
      it.harness.playback.lengths[it.partes[1].path] = partesDoEnsaio[1];
      it.harness.room.listeningUnheardTakeIds = [
        for (final parte in it.partes) parte.takeId!,
      ];
      final linhas = it.harness.voice.fixedLines.length;
      final tocadas = it.harness.playback.played.length;

      await _entrar(it);

      expect(
        _linhas(it, linhas),
        isEmpty,
        reason: 'a primeira entrada fica intacta: nem P2, nem P0',
      );
      expect(it.harness.playback.played.skip(tocadas), [it.partes[0].path]);
    },
  );

  test(
    'depois de uma retomada que caiu na tradução, a parte gravada de novo toca sozinha depois da P2',
    () async {
      final it = await umEnsaioDeTresPartesContadoInteiro();
      it.container.dispose();
      it.container = it.harness.container();
      addTearDown(it.container.dispose);
      await it.sala.abrirEscolha();
      await it.sala.goConversa(book: 'Ruth', pericope: 'P01');
      await waitFor(
        'a retomada cair na tradução',
        () =>
            it.estado.stage == SalaStage.retro &&
            it.estado.btPhase == BtPhase.playing &&
            it.harness.playback.sounding,
      );
      await ouvirAteOFim(it, partesDoEnsaio[2]);
      await _regravada(it, 1, partesDoEnsaio[1]);
      final segunda = it.partes[1];
      it.harness.room.listeningUnheardTakeIds = [segunda.takeId!];
      final linhas = it.harness.voice.fixedLines.length;
      final tocadas = it.harness.playback.played.length;

      await _entrar(it);

      expect(_linhas(it, linhas), ['P2']);
      expect(it.harness.playback.played.skip(tocadas), [segunda.path]);
    },
  );

  test('a primeira entrada na tradução não diz linha nova', () async {
    final it = await umEnsaioDeTresPartesGravado();
    it.harness.room.listeningUnheardTakeIds = [
      for (final parte in it.partes) parte.takeId!,
    ];
    final linhas = it.harness.voice.fixedLines.length;
    final tocadas = it.harness.playback.played.length;

    await _entrar(it);

    expect(_linhas(it, linhas), isEmpty);
    expect(it.harness.playback.played.skip(tocadas), [it.partes[0].path]);
  });

  test(
    'uma recusa que nomeia duas partes não ouvidas toca as duas em ordem e para',
    () async {
      final it = await umEnsaioDeTresPartesContadoInteiro();
      final primeira = it.partes[0];
      final terceira = it.partes[2];
      it.harness.room
        ..verdictChecked = false
        ..verdictUnheardTakeIds = [terceira.takeId!, primeira.takeId!];
      final tocadas = it.harness.playback.played.length;

      await pedirOVeredito(it);
      expect(it.harness.playback.played.skip(tocadas), [primeira.path]);

      await ouvirAteOFim(it, partesDoEnsaio[0]);
      expect(
        it.estado.btParteFronteira,
        isTrue,
        reason: 'falta a terceira: a travessia leva a ela',
      );
      expect(
        it.estado.canFinishBackTranslation,
        isFalse,
        reason: 'ainda falta uma parte: terminei não acende no meio',
      );
      it.sala.ouvirGravacao();
      await waitFor(
        'a terceira parte entrar no ar',
        () => it.harness.playback.played.length == tocadas + 2,
      );
      expect(
        it.harness.playback.played.skip(tocadas),
        [primeira.path, terceira.path],
        reason: 'a travessia pula a segunda, já ouvida',
      );

      await ouvirAteOFim(it, partesDoEnsaio[2]);
      expect(it.estado.canFinishBackTranslation, isTrue);
      expect(it.estado.btParteFronteira, isFalse);
    },
  );
}
