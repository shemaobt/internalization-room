import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';

/// A rehearsal of three parts of three different lengths. Three, because the part the
/// room's refusal names has to be able to have neighbours on both sides of it.
const partesDoEnsaio = [
  Duration(seconds: 10),
  Duration(seconds: 8),
  Duration(seconds: 12),
];

class Sala {
  final SalaHarness harness;

  /// Not final: a tablet closed and opened again on the same passage is a new container
  /// over the same doubles, and the ruler after a mend is read across that seam.
  ProviderContainer container;

  Sala(this.harness, this.container);

  SalaSessionNotifier get sala => container.read(salaSessionProvider.notifier);

  SalaSessionState get estado => container.read(salaSessionProvider);

  List<KeptTake> get partes => estado.partes;
}

Future<void> gravarUmaParte(Sala it) async {
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

/// Translate the part in the air whole: the cut is made at its end, so what the team told
/// back of it runs from its own nought to its own length.
Future<void> ouvirETraduzirAParteInteira(Sala it, Duration quanto) async {
  final antes = it.estado.btTrechos.length;
  it.harness.playback.length = quanto;
  it.harness.playback.at = quanto;
  it.sala.cortarTrecho();
  it.sala.retroTap();
  await waitFor(
    'o microfone abrir no trecho',
    () => it.estado.btPhase == BtPhase.capturing,
  );
  await confirmarATraducao(it.container);
  await waitFor(
    'o trecho traduzido entrar no colar',
    () => it.estado.btTrechos.length == antes + 1,
  );
  it.harness.playback.finishPlayback();
  await waitFor(
    'a parte terminar',
    () => it.estado.btParteFronteira || it.estado.btClipEnded,
  );
}

/// The rehearsal recorded in three parts with nothing told back yet: the room as it stands
/// the first time the team presses the advance button.
Future<Sala> umEnsaioDeTresPartesGravado({
  Duration? tetoDaEspera,
  WorkInProgress? emAbertoNoDisco,
}) async {
  final harness = SalaHarness(
    busyCeiling: tetoDaEspera,
    emAbertoNoDisco: emAbertoNoDisco,
  );
  final container = harness.container();
  addTearDown(container.dispose);
  final it = Sala(harness, container);

  await it.sala.goConversa(pericope: 'P01');
  await waitFor('a sala abrir', () => it.estado.sessionId != null);
  it.sala.goEnsaio();
  for (var onde = 0; onde < partesDoEnsaio.length; onde++) {
    await gravarUmaParte(it);
  }
  final partes = it.estado.keptTakes;
  for (var onde = 0; onde < partesDoEnsaio.length; onde++) {
    harness.playback.lengths[partes[onde].path] = partesDoEnsaio[onde];
  }
  return it;
}

/// The rehearsal recorded in three parts, every one of them told back whole and played to
/// its end, standing with the advance disc beckoning and nothing pressed yet.
Future<Sala> umEnsaioDeTresPartesContadoInteiro({
  Duration? tetoDaEspera,
  WorkInProgress? emAbertoNoDisco,
}) async {
  final it = await umEnsaioDeTresPartesGravado(
    tetoDaEspera: tetoDaEspera,
    emAbertoNoDisco: emAbertoNoDisco,
  );

  it.sala.startRetro();
  await waitFor(
    'a tradução começar a tocar a primeira parte',
    () =>
        it.estado.stage == SalaStage.retro &&
        it.estado.btPhase == BtPhase.playing,
  );

  for (var onde = 0; onde < partesDoEnsaio.length; onde++) {
    await ouvirETraduzirAParteInteira(it, partesDoEnsaio[onde]);
    if (onde < partesDoEnsaio.length - 1) {
      it.sala.ouvirGravacao();
      await waitFor(
        'a parte seguinte entrar no ar',
        () => !it.estado.btParteFronteira,
      );
    }
  }
  return it;
}

/// Cut the stretch in the air at [em], wherever in the part that falls, and tell that
/// stretch back — the caller decides whether that lands mid-part or at its end.
Future<void> traduzirUmTrecho(Sala it, Duration em) async {
  final antes = it.estado.btTrechos.length;
  it.harness.playback.at = em;
  it.sala.cortarTrecho();
  it.sala.retroTap();
  await waitFor(
    'o microfone abrir no trecho',
    () => it.estado.btPhase == BtPhase.capturing,
  );
  await confirmarATraducao(it.container);
  await waitFor(
    'o trecho contado entrar no colar',
    () => it.estado.btTrechos.length == antes + 1,
  );
}

/// Hand a mended stretch up and wait for it to take the retired one's place.
Future<void> entregarAPonte(Sala it) async {
  final antes = it.harness.room.replacesAsked.length;
  await fecharACaptura(it.container);
  await it.sala.confirmarTraducao();
  await waitFor(
    'a ponte nova substituir o trecho',
    () => it.harness.room.replacesAsked.length == antes + 1,
  );
  await waitFor(
    'a sala voltar do veredito',
    () => it.estado.btPhase != BtPhase.thinking,
  );
}

/// Cross from the part in the air into the one after it.
Future<void> atravessarAFronteira(Sala it) async {
  it.harness.playback.finishPlayback();
  await waitFor('a parte terminar', () => it.estado.btParteFronteira);
  it.sala.ouvirGravacao();
  await waitFor(
    'a parte seguinte entrar no ar',
    () => !it.estado.btParteFronteira,
  );
}

/// Open the microphone to translate the stretch in the air a second time.
Future<void> escolherTraduzirDeNovo(Sala it) async {
  it.sala.traduzirDeNovoEmPortugues();
  it.sala.retroTap();
  await waitFor(
    'o microfone abrir para traduzir de novo',
    () => it.estado.btPhase == BtPhase.capturing,
  );
}

Future<void> pedirOVeredito(Sala it) async {
  await it.sala.finishBackTranslation();
  await waitFor(
    'a sala voltar do veredito',
    () => it.estado.btPhase != BtPhase.thinking,
  );
}

/// Record the part at [onde] again, in its own place: the row keeps its length and only
/// that entry changes. The sibling of [gravarUmaParte], which asserts the opposite.
///
/// The name is not waited for here: a test that holds the upload has to be able to look
/// at a part the room has not answered for yet.
Future<void> regravarAParte(Sala it, int onde) async {
  final antes = it.partes;
  final antiga = antes[onde].path;
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
  await waitFor('a gravação nova tomar o lugar da parte ${onde + 1}', () {
    final agora = it.partes;
    return agora.length == antes.length && agora[onde].path != antiga;
  });
}
