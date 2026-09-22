import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';

/// How long each rehearsal part is, and what the player answers for anything else.
const _umaParte = Duration(seconds: 20);
const _oQueOPlayerMede = Duration(seconds: 27);

/// The stretch at one place in the row, whatever the room has renamed it to.
///
/// Mending mints a new name every time, so a stretch cannot be followed by its name
/// across a correction. Its place is what stays put, and it is what the team sees.
Trecho _no(ProviderContainer container, int lugar) =>
    container.read(salaSessionProvider).btTrechos[lugar];

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
Future<void> _traduzirUmTrecho(_Sala it, Duration em) async {
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
  it.sala.ouvirGravacao();
  await waitFor(
    'a parte seguinte entrar no ar',
    () => !it.estado.btParteFronteira,
  );
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
    ..playback.measured = _oQueOPlayerMede
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
    'a tradução começar a tocar a primeira parte',
    () =>
        it.estado.stage == SalaStage.retro &&
        it.estado.btPhase == BtPhase.playing,
  );

  await _traduzirUmTrecho(it, const Duration(seconds: 6));
  await _traduzirUmTrecho(it, _umaParte);
  await _atravessarAFronteira(it);
  await _traduzirUmTrecho(it, const Duration(seconds: 8));
  harness.playback.finishPlayback();
  await waitFor('o ensaio inteiro terminar', () => it.estado.btClipEnded);

  await it.sala.finishBackTranslation();
  await waitFor(
    'o analista apontar um trecho',
    () =>
        it.estado.btPhase == BtPhase.findings &&
        it.estado.btFindingTrecho != null,
  );
  return it;
}

/// The short way, whole: choosing it opens the microphone on the stretch.
Future<void> _escolherTraduzirDeNovo(_Sala it) async {
  it.sala.traduzirDeNovoEmPortugues();
  await waitFor(
    'o microfone abrir para traduzir de novo',
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
    'a tradução ser retomada e voltar ao ar',
    () =>
        it.estado.stage == SalaStage.retro &&
        it.estado.btPhase == BtPhase.playing &&
        it.harness.playback.played.isNotEmpty,
  );
}

void main() {
  test('a retomada não recomeça uma parte já contada', () async {
    final it = await _aSalaNaPergunta(apontado: 1);
    final partes = [for (final take in it.estado.keptTakes) take.path];
    await _escolherTraduzirDeNovo(it);
    await _entregarAPonte(it);

    await _retomar(it);

    expect(
      it.harness.playback.played.first,
      partes[1],
      reason:
          'a primeira parte está contada de ponta a ponta; a sala tem de '
          'voltar no primeiro chão que ninguém contou, que está na segunda. '
          'Recomeçar a primeira faz a equipe traduzir de novo o que já contou, '
          'e o analista lê a passagem duas vezes',
    );
  });

  test('o próximo corte vem da parte certa', () async {
    final it = await _aSalaNaPergunta(apontado: 1);
    final partes = it.estado.keptTakes;
    await _escolherTraduzirDeNovo(it);
    await _entregarAPonte(it);
    await _retomar(it);

    final antes = it.harness.room.chunksSent;
    await _traduzirUmTrecho(it, const Duration(seconds: 12));

    expect(it.harness.room.chunksSent, antes + 1);
    expect(
      it.harness.room.chunkTakes.last,
      partes[1].takeId,
      reason:
          'o trecho novo é uma fatia da parte que está tocando. Contado '
          'sobre a gravação da parte anterior, cada trecho novo cai em cima do '
          'áudio de outro, e foi assim que o fim da história veio antes',
    );
    expect(
      int.parse(it.harness.room.chunkSpans.last.split('-').first),
      greaterThanOrEqualTo(8000),
      reason:
          'a segunda parte já está contada até o oitavo segundo, e o corte '
          'seguinte começa onde a contagem parou',
    );
  });

  test('o caminho curto não mexe no lugar nem no que toca', () async {
    final it = await _aSalaNaPergunta(apontado: 0);
    final antes = _no(it.container, 0);

    await _escolherTraduzirDeNovo(it);
    await _entregarAPonte(it);

    final depois = _no(it.container, 0);
    expect(
      [depois.parte, depois.lugarFrom, depois.lugarTo, depois.from, depois.to],
      [antes.parte, antes.lugarFrom, antes.lugarTo, antes.from, antes.to],
      reason:
          'traduzir de novo em português troca a explicação e mais nada: nem o '
          'áudio que toca nem o lugar onde ele mora se mexem',
    );
  });
}
