import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
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
  await waitFor(
    'o microfone abrir no trecho',
    () => it.estado.btPhase == BtPhase.capturing,
  );
  it.sala.retroTap();
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

/// The rehearsal recorded in three parts, every one of them told back whole and played to
/// its end, standing with *terminei* lit and nothing pressed yet.
Future<Sala> umEnsaioDeTresPartesContadoInteiro({
  String? compoeEm,
  Duration? tetoDaEspera,
}) async {
  final harness = SalaHarness(busyCeiling: tetoDaEspera)
    ..room.composesInto = compoeEm;
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
      it.sala.proximaParte();
      await waitFor(
        'a parte seguinte entrar no ar',
        () => !it.estado.btParteFronteira,
      );
    }
  }
  return it;
}

Future<void> pedirOVeredito(Sala it) async {
  await it.sala.finishBackTranslation();
  await waitFor(
    'a sala voltar do veredito',
    () => it.estado.btPhase != BtPhase.thinking,
  );
}

/// The name the room gives the recording it rebuilds around a mend of this rehearsal, and
/// how long that recording is: shorter than the part it takes the place of, so a length
/// carried over from the file it replaced shows on the cord.
const composta = 'C';
const aComposta = Duration(seconds: 5);

KeptTake parteDois(Sala it) => it.estado.keptTakes.firstWhere(
      (take) => take.scopeId == KeptScope.parte(2),
    );
