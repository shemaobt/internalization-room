import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'session_notifier_test.dart' show inConversa, settle;
import 'playback_ceiling_test.dart' show gravaParte;
import 'tocar_vira_pausar_test.dart' show harnessApontando, pumpAoApontado;

/// What the room does that a team can hear, and what it does to go quiet. A gesture that
/// moves the room has to do the second before the first.
const _fazemSom = {
  'playback:play',
  'voice:line',
  'voice:asset',
  'recorder:start',
};

/// The room went quiet before its next sound.
///
/// Read off one ordered log both players and the recorder write to, so no double has to
/// read another — and off the order, never off which private method ran.
void aSalaSeCalouPrimeiro(
  List<String> desde,
  String linha, {
  bool segurando = false,
}) {
  final calandoOEnsaio = segurando ? 'playback:pause' : 'playback:stop';
  expect(desde, contains(calandoOEnsaio),
      reason: '$linha: o gesto move a sala e o ensaio ficou tocando por baixo '
          'do que veio depois');
  expect(desde, contains('voice:stop'),
      reason: '$linha: a voz da Guia ficou falando por baixo do gesto');

  final primeiroSom = desde.indexWhere(_fazemSom.contains);
  if (primeiroSom < 0) return;
  expect(desde.indexOf(calandoOEnsaio), lessThan(primeiroSom),
      reason: '$linha: a sala calou o ensaio depois de já ter começado '
          '${desde[primeiroSom]} — os dois se sobrepõem');
  expect(desde.indexOf('voice:stop'), lessThan(primeiroSom),
      reason: '$linha: a sala calou a Guia depois de já ter começado '
          '${desde[primeiroSom]}');
}

typedef _Cena = ({
  SalaHarness harness,
  ProviderContainer container,
  SalaSessionNotifier sala,
});

typedef _Linha = ({
  String nome,
  Future<_Cena> Function() arranjo,
  Future<void> Function(_Cena) gesto,
  bool segurando,
});

_Linha _linha(
  String nome,
  Future<_Cena> Function() arranjo,
  Future<void> Function(_Cena) gesto, {
  bool segurando = false,
}) =>
    (nome: nome, arranjo: arranjo, gesto: gesto, segurando: segurando);

_Cena _cena(SalaHarness harness, ProviderContainer container) => (
      harness: harness,
      container: container,
      sala: container.read(salaSessionProvider.notifier),
    );

SalaSessionState _estado(_Cena cena) => cena.container.read(salaSessionProvider);

/// A rehearsal of one part, told back nothing yet, with the part in the air.
Future<_Cena> _noRetro({int partes = 1}) async {
  final harness = SalaHarness(clipGrace: const Duration(milliseconds: 200))
    ..playback.length = const Duration(milliseconds: 600);
  final container = await inConversa(harness);
  addTearDown(container.dispose);
  final cena = _cena(harness, container);
  cena.sala.goEnsaio();
  for (var feita = 0; feita < partes; feita++) {
    await gravaParte(container, cena.sala);
  }
  cena.sala.startRetro();
  await waitFor('a parte entrar no ar', () => _estado(cena).btClipRodando);
  return cena;
}

/// A rehearsal recorded and offered, with the take still pending: the one state the
/// listen/redo/keep gestures live in.
Future<_Cena> _comATomadaNaMao() async {
  final harness = SalaHarness();
  final container = await inConversa(harness);
  addTearDown(container.dispose);
  final cena = _cena(harness, container);
  cena.sala.goEnsaio();
  cena.sala.ensaioTap();
  cena.sala.ensaioTap();
  await waitFor(
    'a tomada ser oferecida',
    () => _estado(cena).ensaio == EnsaioStatus.recorded,
  );
  return cena;
}

/// The findings screen with the analyst's pointer on a stretch the tablet holds.
Future<_Cena> _nosAchados() async {
  final harness = harnessApontando();
  final container = await pumpAoApontado(harness);
  addTearDown(container.dispose);
  return _cena(harness, container);
}

/// A telling-back with one stretch told and the clip ended: the door *terminei* opens.
Future<_Cena> _prontoParaTerminei() async {
  final cena = await _noRetro();
  cena.harness.playback.at = const Duration(milliseconds: 40);
  cena.sala.cortarTrecho();
  await settle();
  cena.sala.retroTap();
  await waitFor(
    'o trecho chegar à sala',
    () => cena.harness.room.chunksSent == 1,
  );
  cena.harness.playback.at = const Duration(milliseconds: 600);
  cena.harness.playback.finishPlayback();
  await waitFor(
    'o clipe poder ser dado por ouvido',
    () => _estado(cena).canFinishBackTranslation,
  );
  return cena;
}

Future<_Cena> _naRoda() async {
  final harness = SalaHarness();
  final container = harness.container();
  addTearDown(container.dispose);
  final cena = _cena(harness, container);
  await cena.sala.abrirEscolha();
  await waitFor('a roda carregar', () => _estado(cena).naRoda != null);
  await settle();
  return cena;
}

void _rodaATabela(String estacao, List<_Linha> tabela, List<String> daMatriz) {
  group(estacao, () {
    for (final linha in tabela) {
      test(linha.nome, () async {
        final cena = await linha.arranjo();
        final marca = cena.harness.sounds.length;

        await linha.gesto(cena);

        aSalaSeCalouPrimeiro(
          cena.harness.sounds.sublist(marca),
          linha.nome,
          segurando: linha.segurando,
        );
      });
    }

    test('nenhum gesto da matriz do ticket ficou de fora', () {
      expect(
        [for (final linha in tabela) linha.nome]..sort(),
        [...daMatriz]..sort(),
        reason: 'uma transição que sai da tabela é uma transição que volta a '
            'tocar por cima da próxima: a matriz do ticket é o contrato',
      );
    });
  });
}

/// The back-translation's gestures, copied from the ticket's matrix.
const _matrizDaRetro = [
  'a aprovação',
  'terminei',
  'o círculo, capturando',
  'o círculo, nos achados',
  'a próxima parte',
  'atravessar para a próxima parte',
  'ouvir a voz materna',
  'ouvir a tradução em português',
  'traduzir de novo, na grade',
  'recontar o pedaço',
  'traduzir de novo, do cordão',
  'dividir o trecho',
  'dividir sem nada que dividir',
  'cortar o trecho',
  'cortar com a cabeça atrás do cursor',
  'a parte não ouvida',
  'o trecho não contado',
  'a parte que não tocou volta ao ensaio',
  'deixar a passagem',
  'continuar o ensaio',
  'gravar a parte de novo',
  'gravar a parte de novo, sem parte',
];

const _matrizDoEnsaio = [
  'abrir o microfone',
  'gravar a tomada de novo',
  'ir para o ensaio',
  'começar o retro',
];

const _matrizDaConversaEDaRoda = [
  'abrir o microfone na conversa',
  'arrastar a régua da roda',
  'abrir a roda',
  'entrar na passagem oferecida',
];

void main() {
  _rodaATabela(
    'a retro se cala antes de mudar',
    [
      _linha('a aprovação', () async {
        final cena = await _prontoParaTerminei();
        await cena.sala.finishBackTranslation();
        await waitFor(
          'o veredito limpo chegar',
          () => _estado(cena).btPhase == BtPhase.conferida,
        );
        cena.sala.ouvirGravacao();
        await waitFor(
          'a última escuta tocar',
          () => cena.harness.playback.sounding,
        );
        return cena;
      }, (cena) async {
        await cena.sala.aprovarRascunhoFinal();
        await settle();
      }),
      _linha('terminei', _prontoParaTerminei, (cena) async {
        await cena.sala.finishBackTranslation();
      }),
      _linha('o círculo, capturando', () async {
        final cena = await _noRetro();
        cena.harness.playback.at = const Duration(milliseconds: 40);
        cena.sala.cortarTrecho();
        await waitFor(
          'o microfone abrir',
          () => _estado(cena).btPhase == BtPhase.capturing,
        );
        return cena;
      }, (cena) async {
        cena.sala.retroTap();
        await waitFor(
          'o pedaço chegar à sala',
          () => cena.harness.room.chunksSent == 1,
        );
        await settle();
      }, segurando: true),
      _linha('o círculo, nos achados', () async {
        final cena = await _nosAchados();
        cena.sala.ouvirVozMaterna();
        await waitFor(
          'o trecho apontado tocar',
          () => _estado(cena).btTrechoTocando,
        );
        return cena;
      }, (cena) async {
        cena.sala.retroTap();
        await settle();
      }),
      _linha('a próxima parte', () async {
        final cena = await _noRetro(partes: 2);
        cena.harness.playback.at = const Duration(milliseconds: 600);
        cena.harness.playback.finishPlayback();
        await waitFor(
          'a fronteira da parte abrir',
          () => _estado(cena).btParteFronteira,
        );
        return cena;
      }, (cena) async {
        cena.sala.proximaParte();
        await settle();
      }),
      _linha('atravessar para a próxima parte', () async {
        final cena = await _noRetro(partes: 2);
        cena.harness.playback.at = const Duration(milliseconds: 600);
        cena.harness.playback.finishPlayback();
        await waitFor(
          'a fronteira da parte abrir',
          () => _estado(cena).btParteFronteira,
        );
        return cena;
      }, (cena) async {
        // O gesto que a tela realmente tem: proximaParte não é chamado por widget
        // nenhum, e é por aqui que a equipe cruza para a parte seguinte.
        cena.sala.ouvirGravacao();
        await settle();
      }),
      _linha('ouvir a voz materna', () async {
        final cena = await _nosAchados();
        // A Guia no meio de uma linha: é por cima dela que o trecho começava.
        cena.harness.voice.holdNextLine();
        cena.sala.retroTap();
        await waitFor(
          'a Guia começar a repetir o veredito',
          () => cena.harness.sounds.contains('voice:line'),
        );
        return cena;
      }, (cena) async {
        cena.sala.ouvirVozMaterna();
        await settle();
        cena.harness.voice.finishHeldLine();
        await settle();
      }),
      _linha('ouvir a tradução em português', () async {
        final cena = await _nosAchados();
        // A voz materna segurada no meio: a bandeira da pausa ficava de pé e o
        // próximo toque nela retomava por cima da tradução.
        cena.sala.ouvirVozMaterna();
        await waitFor(
          'o trecho apontado tocar',
          () => _estado(cena).btTrechoTocando,
        );
        cena.sala.ouvirVozMaterna();
        await waitFor(
          'a voz materna ficar pausada',
          () => _estado(cena).btTrechoPausada,
        );
        return cena;
      }, (cena) async {
        cena.sala.ouvirTraducaoEmPortugues();
        await settle();
        expect(_estado(cena).btTrechoPausada, isFalse,
            reason: 'a materna pausada não pode continuar de pé por baixo da '
                'tradução: o toque seguinte nela retomaria as duas juntas');
      }),
      _linha('traduzir de novo, na grade', () async {
        final cena = await _nosAchados();
        // Com o trecho no ar: este é o gesto que limpa a bandeira antes de
        // delegar, e sem som a limpeza não mede nada.
        cena.sala.ouvirVozMaterna();
        await waitFor(
          'o trecho apontado tocar',
          () => _estado(cena).btTrechoTocando,
        );
        return cena;
      }, (cena) async {
        cena.sala.traduzirDeNovoEmPortugues();
        await settle();
      }, segurando: true),
      _linha('recontar o pedaço', _nosAchados, (cena) async {
        cena.sala.retellChunk();
        await settle();
      }),
      _linha('traduzir de novo, do cordão', _nosAchados, (cena) async {
        await cena.sala.traduzirDeNovo(_estado(cena).btFindingTrecho!);
        await settle();
      }, segurando: true),
      _linha('dividir o trecho', () async {
        final cena = await _nosAchados();
        cena.sala.ouvirVozMaterna();
        await waitFor(
          'o trecho apontado tocar',
          () => _estado(cena).btTrechoTocando,
        );
        return cena;
      }, (cena) async {
        await cena.sala.dividirTrecho();
        await settle();
      }),
      _linha('dividir sem nada que dividir', () async {
        final cena = await _nosAchados();
        cena.sala.ouvirVozMaterna();
        await waitFor(
          'o trecho apontado tocar',
          () => _estado(cena).btTrechoTocando,
        );
        // A room that comes back with no stretches at all: the division landed nowhere,
        // and the gesture returns above everything it would have changed.
        cena.harness.room.segments.clear();
        return cena;
      }, (cena) async {
        await cena.sala.dividirTrecho();
        await settle();
      }),
      _linha('cortar o trecho', () async {
        final cena = await _noRetro();
        cena.harness.playback.at = const Duration(milliseconds: 40);
        return cena;
      }, (cena) async {
        cena.sala.cortarTrecho();
        await settle();
      }, segurando: true),
      _linha('cortar com a cabeça atrás do cursor', () async {
        final cena = await _prontoParaTerminei();
        // The cursor sits at the last cut; the playhead comes back behind it, which is
        // the one reading the room refuses rather than sending a stretch that ends
        // before it begins.
        cena.harness.playback.at = const Duration(milliseconds: 5);
        return cena;
      }, (cena) async {
        cena.sala.cortarTrecho();
        await settle();
      }, segurando: true),
      _linha('a parte não ouvida', () async {
        final cena = await _prontoParaTerminei();
        final gravacao = _estado(cena).partes.first.takeId!;
        cena.harness.room.verdictUnheardTakeIds = [gravacao];
        return cena;
      }, (cena) async {
        await cena.sala.finishBackTranslation();
        await waitFor(
          'a sala levar a equipe à parte',
          () => _estado(cena).btPhase == BtPhase.playing,
        );
      }),
      _linha('o trecho não contado', () async {
        final cena = await _prontoParaTerminei();
        cena.harness.room
          ..verdictChecked = false
          ..verdictUntoldSegmentId = 'trecho-1';
        return cena;
      }, (cena) async {
        await cena.sala.finishBackTranslation();
        await settle();
      }),
      _linha('a parte que não tocou volta ao ensaio', _noRetro, (cena) async {
        cena.harness.playback.failPlayback();
        await waitFor(
          'a equipe voltar ao ensaio',
          () => _estado(cena).stage == SalaStage.ensaio,
        );
      }),
      _linha('deixar a passagem', _noRetro, (cena) async {
        cena.sala.leaveThePassage();
        await settle();
      }),
      _linha('continuar o ensaio', _nosAchados, (cena) async {
        cena.sala.continuarOEnsaio();
        await settle();
      }),
      _linha('gravar a parte de novo', _nosAchados, (cena) async {
        cena.sala.gravarAParteDeNovo();
        await settle();
      }),
      _linha('gravar a parte de novo, sem parte', () async {
        final cena = await _prontoParaTerminei();
        // A stretch on a recording this tablet is not holding: there is no part to
        // record again, and the room calls a person instead of carrying on.
        cena.harness.room
          ..verdictChecked = false
          ..verdictFindingSegmentId = 'trecho-1'
          ..segments.clear()
          ..segments.add(const SegmentView(
            segmentId: 'trecho-1',
            takeId: 'gravacao-de-outro-tablet',
            startsMs: 0,
            endsMs: 40,
          ));
        await cena.sala.finishBackTranslation();
        await waitFor(
          'a grade abrir',
          () => _estado(cena).btPhase == BtPhase.findings,
        );
        expect(_estado(cena).btFindingTrecho?.parte, -1,
            reason: 'o arranjo só vale se o trecho apontado não tiver parte '
                'neste tablet — senão a linha mede o caminho comum');
        return cena;
      }, (cena) async {
        cena.sala.gravarAParteDeNovo();
        await waitFor(
          'a sala chamar uma pessoa',
          () => _estado(cena).needsPerson,
        );
      }),
    ],
    _matrizDaRetro,
  );

  _rodaATabela(
    'o ensaio se cala antes de mudar',
    [
      _linha('abrir o microfone', () async {
        final cena = await _comATomadaNaMao();
        cena.sala.takeRedo();
        await settle();
        return cena;
      }, (cena) async {
        cena.sala.ensaioTap();
        await waitFor(
          'o microfone abrir',
          () => _estado(cena).ensaio == EnsaioStatus.recording,
        );
      }),
      _linha('gravar a tomada de novo', () async {
        final cena = await _comATomadaNaMao();
        cena.sala.takePlay();
        await waitFor('a tomada tocar', () => _estado(cena).playPing);
        return cena;
      }, (cena) async {
        cena.sala.takeRedo();
        await settle();
      }),
      _linha('ir para o ensaio', _noRetro, (cena) async {
        cena.sala.goEnsaio();
        await settle();
      }),
      _linha('começar o retro', () async {
        final harness = SalaHarness();
        final container = await inConversa(harness);
        addTearDown(container.dispose);
        final cena = _cena(harness, container);
        cena.sala.goEnsaio();
        await gravaParte(container, cena.sala);
        return cena;
      }, (cena) async {
        cena.sala.startRetro();
        await settle();
      }),
    ],
    _matrizDoEnsaio,
  );

  _rodaATabela(
    'a conversa e a roda se calam antes de mudar',
    [
      _linha('abrir o microfone na conversa', () async {
        final harness = SalaHarness();
        final container = await inConversa(harness);
        addTearDown(container.dispose);
        return _cena(harness, container);
      }, (cena) async {
        cena.sala.conversaTap();
        await waitFor(
          'o microfone abrir',
          () => _estado(cena).voice == VoiceState.listening,
        );
      }),
      _linha('arrastar a régua da roda', _naRoda, (cena) async {
        cena.sala.apontarPassagem(1);
        await settle();
      }),
      _linha('abrir a roda', _noRetro, (cena) async {
        await cena.sala.abrirEscolha();
        await settle();
      }),
      _linha('entrar na passagem oferecida', _naRoda, (cena) async {
        cena.sala.entrarNaOferecida();
        await settle();
      }),
    ],
    _matrizDaConversaEDaRoda,
  );

  test('a aprovação cala o ensaio antes da linha aprovada', () async {
    final harness = SalaHarness()..playback.length = const Duration(seconds: 1);
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final cena = _cena(harness, container);

    cena.sala.goEnsaio();
    await gravaParte(container, cena.sala);
    cena.sala.startRetro();
    await waitFor('a parte entrar no ar', () => _estado(cena).btClipRodando);
    harness.playback.finishPlayback();
    await waitFor(
      'o clipe poder ser dado por ouvido',
      () => _estado(cena).canFinishBackTranslation,
    );
    await cena.sala.finishBackTranslation();
    await waitFor(
      'o veredito limpo chegar',
      () => _estado(cena).btPhase == BtPhase.conferida,
    );

    // A última escuta que o veredito limpo convida.
    cena.sala.ouvirGravacao();
    await waitFor('a última escuta tocar', () => harness.playback.sounding);

    final paradasAntes = harness.playback.stops;
    final marca = harness.sounds.length;
    var tocandoQuandoAVozComecou = true;
    harness.voice.aoFalar = () => tocandoQuandoAVozComecou = harness.playback.sounding;

    await cena.sala.aprovarRascunhoFinal();
    await waitFor(
      'a linha aprovada ser dita',
      () => harness.voice.assets.contains(
        fixedLineAsset(approvedLine, testLanguage),
      ),
    );

    expect(harness.playback.stops, paradasAntes + 1,
        reason: 'a aprovação é um gesto que move a sala: o ensaio que a equipe '
            'estava ouvindo tem de parar, não seguir por baixo');
    aSalaSeCalouPrimeiro(harness.sounds.sublist(marca), 'a aprovação');
    expect(tocandoQuandoAVozComecou, isFalse,
        reason: 'nada pode soar por baixo da linha da Marcia');
  });

  test('o dublê do ensaio honra um hold dado enquanto o clipe abre', () async {
    final cena = await _nosAchados();
    cena.harness.playback.holdNextOpening();

    cena.sala.ouvirVozMaterna();
    await settle();
    cena.sala.ouvirVozMaterna();
    await settle();

    cena.harness.playback.finishHeldOpening();
    await settle();

    expect(cena.harness.playback.sounding, isFalse,
        reason: 'a equipe segurou o clipe enquanto ele abria: o load não pode '
            'tocar por cima do gesto dela');
    expect(_estado(cena).btTrechoTocando, isFalse);

    cena.sala.ouvirVozMaterna();
    await waitFor(
      'o próximo toque começar o trecho',
      () => cena.harness.playback.sounding,
    );
  });

  test('o razão fecha o vão onde a sala se calou', () async {
    final cena = await _noRetro();
    cena.harness.playback.at = const Duration(milliseconds: 350);

    // Um gesto que tira a equipe da retro com a parte ainda no ar.
    cena.sala.goEnsaio();
    await settle();

    final estado = _estado(cena);
    expect(estado.btClipRodando, isFalse);
    expect(estado.btOuvidoMs, 350,
        reason: 'a sala se calou com a parte em 350 ms: o que a equipe ouviu '
            'até ali é o que o relato do terminei cobre, e um vão que ninguém '
            'fechou não conta nada');
  });

  test('o alternador isento não conta nenhuma parada', () async {
    final cena = await _comATomadaNaMao();
    final paradasAntes = cena.harness.playback.stops;

    cena.sala.takePlay();
    await waitFor('a tomada tocar', () => _estado(cena).playPing);
    cena.sala.takePlay();
    await settle();
    cena.sala.takePlay();
    await settle();

    expect(_estado(cena).playPing, isTrue);
    expect(cena.harness.playback.stops, paradasAntes,
        reason: 'tocar, pausar e retomar o mesmo som é o alternador da '
            'ENG-742, não um gesto que move a sala');
  });
}
