import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'scenario_helpers.dart'
    show holdTheSession, intoTheBackTranslation, intoTheRecordingHome, settle;
import 'um_ensaio_de_tres_partes.dart';

const _cincoPartes = [
  Duration(seconds: 10),
  Duration(seconds: 8),
  Duration(seconds: 12),
  Duration(seconds: 6),
  Duration(seconds: 9),
];

/// The part at [onde] recorded again the way ADR 0020 has it, through a finding on it,
/// and kept.
Future<void> _regravada(Sala it, int onde, Duration quanto) async {
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
  it.sala.leaveTheBackTranslation();
  await regravarAParte(it, onde);
  await waitFor(
    'a sala nomear a parte gravada de novo',
    () => it.partes[onde].takeId != null,
  );
  it.harness.playback.lengths[it.partes[onde].path] = quanto;
  it.harness.room
    ..verdictHasFinding = false
    ..verdictFindingPlace = null;
}

/// The part at [onde] recorded again and kept, landed in the room while the app was
/// closed: killed before the tablet learned its name, and the room's listing fails on the
/// resume and again on the home, so the part comes back to the recording home nameless
/// and off the Outbox (ADR 0163).
Future<void> _regravadaSemNome(Sala it, int onde, Duration quanto) async {
  it.harness.room
    ..verdictChecked = false
    ..verdictHasFinding = true
    ..verdictFindingPlace = onde;
  await pedirOVeredito(it);
  it.harness.room.holdNextTake('parte-${onde + 1}');
  it.sala.leaveTheBackTranslation();
  await regravarAParte(it, onde);
  await it.harness.room.untilTakeHeld().timeout(const Duration(seconds: 10));
  it.container.dispose();
  it.harness.room
    ..failTakesWith = const NetworkFailed('sem rede')
    ..finishHeldTake();
  await waitFor(
    'a parte chegar à sala com o app fechado',
    () => it.harness.room.takesKept.contains('ensaio/parte-${onde + 1}'),
  );
  await it.harness.takes.writingEnds();
  for (final row in await it.harness.takes.pending()) {
    if (row.scope == 'parte-${onde + 1}') await it.harness.takes.withdraw(row);
  }
  it.container = it.harness.container();
  addTearDown(it.container.dispose);
  await it.sala.refreshUnsent();
  await it.sala.openTheRoom();
  await intoTheRecordingHome(it.sala, () => it.estado);
  await settle();
  expect(it.partes[onde].takeId, isNull, reason: 'a parte volta sem nome');
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

Future<void> _retomadaJuntada(
  Sala it,
  Duration ultima, {
  Set<int>? juntas,
}) async {
  for (final MapEntry(:key, :value)
      in it.harness.emAberto.rows.entries.toList()) {
    it.harness.emAberto.rows[key] = ResumePoint(
      sessionId: value.sessionId,
      stage: value.stage,
      takes: [
        for (final (onde, take) in value.takes.indexed)
          KeptTake(
            scopeId: take.scopeId,
            path: take.path,
            takeId: take.takeId,
            pass: take.pass,
            origin: juntas == null || juntas.contains(onde)
                ? 'ensaio-da-cena-${onde + 1}'
                : null,
          ),
      ],
      savedAt: value.savedAt,
      language: value.language,
      passesToGoAbove: value.passesToGoAbove,
    );
  }
  it.container.dispose();
  await holdTheSession(
    it.harness,
    it.harness.emAberto.rows['Ruth/P01/$testLanguage']!,
  );
  it.container = it.harness.container();
  addTearDown(it.container.dispose);
  await it.sala.openTheRoom();
  await intoTheBackTranslation(it.sala, () => it.estado);
  await waitFor(
    'a retomada cair na tradução',
    () => it.estado.btPhase == BtPhase.playing && it.harness.playback.sounding,
  );
  expect(it.estado.joined, isTrue, reason: 'o cenário é uma gravação juntada');
  await ouvirAteOFim(it, ultima);
}

void main() {
  test(
    'a sala pedindo uma pessoa durante a fala dela não mostra o sinal, e a parte que falta toca e para nela',
    () async {
      final it = await umEnsaioContadoInteiro(
        _cincoPartes,
        numaSala: SalaHarness(watchesWithoutAHalt: true),
      );
      await _retomadaJuntada(it, _cincoPartes[4]);
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

      it.harness.room.listeningUnheardTakeIds = const [];
      await ouvirAteOFim(it, _cincoPartes[2]);
      await waitFor(
        'a sala contar a parte ouvida',
        () => it.estado.canFinishBackTranslation,
      );

      expect(
        it.estado.btParteFronteira,
        isFalse,
        reason: 'a quarta parte já foi ouvida: o replay para na que faltava',
      );
      expect(it.estado.canFinishBackTranslation, isTrue);
    },
  );

  test(
    'duas partes não ouvidas tocam em ordem sem toque e nunca seguem para uma já ouvida',
    () async {
      final it = await umEnsaioContadoInteiro(_cincoPartes);
      await _retomadaJuntada(it, _cincoPartes[4]);
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

      await theClipOpens(it.harness);
      it.harness.playback
        ..length = _cincoPartes[1]
        ..at = _cincoPartes[1]
        ..finishPlayback();
      await settle();
      expect(
        it.harness.playback.played.skip(tocadas),
        [segunda.path, quarta.path],
        reason:
            'a segunda acabava calada, esperando um toque para seguir à quarta',
      );
      expect(it.estado.btClipRodando, isTrue);
      expect(it.harness.playback.playedFrom.last, Duration.zero);

      it.harness.room.listeningUnheardTakeIds = const [];
      await ouvirAteOFim(it, _cincoPartes[3]);
      await waitFor(
        'a sala contar as partes ouvidas',
        () => it.estado.canFinishBackTranslation,
      );
      expect(it.estado.canFinishBackTranslation, isTrue);
      expect(
        it.estado.btParteFronteira,
        isFalse,
        reason: 'a quinta já foi ouvida: depois da última que faltava, para',
      );
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
      await waitFor(
        'a segunda parte entrar no ar',
        () => it.harness.playback.played.length == tocadas + 2,
      );
      await ouvirAteOFim(it, partesDoEnsaio[1]);
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

  test(
    'on a recording no join touched, a part recorded again brings P-start and the whole recording from its first part, not P-unheard',
    () async {
      final it = await umEnsaioDeTresPartesContadoInteiro();
      await _regravada(it, 1, partesDoEnsaio[1]);
      it.harness.room.listeningUnheardTakeIds = [it.partes[1].takeId!];
      final linhas = it.harness.voice.fixedLines.length;
      final tocadas = it.harness.playback.played.length;
      final desde = it.harness.playback.playedFrom.length;

      await _entrar(it);
      expect(
        _linhas(it, linhas),
        ['P0'],
        reason:
            'só a segunda faltava ouvir, e a sala dizia a P2 e tocava só ela; '
            'numa gravação sem junção a dela diz a P-start e toca tudo',
      );
      expect(it.harness.playback.played.skip(tocadas), [it.partes[0].path]);

      await ouvirAteOFim(it, partesDoEnsaio[0]);
      it.sala.ouvirGravacao();
      await waitFor(
        'a segunda parte entrar no ar',
        () => it.harness.playback.played.length == tocadas + 2,
      );
      await ouvirAteOFim(it, partesDoEnsaio[1]);
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
      expect(it.harness.playback.playedFrom.skip(desde), [
        Duration.zero,
        Duration.zero,
        Duration.zero,
      ]);
    },
  );

  test(
    'on a recording no join touched, a part recorded again and heard brings P1 and the recording again from its first part, not the end of the listen',
    () async {
      final it = await umEnsaioDeTresPartesContadoInteiro();
      await _regravada(it, 1, partesDoEnsaio[1]);
      it.harness.room.listeningUnheardTakeIds = [it.partes[1].takeId!];
      final linhas = it.harness.voice.fixedLines.length;
      final tocadas = it.harness.playback.played.length;

      await _entrar(it);
      for (var onde = 0; onde < 2; onde++) {
        await ouvirAteOFim(it, partesDoEnsaio[onde]);
        await waitFor(
          'a parte ${onde + 2} entrar no ar',
          () => it.harness.playback.played.length == tocadas + onde + 2,
        );
      }
      it.harness.room.listeningUnheardTakeIds = const [];
      await ouvirAteOFim(it, partesDoEnsaio[2]);
      await waitFor(
        'a primeira parte voltar ao ar',
        () => it.harness.playback.played.length == tocadas + 4,
      );

      expect(
        _linhas(it, linhas),
        ['P0', 'P1'],
        reason:
            'a escuta acabava em silêncio, com o terminei aceso, e a P1 nunca '
            'era dita',
      );
      expect(
        it.harness.playback.played.skip(tocadas),
        [
          for (final onde in [0, 1, 2, 0]) it.partes[onde].path,
        ],
        reason: 'depois da P1 a gravação volta à primeira parte',
      );
      expect(it.harness.playback.playedFrom.last, Duration.zero);
    },
  );

  test(
    'on a recording no join touched, the listen after a part recorded again shows nothing left to hear, as hers clears the line',
    () async {
      final it = await umEnsaioDeTresPartesContadoInteiro();
      await _regravada(it, 1, partesDoEnsaio[1]);
      it.harness.room.listeningUnheardTakeIds = [
        for (final parte in it.partes) parte.takeId!,
      ];
      CheckRefusal? naTelaDuranteAFala = CheckRefusal.partUnheard;
      it.harness.voice.aoFalar = () => naTelaDuranteAFala = it.estado.btRecusa;

      await _entrar(it);

      expect(
        naTelaDuranteAFala,
        isNull,
        reason:
            'pelo disco a escuta dizia «ainda falta ouvir», e pela retomada '
            'não; a dela não diz em nenhuma das duas',
      );
    },
  );

  test(
    'on a recording no join touched, a relaunch after a part recorded again shows nothing left to hear during P0, as the advance disc does',
    () async {
      final it = await umEnsaioDeTresPartesContadoInteiro();
      await _regravada(it, 1, partesDoEnsaio[1]);
      for (final MapEntry(:key, :value)
          in it.harness.emAberto.rows.entries.toList()) {
        it.harness.emAberto.rows[key] = ResumePoint(
          sessionId: value.sessionId,
          stage: SalaStage.retro,
          takes: value.takes,
          savedAt: value.savedAt,
          language: value.language,
        );
      }
      it.harness.room
        ..retroSoFar = BackTranslationProgress(
          segments: [...it.harness.room.segments],
        )
        ..listeningUnheardTakeIds = [
          for (final parte in it.partes) parte.takeId!,
        ];
      CheckRefusal? naTelaDuranteAFala = CheckRefusal.partUnheard;
      it.harness.voice.aoFalar = () => naTelaDuranteAFala = it.estado.btRecusa;
      final linhas = it.harness.voice.fixedLines.length;
      final tocadas = it.harness.playback.played.length;

      it.container.dispose();
      it.container = it.harness.container();
      addTearDown(it.container.dispose);
      await it.sala.abrirEscolha();
      await it.sala.goConversa(book: 'Ruth', pericope: 'P01');
      await intoTheBackTranslation(it.sala, () => it.estado);
      await waitFor(
        'a retomada pôr uma parte no ar',
        () =>
            it.estado.stage == SalaStage.retro &&
            it.harness.playback.played.length > tocadas,
      );

      expect(_linhas(it, linhas), ['P0']);
      expect(
        naTelaDuranteAFala,
        isNull,
        reason: 'a retomada e o disco abrem a mesma escuta, com a mesma tela',
      );
    },
  );

  test('a sala pedindo uma pessoa no meio do replay não mostra o sinal, e o '
      'relato tem só o que soou', () async {
    final it = await umEnsaioContadoInteiro(
      _cincoPartes,
      numaSala: SalaHarness(watchesWithoutAHalt: true),
    );
    await _retomadaJuntada(it, _cincoPartes[4]);
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
    'the listen of only the unheard parts shows no line left to hear while it '
    'crosses into the next named part, not before its end',
    () async {
      final it = await umEnsaioContadoInteiro(_cincoPartes);
      await _retomadaJuntada(it, _cincoPartes[4]);
      await _regravada(it, 1, _cincoPartes[1]);
      final quarta = it.partes[3];
      it.harness.room.listeningUnheardTakeIds = [
        it.partes[1].takeId!,
        quarta.takeId!,
      ];
      await _entrar(it);

      await ouvirAteOFim(it, _cincoPartes[1]);
      expect(
        it.estado.btRecusa,
        isNull,
        reason:
            'a escuta ainda não acabou: a dela só diz o que falta depois da '
            'última parte',
      );

      await waitFor(
        'a quarta entrar no ar sem toque',
        () => it.harness.playback.played.last == quarta.path,
      );
      expect(
        it.estado.btRecusa,
        isNull,
        reason: 'a travessia para a quarta mostrava «ainda falta ouvir»',
      );
    },
  );

  test(
    'a joined entry the room answers with a take this tablet does not hold shows no line left to hear',
    () async {
      final it = await umEnsaioContadoInteiro(_cincoPartes);
      await _retomadaJuntada(it, _cincoPartes[4]);
      await _regravada(it, 1, _cincoPartes[1]);
      it.harness.room.listeningUnheardTakeIds = const ['take-de-outro-tablet'];
      CheckRefusal? naTelaDuranteAFala = CheckRefusal.partUnheard;
      var falou = false;
      it.harness.voice.aoFalar = () {
        falou = true;
        naTelaDuranteAFala = it.estado.btRecusa;
      };

      await _entrar(it);

      expect(falou, isTrue, reason: 'a entrada fala antes de tocar');
      expect(
        naTelaDuranteAFala,
        isNull,
        reason:
            'a entrada falava com «ainda falta ouvir» na tela; a dela limpa a '
            'linha em toda entrada',
      );
      expect(it.estado.btRecusa, isNull);
    },
  );

  testWidgets(
    'entering the listen of only the unheard parts shows no line left to hear '
    'while P2 sounds, as hers clears it on every entry',
    (tester) async {
      late Sala it;
      await tester.runAsync(() async {
        it = await umEnsaioContadoInteiro(
          _cincoPartes,
          numaSala: SalaHarness(filaEmMemoria: true),
        );
        await _retomadaJuntada(it, _cincoPartes[4]);
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
        findsNothing,
        reason:
            'a entrada já mostrava «ainda falta ouvir» enquanto a P2 soava; a '
            'dela limpa a linha em toda entrada',
      );
      it.harness.voice.finishHeldLine();
      closeTheRoom(it.container);
    },
  );

  test(
    'uma sala antiga que não nomeia nada mantém o caminho de hoje',
    () async {
      final it = await umEnsaioContadoInteiro(_cincoPartes);
      await _regravada(it, 2, _cincoPartes[2]);
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
    'uma cena gravada de novo no ensaio antes da primeira entrada deixa a entrada na primeira escuta, não na P2',
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
        ['P0'],
        reason: 'a primeira entrada é a primeira escuta: a P0, nunca a P2',
      );
      expect(it.harness.playback.played.skip(tocadas), [it.partes[0].path]);
    },
  );

  test(
    'on a joined recording picked back up, a part recorded again plays alone after P-unheard',
    () async {
      final it = await umEnsaioDeTresPartesContadoInteiro();
      await _retomadaJuntada(it, partesDoEnsaio[2]);
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

  test(
    'a joined recording whose only joined part is recorded again by hand is one no join touched, so P-start and the whole recording',
    () async {
      final it = await umEnsaioDeTresPartesContadoInteiro();
      await _retomadaJuntada(it, partesDoEnsaio[2], juntas: {1});
      await _regravada(it, 1, partesDoEnsaio[1]);
      it.harness.room.listeningUnheardTakeIds = [it.partes[1].takeId!];
      final linhas = it.harness.voice.fixedLines.length;
      final tocadas = it.harness.playback.played.length;

      await _entrar(it);

      expect(it.estado.joined, isFalse);
      expect(
        _linhas(it, linhas),
        ['P0'],
        reason:
            'a parte gravada à mão não é mais juntada, na dela também '
            '(join.ts:70): a gravação deixa de ser juntada e ouve-se inteira',
      );
      expect(it.harness.playback.played.skip(tocadas), [it.partes[0].path]);
    },
  );

  test('a primeira entrada na tradução diz a P0, não a P2', () async {
    final it = await umEnsaioDeTresPartesGravado();
    it.harness.room.listeningUnheardTakeIds = [
      for (final parte in it.partes) parte.takeId!,
    ];
    final linhas = it.harness.voice.fixedLines.length;
    final tocadas = it.harness.playback.played.length;

    await _entrar(it);

    expect(_linhas(it, linhas), ['P0']);
    expect(it.harness.playback.played.skip(tocadas), [it.partes[0].path]);
  });
  test(
    'uma passagem de uma parte gravada de novo ouve a abertura e a gravação inteira',
    () async {
      const umaParte = [Duration(seconds: 10)];
      final it = await umEnsaioContadoInteiro(umaParte);
      await _regravadaSemNome(it, 0, umaParte[0]);
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
    'a parte gravada de novo numa passagem de cinco toca sozinha depois da fala dela',
    () async {
      final it = await umEnsaioContadoInteiro(_cincoPartes);
      await _retomadaJuntada(it, _cincoPartes[4]);
      await _regravadaSemNome(it, 2, _cincoPartes[2]);
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
    },
  );

  test(
    'numa gravação juntada, a parte cujo nome o tablet não aprendeu segue por ouvir depois de tocada',
    () async {
      final it = await umEnsaioContadoInteiro(_cincoPartes);
      await _retomadaJuntada(it, _cincoPartes[4]);
      await _regravadaSemNome(it, 2, _cincoPartes[2]);
      it.harness.room.listeningUnheardTakeIds = const [];
      await _entrar(it);
      final relatos = it.harness.room.listeningReports.length;

      await ouvirAteOFim(it, _cincoPartes[2]);
      await waitFor(
        'o relato da parte',
        () => it.harness.room.listeningReports.length > relatos,
      );
      await settle();

      expect(
        it.estado.canFinishBackTranslation,
        isFalse,
        reason: 'a sala não pode contar ouvida uma parte que ainda não nomeou',
      );
      expect(it.estado.btRecusa, CheckRefusal.partUnheard);
    },
  );

  test('a part landed without this tablet learning its name keeps the listen '
      'before a frase that awaits, even when the room names only that frase\'s '
      'take', () async {
    final it = await umEnsaioDeTresPartesContadoInteiro();
    final daPrimeira = it.estado.btTrechos.firstWhere(
      (trecho) => trecho.parte == 0,
    );
    it.harness.room
      ..awaitingSegmentId = daPrimeira.segmentId
      ..verdictChecked = false
      ..verdictRefusal = CheckRefusal.fraseAwaiting
      ..verdictUntoldSegmentId = daPrimeira.segmentId;
    await pedirOVeredito(it);
    it.harness.room
      ..verdictRefusal = null
      ..verdictUntoldSegmentId = null;
    await _regravadaSemNome(it, 1, partesDoEnsaio[1]);
    expect(it.estado.btFraseQueAguarda, daPrimeira.segmentId);
    expect(it.partes[1].takeId, isNull);
    it.harness.room.listeningUnheardTakeIds = [it.partes[0].takeId!];
    final linhas = it.harness.voice.fixedLines.length;

    it.sala.startRetro();
    await waitFor(
      'a voz dizer o que vem',
      () => it.harness.voice.fixedLines.length > linhas,
    );

    expect(
      _linhas(it, linhas).first,
      'P0',
      reason:
          'a volta pulava a escuta da parte que ainda subia e abria a '
          'frase que espera',
    );
  });
}
