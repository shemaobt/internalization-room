import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'session_notifier_test.dart' show inConversa;
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

/// The room was quiet at the instant this gesture made its own sound.
///
/// Not merely "a stop was called": the *last* silence before that sound has to come after
/// everything that was sounding before it. A gesture whose own sound arrives several steps
/// into a turn would otherwise pass on the silence of the step that opened the turn.
///
/// Read off one ordered log both players and the recorder write to, so no double has to
/// read another — and off the order, never off which private method ran.
void aSalaSeCalouPrimeiro(
  List<String> desde,
  String linha, {
  bool segurando = false,
  String? somProprio,
}) {
  final calandoOEnsaio = segurando ? 'playback:pause' : 'playback:stop';
  expect(
    desde,
    contains(calandoOEnsaio),
    reason:
        '$linha: o gesto move a sala e o ensaio ficou tocando por baixo '
        'do que veio depois',
  );
  expect(
    desde,
    contains('voice:stop'),
    reason: '$linha: a voz da Guia ficou falando por baixo do gesto',
  );

  final alvo = somProprio == null
      ? desde.indexWhere(_fazemSom.contains)
      : desde.indexOf(somProprio);
  if (alvo < 0) return;
  final antes = desde.sublist(0, alvo);
  final ultimoSom = antes.lastIndexWhere(_fazemSom.contains);
  for (final calando in [calandoOEnsaio, 'voice:stop']) {
    expect(
      antes.lastIndexOf(calando),
      greaterThan(ultimoSom),
      reason:
          '$linha: entre ${ultimoSom < 0 ? 'o começo' : antes[ultimoSom]} '
          'e ${desde[alvo]} a sala não se calou. Log: $desde',
    );
  }
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
  String? somProprio,
});

_Linha _linha(
  String nome,
  Future<_Cena> Function() arranjo,
  Future<void> Function(_Cena) gesto, {
  bool segurando = false,
  String? somProprio,
}) => (
  nome: nome,
  arranjo: arranjo,
  gesto: gesto,
  segurando: segurando,
  somProprio: somProprio,
);

_Cena _cena(SalaHarness harness, ProviderContainer container) => (
  harness: harness,
  container: container,
  sala: container.read(salaSessionProvider.notifier),
);

SalaSessionState _estado(_Cena cena) =>
    cena.container.read(salaSessionProvider);

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
  await waitFor(
    'a parte entrar no ar',
    () => _estado(cena).btClipRodando && harness.playback.sounding,
  );
  return cena;
}

/// A rehearsal recorded and offered, with the take still pending: the one state the
/// check and the circle's record-over live in.
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

/// The same screen with the pointed stretch actually sounding, which is the state every
/// gesture of the findings is really made in.
Future<_Cena> _nosAchadosComOTrechoNoAr() async {
  final cena = await _nosAchados();
  cena.sala.ouvirOTrechoEATraducao();
  await waitFor(
    'o trecho apontado tocar',
    () => _estado(cena).btTrechoTocando && cena.harness.playback.sounding,
  );
  return cena;
}

/// Two parts, the first played through: the room offers the crossing into the second.
Future<_Cena> _naFronteiraDaParte() async {
  final cena = await _noRetro(partes: 2);
  cena.harness.playback.at = const Duration(milliseconds: 600);
  cena.harness.playback.finishPlayback();
  await waitFor(
    'a fronteira da parte abrir',
    () => _estado(cena).btParteFronteira,
  );
  return cena;
}

/// A telling-back with one stretch told and the clip ended: the door *terminei* opens.
Future<_Cena> _prontoParaTerminei() async {
  final cena = await _noRetro();
  cena.harness.playback.at = const Duration(milliseconds: 40);
  cena.sala.cortarTrecho();
  cena.sala.retroTap();
  await waitFor(
    'o microfone abrir no trecho',
    () => _estado(cena).btPhase == BtPhase.capturing,
  );
  await confirmarATraducao(cena.container);
  await waitFor(
    'o trecho chegar à sala',
    () =>
        cena.harness.room.chunksSent == 1 &&
        _estado(cena).btPhase == BtPhase.playing,
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
  await waitFor(
    'a roda carregar e oferecer a primeira passagem',
    () =>
        _estado(cena).naRoda != null &&
        _estado(cena).voice == VoiceState.invite,
  );
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
          somProprio: linha.somProprio,
        );
        if (linha.segurando) {
          expect(
            cena.harness.playback.sounding,
            isFalse,
            reason:
                '${linha.nome}: segurar é calar. O clipe fica aberto para '
                'a equipe voltar a ele, mas som nenhum pode continuar a sair '
                'por baixo do que o gesto abriu',
          );
        }
      });
    }

    test('nenhum gesto da matriz do ticket ficou de fora', () {
      expect(
        [for (final linha in tabela) linha.nome]..sort(),
        [...daMatriz]..sort(),
        reason:
            'uma transição que sai da tabela é uma transição que volta a '
            'tocar por cima da próxima: a matriz do ticket é o contrato',
      );
    });
  });
}

/// The back-translation's gestures, copied from the ticket's matrix, minus the two rows
/// ENG-951 retired with `proximaParte` and `retellChunk` (ADR 0024's Consequences) and the
/// grid's players, scissors and in-place capture ADR 0040 retired.
const _matrizDaRetro = [
  'a aprovação',
  'terminei',
  'o círculo, capturando',
  'o círculo, nos achados',
  'atravessar para a próxima parte',
  'ouvir o trecho e a tradução',
  'traduzir de novo, no achado',
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
  'dizer a passagem de novo',
  'abrir a roda',
  'entrar na passagem oferecida',
  'entrar no panorama da roda',
];

void main() {
  _rodaATabela('a retro se cala antes de mudar', [
    _linha(
      'a aprovação',
      () async {
        final cena = await _prontoParaTerminei();
        await cena.sala.finishBackTranslation();
        await waitFor(
          'o veredito limpo chegar',
          () => _estado(cena).btPhase == BtPhase.conferida,
        );
        // A última escuta que o veredito limpo convida.
        cena.sala.ouvirGravacao();
        await waitFor(
          'a última escuta tocar',
          () => cena.harness.playback.sounding,
        );
        return cena;
      },
      (cena) async {
        await cena.sala.aprovarRascunhoFinal();
        await waitFor(
          'a linha aprovada ser dita',
          () => cena.harness.voice.assets.contains(
            fixedLineAsset(approvedLine, testLanguage),
          ),
        );
      },
      somProprio: 'voice:asset',
    ),
    _linha('terminei', _prontoParaTerminei, (cena) async {
      await cena.sala.finishBackTranslation();
      await waitFor(
        'o veredito ser dito',
        () => _estado(cena).btPhase != BtPhase.thinking,
      );
    }, somProprio: 'voice:line'),
    _linha(
      'o círculo, capturando',
      () async {
        final cena = await _noRetro();
        cena.harness.playback.at = const Duration(milliseconds: 40);
        cena.sala.cortarTrecho();
        cena.sala.retroTap();
        await waitFor(
          'o microfone abrir',
          () => _estado(cena).btPhase == BtPhase.capturing,
        );
        return cena;
      },
      (cena) async {
        await confirmarATraducao(cena.container);
        await waitFor(
          'o pedaço chegar à sala',
          () =>
              cena.harness.room.chunksSent == 1 &&
              _estado(cena).btPhase == BtPhase.playing,
        );
      },
      segurando: true,
    ),
    _linha('o círculo, nos achados', _nosAchadosComOTrechoNoAr, (cena) async {
      final ditas = cena.harness.voice.played.length;
      cena.sala.retroTap();
      await waitFor(
        'a Guia repetir o veredito',
        () => cena.harness.voice.played.length > ditas,
      );
    }, somProprio: 'voice:line'),
    _linha(
      'atravessar para a próxima parte',
      _naFronteiraDaParte,
      (cena) async {
        // O gesto que a tela realmente tem: é por aqui que a equipe cruza
        // para a parte seguinte.
        cena.sala.ouvirGravacao();
        await waitFor(
          'a parte seguinte entrar no ar',
          () => _estado(cena).btClipRodando,
        );
      },
      somProprio: 'playback:play',
    ),
    _linha(
      'ouvir o trecho e a tradução',
      () async {
        final cena = await _nosAchados();
        // A Guia no meio de uma linha: é por cima dela que o trecho começava.
        cena.harness.voice.holdNextLine();
        cena.sala.retroTap();
        await waitFor(
          'a Guia começar a repetir o veredito',
          () => cena.harness.sounds.contains('voice:line'),
        );
        return cena;
      },
      (cena) async {
        cena.sala.ouvirOTrechoEATraducao();
        await waitFor(
          'o trecho apontado tocar',
          () => _estado(cena).btTrechoTocando,
        );
        cena.harness.voice.finishHeldLine();
      },
      somProprio: 'playback:play',
    ),
    _linha('traduzir de novo, no achado', _nosAchadosComOTrechoNoAr, (
      cena,
    ) async {
      cena.sala.traduzirDeNovoEmPortugues();
      await waitFor(
        'a tradução abrir no trecho apontado',
        () => _estado(cena).btPhase == BtPhase.playing,
      );
    }),
    _linha(
      'cortar o trecho',
      () async {
        final cena = await _noRetro();
        cena.harness.playback.at = const Duration(milliseconds: 40);
        return cena;
      },
      (cena) async {
        cena.sala.cortarTrecho();
        cena.sala.retroTap();
        await waitFor(
          'o microfone abrir',
          () => _estado(cena).btPhase == BtPhase.capturing,
        );
      },
      segurando: true,
      somProprio: 'recorder:start',
    ),
    _linha(
      'cortar com a cabeça atrás do cursor',
      () async {
        final cena = await _noRetro();
        cena.harness.playback.at = const Duration(milliseconds: 400);
        cena.sala.cortarTrecho();
        cena.sala.retroTap();
        await waitFor(
          'o microfone abrir',
          () => _estado(cena).btPhase == BtPhase.capturing,
        );
        await confirmarATraducao(cena.container);
        await waitFor(
          'o trecho chegar à sala e a gravação seguir no ar',
          () =>
              _estado(cena).btPhase == BtPhase.playing &&
              cena.harness.playback.sounding,
        );
        // O cursor está no último corte; a cabeça volta atrás dele, que é a única
        // leitura que a sala recusa em vez de mandar um trecho que acaba antes de
        // começar.
        cena.harness.playback.at = const Duration(milliseconds: 5);
        return cena;
      },
      (cena) async {
        cena.sala.cortarTrecho();
        cena.sala.retroTap();
        expect(
          _estado(cena).btPhase,
          BtPhase.playing,
          reason: 'o arranjo só vale se o corte for recusado',
        );
      },
      segurando: true,
    ),
    _linha(
      'a parte não ouvida',
      () async {
        final cena = await _prontoParaTerminei();
        final gravacao = _estado(cena).partes.first.takeId!;
        cena.harness.room.verdictUnheardTakeIds = [gravacao];
        return cena;
      },
      (cena) async {
        await cena.sala.finishBackTranslation();
        await waitFor(
          'a parte entrar no ar',
          () => _estado(cena).btClipRodando,
        );
      },
      somProprio: 'playback:play',
    ),
    _linha(
      'o trecho não contado',
      () async {
        final cena = await _prontoParaTerminei();
        cena.harness.room
          ..verdictChecked = false
          ..verdictUntoldSegmentId = 'trecho-1';
        return cena;
      },
      (cena) async {
        await cena.sala.finishBackTranslation();
        await waitFor(
          'o trecho nomeado entrar no ar',
          () => _estado(cena).btTrechoTocando,
        );
      },
      somProprio: 'playback:play',
    ),
    _linha('a parte que não tocou volta ao ensaio', _noRetro, (cena) async {
      cena.harness.playback.failPlayback();
      await waitFor(
        'a equipe voltar ao ensaio',
        () => _estado(cena).stage == SalaStage.ensaio,
      );
    }),
    _linha('deixar a passagem', _noRetro, (cena) async {
      cena.sala.leaveThePassage();
      await waitFor(
        'a roda abrir',
        () => _estado(cena).stage == SalaStage.escolha,
      );
    }),
    _linha('continuar o ensaio', _nosAchadosComOTrechoNoAr, (cena) async {
      cena.sala.continuarOEnsaio();
      await waitFor(
        'a equipe voltar ao ensaio',
        () => _estado(cena).stage == SalaStage.ensaio,
      );
    }),
    _linha('gravar a parte de novo', _nosAchadosComOTrechoNoAr, (cena) async {
      cena.sala.gravarAParteDeNovo();
      await waitFor(
        'a equipe voltar ao ensaio',
        () => _estado(cena).stage == SalaStage.ensaio,
      );
    }),
    _linha(
      'gravar a parte de novo, sem parte',
      () async {
        final cena = await _prontoParaTerminei();
        // Um trecho numa gravação que este tablet não tem: não há parte para gravar
        // de novo, e a sala chama uma pessoa em vez de seguir.
        cena.harness.room
          ..verdictChecked = false
          ..verdictFindingSegmentId = 'trecho-1'
          ..segments.clear()
          ..segments.add(
            const SegmentView(
              segmentId: 'trecho-1',
              takeId: 'gravacao-de-outro-tablet',
              startsMs: 0,
              endsMs: 40,
            ),
          );
        await cena.sala.finishBackTranslation();
        await waitFor(
          'o achado abrir',
          () => _estado(cena).btPhase == BtPhase.findings,
        );
        expect(
          _estado(cena).btFindingTrecho?.parte,
          -1,
          reason:
              'o arranjo só vale se o trecho apontado não tiver parte '
              'neste tablet — senão a linha mede o caminho comum',
        );
        return cena;
      },
      (cena) async {
        cena.sala.gravarAParteDeNovo();
        await waitFor(
          'a sala chamar uma pessoa',
          () => _estado(cena).needsPerson,
        );
      },
    ),
  ], _matrizDaRetro);

  _rodaATabela('o ensaio se cala antes de mudar', [
    _linha(
      'abrir o microfone',
      () async {
        final cena = await _comATomadaNaMao();
        cena.sala.takeKeep();
        await waitFor(
          'a tomada ser confirmada',
          () => _estado(cena).ensaio == EnsaioStatus.idle,
        );
        return cena;
      },
      (cena) async {
        cena.sala.ensaioTap();
        await waitFor(
          'o microfone abrir',
          () => _estado(cena).ensaio == EnsaioStatus.recording,
        );
      },
      somProprio: 'recorder:start',
    ),
    _linha(
      'gravar a tomada de novo',
      () async {
        final cena = await _comATomadaNaMao();
        cena.sala.playTheRehearsal();
        await waitFor(
          'a tomada tocar',
          () => _estado(cena).playPing && cena.harness.playback.sounding,
        );
        cena.sala.playTheRehearsal();
        await waitFor('a tomada pausar', () => _estado(cena).takePaused);
        return cena;
      },
      (cena) async {
        cena.sala.ensaioTap();
        await waitFor(
          'o microfone abrir por cima da tomada',
          () => _estado(cena).ensaio == EnsaioStatus.recording,
        );
      },
      somProprio: 'recorder:start',
    ),
    _linha('ir para o ensaio', _noRetro, (cena) async {
      cena.sala.goEnsaio();
      await waitFor(
        'a equipe chegar ao ensaio',
        () => _estado(cena).stage == SalaStage.ensaio,
      );
    }),
    _linha(
      'começar o retro',
      () async {
        final harness = SalaHarness();
        final container = await inConversa(harness);
        addTearDown(container.dispose);
        final cena = _cena(harness, container);
        cena.sala.goEnsaio();
        await gravaParte(container, cena.sala);
        return cena;
      },
      (cena) async {
        cena.sala.startRetro();
        await waitFor(
          'a retro abrir',
          () => _estado(cena).stage == SalaStage.retro,
        );
      },
    ),
  ], _matrizDoEnsaio);

  _rodaATabela('a conversa e a roda se calam antes de mudar', [
    _linha(
      'abrir o microfone na conversa',
      () async {
        final harness = SalaHarness();
        final container = await inConversa(harness);
        addTearDown(container.dispose);
        return _cena(harness, container);
      },
      (cena) async {
        cena.sala.conversaTap();
        await waitFor(
          'o microfone abrir',
          () => _estado(cena).voice == VoiceState.listening,
        );
      },
      somProprio: 'recorder:start',
    ),
    _linha('arrastar a régua da roda', _naRoda, (cena) async {
      cena.sala.apontarPassagem(1);
      await waitFor(
        'a roda parar na passagem apontada',
        () => _estado(cena).aOferecer == 1,
      );
    }),
    _linha('dizer a passagem de novo', _naRoda, (cena) async {
      final ditas = cena.harness.voice.played.length;
      cena.sala.dizerAPassagem();
      await waitFor(
        'a roda dizer a passagem de novo',
        () => cena.harness.voice.played.length > ditas,
      );
    }, somProprio: 'voice:line'),
    _linha('abrir a roda', _noRetro, (cena) async {
      await cena.sala.abrirEscolha();
      await waitFor('a roda carregar', () => _estado(cena).naRoda != null);
    }),
    _linha('entrar na passagem oferecida', _naRoda, (cena) async {
      cena.sala.entrarNaOferecida();
      await waitFor(
        'a conversa abrir',
        () => _estado(cena).stage == SalaStage.conversa,
      );
    }),
    _linha(
      'entrar no panorama da roda',
      () async {
        final harness = SalaHarness()
          ..room.passages = const [
            Passagem(pericope: 'P01', audioUrl: '/voice/p01'),
            Passagem(
              pericope: 'panorama',
              audioUrl: '/voice/panorama',
              kind: PassagemKind.panorama,
            ),
          ];
        final container = harness.container();
        addTearDown(container.dispose);
        final cena = _cena(harness, container);
        await cena.sala.abrirEscolha();
        await waitFor('a roda carregar', () => _estado(cena).naRoda != null);
        cena.sala.apontarPassagem(1);
        await waitFor(
          'a roda dizer o raio do panorama',
          () =>
              _estado(cena).aOferecer == 1 &&
              _estado(cena).voice == VoiceState.invite,
        );
        return cena;
      },
      (cena) async {
        // Este ramo não passa pelo _clearAll do goConversa, e a linha que a roda
        // acabou de oferecer seguia soando por cima da espera dele.
        final ditas = cena.harness.voice.played.length;
        cena.sala.entrarNaOferecida();
        await waitFor(
          'o panorama falar',
          () => cena.harness.voice.played.length > ditas,
        );
      },
      somProprio: 'voice:line',
    ),
  ], _matrizDaConversaEDaRoda);

  test('um hold dado enquanto o clipe abre não deixa a sala tocando', () async {
    final cena = await _nosAchados();
    cena.harness.playback.holdNextOpening();

    cena.sala.ouvirOTrechoEATraducao();
    await waitFor('a sala pedir o trecho', () => _estado(cena).btTrechoTocando);
    cena.sala.ouvirOTrechoEATraducao();
    await waitFor(
      'a equipe segurar o trecho',
      () => _estado(cena).btTrechoPausada,
    );

    cena.harness.playback.finishHeldOpening();
    await waitFor(
      'a abertura segurada terminar',
      () => cena.harness.playback.playingLength != null,
    );

    expect(
      cena.harness.playback.sounding,
      isFalse,
      reason:
          'a equipe segurou o clipe enquanto ele abria: o load não pode '
          'tocar por cima do gesto dela',
    );
    expect(_estado(cena).btTrechoTocando, isFalse);

    cena.sala.ouvirOTrechoEATraducao();
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
    await waitFor(
      'a equipe chegar ao ensaio',
      () => _estado(cena).stage == SalaStage.ensaio,
    );

    final estado = _estado(cena);
    expect(estado.btClipRodando, isFalse);
    expect(
      estado.btOuvidoMs,
      350,
      reason:
          'a sala se calou com a parte em 350 ms: o que a equipe ouviu '
          'até ali é o que o relato do terminei cobre, e um vão que ninguém '
          'fechou não conta nada',
    );
  });

  test('o alternador isento não conta nenhuma parada', () async {
    final cena = await _comATomadaNaMao();
    final paradasAntes = cena.harness.playback.stops;

    cena.sala.playTheRehearsal();
    await waitFor('a tomada tocar', () => _estado(cena).playPing);
    cena.sala.playTheRehearsal();
    await waitFor('a tomada pausar', () => _estado(cena).takePaused);
    cena.sala.playTheRehearsal();
    await waitFor('a tomada retomar', () => _estado(cena).playPing);

    expect(
      cena.harness.playback.stops,
      paradasAntes,
      reason:
          'tocar, pausar e retomar o mesmo som é o alternador da '
          'ENG-742, não um gesto que move a sala',
    );
  });
}
