import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/retro_cord.dart';

import 'fakes.dart';

const _umaParte = Duration(seconds: 30);

/// Which stretches the cord can actually draw, by their place in the list.
///
/// The cord's own rule, called rather than copied: a stretch whose part it cannot place
/// has no offset on the line, and the painter drops it. Reading it this way asks the
/// question the team asks — "is my stretch still on the necklace?" — without knowing
/// anything about how the answer is reached.
List<int> _desenhados(SalaSessionState state) {
  int? onde(Trecho trecho, Duration quando) => cordStartMs(
        parte: trecho.parte,
        dentroMs: quando.inMilliseconds,
        fimDasPartes: state.btFimDasPartesMs,
      );
  return [
    for (var lugar = 0; lugar < state.btTrechos.length; lugar++)
      if (onde(state.btTrechos[lugar], state.btTrechos[lugar].from) != null &&
          onde(state.btTrechos[lugar], state.btTrechos[lugar].to) != null)
        lugar,
  ];
}

/// The stretch at one place in the row, whatever the room has renamed it to.
///
/// Mending mints a new name every time, so a stretch cannot be followed by its name
/// across a correction. Its place is what stays put, and it is what the team sees.
Trecho _no(ProviderContainer container, int lugar) =>
    container.read(salaSessionProvider).btTrechos[lugar];

class _Sala {
  final SalaHarness harness;
  final ProviderContainer container;

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

/// A rehearsal of two parts told back in three stretches — one out of the first part, two
/// out of the second — standing at the analyst's finding on the second stretch.
///
/// The pointed stretch is deliberately out of the *second* part: its place on the cord is
/// part 1, so a mend that lands it on part 0 is as wrong as one that loses it altogether,
/// and only reading the real part number can tell those apart.
Future<_Sala> _aSalaNaPergunta() async {
  final harness = SalaHarness()
    ..playback.length = _umaParte
    ..room.verdictChecked = false
    ..room.verdictFinding = BtFindingKind.addition
    ..room.verdictFindingPlace = 1;
  final container = harness.container();
  addTearDown(container.dispose);
  final it = _Sala(harness, container);

  await it.sala.goConversa();
  await waitFor('a sala abrir', () => it.estado.sessionId != null);
  it.sala.goEnsaio();
  await _gravarUmaParte(it);
  await _gravarUmaParte(it);
  it.sala.startRetro();
  await waitFor(
    'a retrotradução começar a tocar a primeira parte',
    () => it.estado.stage == SalaStage.retro && it.estado.btPhase == BtPhase.playing,
  );

  await _contarUmTrecho(it, const Duration(seconds: 10));
  harness.playback.finishPlayback();
  await waitFor(
    'a primeira parte terminar',
    () => it.estado.btParteFronteira,
  );
  it.sala.proximaParte();
  await waitFor(
    'a segunda parte entrar no ar',
    () => !it.estado.btParteFronteira,
  );
  await _contarUmTrecho(it, const Duration(seconds: 5));
  await _contarUmTrecho(it, const Duration(seconds: 12));
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
  it.sala.recontarEmPortugues();
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

void main() {
  test('o caminho longo não tira o trecho do colar', () async {
    final it = await _aSalaNaPergunta();
    final antes = _no(it.container, 1);
    expect(antes.parte, 1, reason: 'o trecho apontado mora na segunda parte');

    await _regravarAMaterna(it);

    final naSegundaEstacao = _no(it.container, 1);
    expect(naSegundaEstacao.parte, antes.parte,
        reason: 'a equipe regravou a voz materna daquele trecho, não mudou o '
            'trecho de lugar — e o lugar no colar é a única coisa nesta sala '
            'que diz a uma equipe que não lê *onde* o conserto está');
    expect(_desenhados(it.estado), contains(1),
        reason: 'sem parte que o colar saiba situar, o trecho some da faixa '
            'entre as duas estações: a equipe conserta olhando um colar que '
            'diz que aquele trecho nunca existiu');

    await _entregarAPonte(it);

    expect(_no(it.container, 1).parte, antes.parte,
        reason: 'e continua no mesmo lugar depois de recontado');
    expect(_desenhados(it.estado), contains(1),
        reason: 'o conserto inteiro passou, e a faixa que a equipe consertou '
            'está onde sempre esteve');
  });

  test('a ponte recém-gravada é a que se ouve, no caminho curto', () async {
    final it = await _aSalaNaPergunta();
    final aPonteAntiga = _no(it.container, 1).retroPath;
    expect(aPonteAntiga, isNotNull);

    await _escolherRecontar(it);
    await _entregarAPonte(it);
    final aPonteNova = it.harness.recorder.lastPath;

    expect(aPonteNova, isNot(aPonteAntiga));
    expect(_no(it.container, 1).retroPath, aPonteNova,
        reason: 'o botão de ouvir a ponte toca o arquivo do trecho, então ele '
            'tem de ser o que a equipe acabou de dizer — tocar o anterior '
            'devolve a explicação que o analista já recusou');
    expect(it.estado.btFindingTrecho?.retroPath, aPonteNova,
        reason: 'e é por este ponteiro que a tela decide se o botão acende, '
            'enquanto o achado estiver aberto');
  });

  test('depois do caminho longo, a ponte nova é a que se ouve', () async {
    final it = await _aSalaNaPergunta();

    await _regravarAMaterna(it);
    final aMaterna = it.harness.recorder.lastPath;
    await _entregarAPonte(it);
    final aPonteNova = it.harness.recorder.lastPath;

    expect(aPonteNova, isNot(aMaterna),
        reason: 'as duas estações gravam arquivos diferentes');
    expect(_no(it.container, 1).retroPath, aPonteNova,
        reason: 'o caminho longo termina na mesma recontagem que o curto, e a '
            'ponte que ficou é a que a equipe gravou agora');
    expect(it.estado.btFindingTrecho?.retroPath, aPonteNova);
  });

  test('dois consertos seguidos não perdem a ponte', () async {
    final it = await _aSalaNaPergunta();

    await _regravarAMaterna(it);
    await _entregarAPonte(it);
    await _escolherRecontar(it);
    await _entregarAPonte(it);
    final aTerceiraPonte = it.harness.recorder.lastPath;

    expect(_no(it.container, 1).retroPath, aTerceiraPonte,
        reason: 'um trecho que passou pelo caminho longo não fica surdo para '
            'sempre: era assim que o usuário chegava à segunda correção sem '
            'nenhuma ponte para escutar');
  });

  test('a primeira contagem continua guardando o que foi gravado', () async {
    final it = await _aSalaNaPergunta();

    for (final lugar in [0, 1, 2]) {
      expect(_no(it.container, lugar).retroPath, isNotNull,
          reason: 'todo trecho contado tem aqui a cópia do que a equipe disse '
              'na língua-ponte');
    }
  });

  test('os trechos vizinhos não se mexem', () async {
    final it = await _aSalaNaPergunta();
    final vizinhos = [_no(it.container, 0), _no(it.container, 2)];

    await _regravarAMaterna(it);
    await _entregarAPonte(it);
    await _escolherRecontar(it);
    await _entregarAPonte(it);

    for (final (onde, antes) in [(0, vizinhos[0]), (2, vizinhos[1])]) {
      final depois = _no(it.container, onde);
      expect(
        [depois.parte, depois.retroPath, depois.from, depois.to],
        [antes.parte, antes.retroPath, antes.from, antes.to],
        reason: 'correção é localizada: consertar um trecho não pode mover nem '
            'emudecer os outros dois',
      );
    }
  });
}
