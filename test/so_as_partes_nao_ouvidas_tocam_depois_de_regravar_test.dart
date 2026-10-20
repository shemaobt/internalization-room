import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'um_ensaio_de_tres_partes.dart';

const _cincoPartes = [
  Duration(seconds: 10),
  Duration(seconds: 8),
  Duration(seconds: 12),
  Duration(seconds: 6),
  Duration(seconds: 9),
];

/// A rehearsal of [partes], every part told back whole and played to its end: every part
/// heard, the room standing with «terminei» lit.
Future<Sala> _contadoInteiro(List<Duration> partes) async {
  final harness = SalaHarness();
  final container = harness.container();
  addTearDown(container.dispose);
  final it = Sala(harness, container);

  await it.sala.goConversa(book: 'Ruth', pericope: 'P01');
  await waitFor('a sala abrir', () => it.estado.sessionId != null);
  it.sala.goEnsaio();
  for (var onde = 0; onde < partes.length; onde++) {
    await gravarUmaParteDoEnsaio(it);
  }
  for (var onde = 0; onde < partes.length; onde++) {
    harness.playback.lengths[it.partes[onde].path] = partes[onde];
  }
  it.sala.startRetro();
  await waitFor(
    'a tradução começar a tocar a primeira parte',
    () =>
        it.estado.stage == SalaStage.retro &&
        it.estado.btPhase == BtPhase.playing,
  );
  for (var onde = 0; onde < partes.length; onde++) {
    await ouvirETraduzirAParteInteira(it, partes[onde]);
    if (onde < partes.length - 1) {
      it.sala.ouvirGravacao();
      await waitFor(
        'a parte seguinte entrar no ar',
        () => !it.estado.btParteFronteira,
      );
    }
  }
  return it;
}

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

Future<void> _ateOFim(Sala it, Duration quanto) async {
  await theClipOpens(it.harness);
  it.harness.playback
    ..length = quanto
    ..at = quanto
    ..finishPlayback();
  await waitFor(
    'a parte acabar',
    () => it.estado.btParteFronteira || it.estado.btClipEnded,
  );
}

List<String> _linhas(Sala it, int desde) => [
  for (final (linha, _) in it.harness.voice.fixedLines.skip(desde)) linha,
];

void main() {
  test(
    'a parte gravada de novo numa passagem de cinco toca sozinha depois da fala dela',
    () async {
      final it = await _contadoInteiro(_cincoPartes);
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

      await _ateOFim(it, _cincoPartes[2]);

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

  test('a tela diz o que falta ouvir enquanto a fala dela soa', () async {
    final it = await _contadoInteiro(_cincoPartes);
    await _regravada(it, 2, _cincoPartes[2]);
    it.harness.room.listeningUnheardTakeIds = [it.partes[2].takeId!];
    CheckRefusal? naTelaDuranteAFala;
    it.harness.voice.aoFalar = () => naTelaDuranteAFala = it.estado.btRecusa;

    await _entrar(it);

    expect(
      naTelaDuranteAFala,
      CheckRefusal.partUnheard,
      reason:
          'a tela mostra «ainda falta ouvir um trecho da gravação» '
          'enquanto a P2 soa: a voz não é o único sinal',
    );
  });

  test(
    'duas partes não ouvidas tocam em ordem e nunca seguem para uma já ouvida',
    () async {
      final it = await _contadoInteiro(_cincoPartes);
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

      await _ateOFim(it, _cincoPartes[1]);
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

      await _ateOFim(it, _cincoPartes[3]);
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
      final it = await _contadoInteiro(umaParte);
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

      await _entrar(it);
      expect(_linhas(it, linhas), ['P0']);
      expect(it.harness.playback.played.skip(tocadas), [it.partes[0].path]);

      await _ateOFim(it, partesDoEnsaio[0]);
      expect(it.estado.btParteFronteira, isTrue);
      it.sala.ouvirGravacao();
      await waitFor(
        'a segunda parte entrar no ar',
        () => it.harness.playback.played.length == tocadas + 2,
      );
      await _ateOFim(it, partesDoEnsaio[1]);
      expect(it.estado.btParteFronteira, isTrue);
      it.sala.ouvirGravacao();
      await waitFor(
        'a terceira parte entrar no ar',
        () => it.harness.playback.played.length == tocadas + 3,
      );

      expect(
        it.harness.playback.played.skip(tocadas),
        [for (final parte in it.partes) parte.path],
        reason: 'a gravação inteira, parte por parte, como hoje',
      );
    },
  );

  test(
    'uma sala antiga que não nomeia nada mantém o caminho de hoje',
    () async {
      final it = await _contadoInteiro(_cincoPartes);
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

      await _ateOFim(it, partesDoEnsaio[0]);
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

      await _ateOFim(it, partesDoEnsaio[2]);
      expect(it.estado.canFinishBackTranslation, isTrue);
      expect(it.estado.btParteFronteira, isFalse);
    },
  );
}
