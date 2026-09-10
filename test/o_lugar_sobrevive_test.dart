import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/retro_cord.dart';

import 'fakes.dart';

/// Each rehearsal part, and the take one mend records over one stretch of it.
///
/// The mend is deliberately longer than the whole part it corrects: the two numbers a
/// stretch carries are the interval it plays and the interval it occupies, and only a
/// pair that cannot be mistaken for one another can tell whether the room is reading the
/// right one.
const _umaParte = Duration(seconds: 20);
const _oConserto = Duration(seconds: 27);

/// The stretch at one place in the row, whatever the room has renamed it to.
///
/// Mending mints a new name every time, so a stretch cannot be followed by its name
/// across a correction. Its place is what stays put, and it is what the team sees.
Trecho _no(ProviderContainer container, int lugar) =>
    container.read(salaSessionProvider).btTrechos[lugar];

/// The band the cord draws for one stretch, on the whole rehearsal.
///
/// The cord's own rule, called rather than copied: asking it this way is the question the
/// team asks of the necklace — "how much of the passage is my stretch?" — without knowing
/// which of the stretch's numbers the answer is reached through.
(int, int)? _naFaixa(SalaSessionState state, int lugar) => cordSpanMs(
      trecho: state.btTrechos[lugar],
      fimDasPartes: state.btFimDasPartesMs,
    );

class _Sala {
  final SalaHarness harness;
  ProviderContainer container;

  _Sala(this.harness, this.container);

  SalaSessionNotifier get sala => container.read(salaSessionProvider.notifier);

  SalaSessionState get estado => container.read(salaSessionProvider);
}

Future<void> _gravarUmaParte(_Sala it) async {
  final antes = it.estado.keptTakes.length;
  it.sala.ensaioTap();
  await waitFor(
    'a gravação da parte começar',
    () => it.estado.ensaio == EnsaioStatus.recording,
  );
  it.sala.ensaioTap();
  await waitFor(
    'a gravação da parte terminar',
    () => it.estado.ensaio == EnsaioStatus.recorded,
  );
  it.sala.takeKeep();
  await waitFor('a sala nomear a parte nova', () {
    final takes = it.estado.keptTakes;
    return takes.length == antes + 1 && takes.last.takeId != null;
  });
}

/// Cut a stretch where the part is playing and tell it back.
Future<void> _contarUmTrecho(_Sala it, Duration em) async {
  final antes = it.estado.btTrechos.length;
  it.harness.playback.at = em;
  it.sala.cortarTrecho();
  await waitFor(
    'o microfone abrir no trecho',
    () => it.estado.btPhase == BtPhase.capturing,
  );
  it.sala.retroTap();
  await waitFor(
    'o trecho contado entrar no colar',
    () => it.estado.btTrechos.length == antes + 1,
  );
}

Future<void> _atravessarAFronteira(_Sala it) async {
  it.harness.playback.finishPlayback();
  await waitFor('a parte terminar', () => it.estado.btParteFronteira);
  it.sala.proximaParte();
  await waitFor('a parte seguinte entrar no ar', () => !it.estado.btParteFronteira);
}

/// A rehearsal of two parts of twenty seconds each, told back in three stretches — the
/// first part whole in two of them, the second only as far as its eighth second — standing
/// at the analyst's finding on the stretch at [apontado].
///
/// The second part is deliberately left with ground nobody has told back: where the room
/// picks the telling up again is the whole question, and a rehearsal told to its end has
/// nowhere left to pick it up.
Future<_Sala> _aSalaNaPergunta({required int apontado}) async {
  final harness = SalaHarness()
    ..playback.length = _umaParte
    ..playback.measured = _oConserto
    ..room.verdictChecked = false
    ..room.verdictFinding = BtFindingKind.addition
    ..room.verdictFindingPlace = apontado;
  final container = harness.container();
  addTearDown(container.dispose);
  final it = _Sala(harness, container);

  await it.sala.goConversa(pericope: 'P01');
  await waitFor('a sala abrir', () => it.estado.sessionId != null);
  it.sala.goEnsaio();
  await _gravarUmaParte(it);
  await _gravarUmaParte(it);
  // Measured one by one, because the mend records a file of its own and it is longer
  // than the parts it corrects.
  for (final parte in it.estado.keptTakes) {
    harness.playback.lengths[parte.path] = _umaParte;
  }

  it.sala.startRetro();
  await waitFor(
    'a retrotradução começar a tocar a primeira parte',
    () => it.estado.stage == SalaStage.retro && it.estado.btPhase == BtPhase.playing,
  );

  await _contarUmTrecho(it, const Duration(seconds: 6));
  await _contarUmTrecho(it, _umaParte);
  await _atravessarAFronteira(it);
  await _contarUmTrecho(it, const Duration(seconds: 8));
  harness.playback.finishPlayback();
  await waitFor('o ensaio inteiro terminar', () => it.estado.btClipEnded);

  await it.sala.finishBackTranslation();
  await waitFor(
    'o analista apontar um trecho',
    () => it.estado.btPhase == BtPhase.findings && it.estado.btFindingTrecho != null,
  );
  return it;
}

/// The long way's first station: the mother tongue of the pointed stretch, recorded again.
/// It returns with the microphone already open for the telling that must follow.
Future<void> _regravarAMaterna(_Sala it) async {
  final antes = it.harness.room.replacesSemArquivo.length;
  it.sala.regravarAVozMaterna();
  it.sala.retroTap();
  await waitFor(
    'o microfone abrir na materna',
    () => it.estado.voice == VoiceState.listening,
  );
  it.sala.retroTap();
  await waitFor(
    'a voz materna nova substituir o trecho',
    () => it.harness.room.replacesSemArquivo.length == antes + 1,
  );
  await waitFor(
    'a segunda estação abrir sozinha',
    () => it.estado.btPhase == BtPhase.capturing,
  );
}

/// The short way, whole: choosing it opens the microphone on the stretch.
Future<void> _escolherRecontar(_Sala it) async {
  it.sala.traduzirDeNovoEmPortugues();
  await waitFor(
    'o microfone abrir para recontar',
    () => it.estado.btPhase == BtPhase.capturing,
  );
}

/// Hand the telling over and let the room say what it was worth.
Future<void> _entregarAPonte(_Sala it) async {
  final antes = it.harness.room.replacesAsked.length;
  it.sala.retroTap();
  await waitFor(
    'a ponte nova substituir o trecho',
    () => it.harness.room.replacesAsked.length == antes + 1,
  );
  await waitFor(
    'a sala voltar do veredito',
    () => it.estado.btPhase != BtPhase.thinking,
  );
}

/// The whole long way, both stations.
Future<void> _consertarPeloCaminhoLongo(_Sala it) async {
  await _regravarAMaterna(it);
  await _entregarAPonte(it);
}

/// The tablet closed and opened again on the same passage: a new room over the same
/// server, the same ledger and the same recordings on disk.
Future<void> _retomar(_Sala it) async {
  it.container.dispose();
  it.harness.playback.played.clear();
  it.container = it.harness.container();
  addTearDown(it.container.dispose);
  await it.sala.abrirEscolha();
  await waitFor(
    'a roda dizer que esta passagem tem trabalho parado',
    () => it.estado.comecadas.contains('P01'),
  );
  await it.sala.goConversa(pericope: 'P01');
  await waitFor(
    'a retrotradução ser retomada e voltar ao ar',
    () =>
        it.estado.stage == SalaStage.retro &&
        it.estado.btPhase == BtPhase.playing &&
        it.harness.playback.played.isNotEmpty,
  );
}

void main() {
  test('depois do caminho longo, o lugar do trecho é o original', () async {
    final it = await _aSalaNaPergunta(apontado: 0);
    final antes = _no(it.container, 0);
    expect(
      [antes.parte, antes.lugarFrom, antes.lugarTo],
      [0, Duration.zero, const Duration(seconds: 6)],
      reason: 'antes de qualquer conserto, o lugar de um trecho é o pedaço da '
          'parte que ele cobre',
    );

    await _consertarPeloCaminhoLongo(it);

    final depois = _no(it.container, 0);
    expect(
      [depois.from, depois.to],
      [Duration.zero, _oConserto],
      reason: 'o que toca é o take próprio da correção, inteiro',
    );
    expect(
      [depois.parte, depois.lugarFrom, depois.lugarTo],
      [0, Duration.zero, const Duration(seconds: 6)],
      reason: 'regravar a voz materna de um trecho não muda o trecho de lugar: '
          'ele continua sendo os seis primeiros segundos da primeira parte',
    );
    expect(
      _naFaixa(it.estado, 0),
      (0, 6000),
      reason: 'o colar desenhava a correção com o tamanho do arquivo novo — '
          'vinte e sete segundos num lugar de seis — e uma equipe que não lê '
          'via o conserto engolir os trechos vizinhos',
    );
  });

  test('na retomada fria, o lugar continua', () async {
    final it = await _aSalaNaPergunta(apontado: 0);
    await _consertarPeloCaminhoLongo(it);

    await _retomar(it);

    final depois = _no(it.container, 0);
    expect(
      [depois.parte, depois.lugarFrom, depois.lugarTo],
      [0, Duration.zero, const Duration(seconds: 6)],
      reason: 'a sala nova acha a parte de um trecho pela gravação que ele '
          'fatia, e a do conserto não é parte nenhuma do ensaio: o trecho '
          'voltava sem lugar, e o colar deixava de desenhá-lo',
    );
    expect(_naFaixa(it.estado, 0), isNotNull,
        reason: 'sem lugar não há faixa: a equipe retoma olhando um colar que '
            'diz que o trecho que ela consertou nunca existiu');
  });

  test('a retomada não recomeça uma parte já contada', () async {
    final it = await _aSalaNaPergunta(apontado: 1);
    final partes = [for (final take in it.estado.keptTakes) take.path];
    await _consertarPeloCaminhoLongo(it);

    await _retomar(it);

    expect(
      it.harness.playback.played.first,
      partes[1],
      reason: 'a primeira parte está contada de ponta a ponta; a sala tem de '
          'voltar no primeiro chão que ninguém contou, que está na segunda. '
          'Recomeçar a primeira faz a equipe contar de novo o que já contou, '
          'e o analista lê a passagem duas vezes',
    );
  });

  test('o próximo corte vem da parte certa', () async {
    final it = await _aSalaNaPergunta(apontado: 1);
    final partes = it.estado.keptTakes;
    await _consertarPeloCaminhoLongo(it);
    await _retomar(it);

    final antes = it.harness.room.chunksSent;
    await _contarUmTrecho(it, const Duration(seconds: 12));

    expect(it.harness.room.chunksSent, antes + 1);
    expect(
      it.harness.room.chunkTakes.last,
      partes[1].takeId,
      reason: 'o trecho novo é uma fatia da parte que está tocando. Contado '
          'sobre a gravação da parte anterior, cada trecho novo cai em cima do '
          'áudio de outro, e foi assim que o fim da história veio antes',
    );
    expect(
      int.parse(it.harness.room.chunkSpans.last.split('-').first),
      greaterThanOrEqualTo(8000),
      reason: 'a segunda parte já está contada até o oitavo segundo, e o corte '
          'seguinte começa onde a contagem parou',
    );
  });

  test('o caminho curto não mexe no lugar nem no que toca', () async {
    final it = await _aSalaNaPergunta(apontado: 0);
    final antes = _no(it.container, 0);

    await _escolherRecontar(it);
    await _entregarAPonte(it);

    final depois = _no(it.container, 0);
    expect(
      [depois.parte, depois.lugarFrom, depois.lugarTo, depois.from, depois.to],
      [antes.parte, antes.lugarFrom, antes.lugarTo, antes.from, antes.to],
      reason: 'recontar em português troca a explicação e mais nada: nem o '
          'áudio que toca nem o lugar onde ele mora se mexem',
    );
  });
}
