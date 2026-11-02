import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'a_wav_take.dart';
import 'fakes.dart';
import 'scenario_helpers.dart' show settle;
import 'um_ensaio_de_tres_partes.dart';

Duration _s(double seconds) => Duration(milliseconds: (seconds * 1000).round());

const _aParte = Duration(seconds: 10);

Future<Sala> _umaPausaMovidaComTudoOuvido() async {
  final it = await umEnsaioGravado(
    const [_aParte],
    numaSala: SalaHarness()
      ..recorder.rehearsalSpeaks = aSpokenWav(
        gaps: [(_s(3.0), _s(3.4)), (_s(6.0), _s(6.4))],
      ),
  );
  it.harness.room.listeningUnheardTakeIds = [it.partes.single.takeId!];
  it.sala.startRetro();
  await waitFor(
    'a parte entrar no ar',
    () =>
        it.harness.playback.played.isNotEmpty &&
        it.harness.playback.played.last == it.partes.single.path &&
        it.harness.playback.sounding,
  );
  it.harness.room.listeningUnheardTakeIds = const [];
  await ouvirAteOFim(it, _aParte);
  await waitFor(
    'a primeira escuta acabar e a parte voltar ao ar',
    () =>
        !it.estado.btSoOuvir &&
        it.estado.btPhase == BtPhase.playing &&
        it.harness.playback.sounding,
  );
  await traduzirUmTrecho(it, _s(4.2));
  await waitFor(
    'a equipe voltar ao círculo',
    () => it.estado.btPhase == BtPhase.playing,
  );
  if (!it.estado.btClipRodando) it.sala.ouvirGravacao();
  await waitFor('a parte tocar', () => it.estado.btClipRodando);
  it.harness.playback.at = _aParte - _s(0.5);
  it.sala.ouvirGravacao();
  await waitFor('a parte pausar', () => !it.harness.playback.sounding);
  it.sala.ouvirGravacao();
  await waitFor('a parte seguir', () => it.estado.btClipRodando);
  it.harness.playback.at = _s(7.4);
  it.sala.retroTap();
  await waitFor('a pausa ficar', () => it.estado.btCorte == _s(6.2));
  it.sala.pausaUmPoucoAntes();
  await waitFor('a pausa andar', () => it.estado.btCorte == _s(5.8));
  it.harness.room
    ..verdictChecked = false
    ..verdictHasFinding = true;
  return it;
}

void main() {
  test(
    'terminei with a pause still on the move drops it before the room is asked, '
    'and the verdict comes back with no pause pending',
    () async {
      final it = await _umaPausaMovidaComTudoOuvido();
      expect(it.estado.canAdvanceToTheVerdict, isTrue);
      bool? cortadaNoPedido;
      Duration? corteNoPedido;
      it.harness.room.duranteOVeredito = () {
        cortadaNoPedido = it.estado.btCortado;
        corteNoPedido = it.estado.btCorte;
      };

      await pedirOVeredito(it);

      expect(
        cortadaNoPedido,
        isFalse,
        reason: 'a pausa movida seguia pendente enquanto a sala conferia',
      );
      expect(corteNoPedido, _s(3.2), reason: 'o corte não voltava ao cursor');
      expect(it.estado.btPhase, BtPhase.playing);
      expect(
        it.estado.btCortado,
        isFalse,
        reason: 'o veredito voltava com a pausa movida ainda pendente',
      );
    },
  );

  test(
    'after the verdict the circle never tells up to the dropped pause: the next '
    'frase runs from the cursor to a pause marked afresh',
    () async {
      final it = await _umaPausaMovidaComTudoOuvido();
      await pedirOVeredito(it);

      it.sala.retroTap();
      await settle();

      expect(
        it.estado.btPhase,
        BtPhase.playing,
        reason:
            'o primeiro toque depois do veredito abria o microfone de uma vez, '
            'até a pausa que a equipe já tinha deixado para trás',
      );
      it.sala.ouvirGravacao();
      await theClipOpens(it.harness);
      it.harness.playback.at = _s(8.8);
      it.sala.retroTap();
      await waitFor('a pausa nova ficar', () => it.estado.btCorte == _s(8.8));
      it.sala.retroTap();
      await waitFor(
        'o microfone abrir',
        () => it.estado.btPhase == BtPhase.capturing,
      );
      await confirmarATraducao(it.container);
      await waitFor(
        'a frase chegar à sala',
        () => it.harness.room.chunkSpans.length == 2,
      );

      expect(
        it.harness.room.chunkSpans.last,
        '3200-8800',
        reason: 'a frase subia até a pausa largada, 3200-5800',
      );
    },
  );

  test(
    'terminei while a frase the room sent back to be told again stands keeps '
    'its span, so the next tap tells it whole, never a zero-length piece',
    () async {
      final it = await _umaPausaMovidaComTudoOuvido();
      it.harness.room.verdictUntoldSegmentId =
          it.estado.btTrechos.single.segmentId;
      await pedirOVeredito(it);
      await waitFor(
        'a frase voltar para ser contada de novo',
        () => it.estado.btTrechoTraduzidoDeNovo != null,
      );
      it.harness.room.verdictUntoldSegmentId = null;
      await waitFor(
        'o terminei acender com a frase devolvida',
        () => it.estado.canAdvanceToTheVerdict,
      );

      await pedirOVeredito(it);
      it.sala.retroTap();
      await waitFor(
        'o microfone abrir na frase devolvida',
        () => it.estado.btPhase == BtPhase.capturing,
      );
      await confirmarATraducao(it.container);
      await waitFor(
        'a frase contada de novo chegar à sala',
        () => it.harness.room.replacesAsked.isNotEmpty,
      );

      expect(
        it.harness.room.replacesAsked.single,
        endsWith(':0-3200'),
        reason:
            'o terminei largava o fim da frase devolvida junto com a pausa, e '
            'a frase subia de novo sem comprimento nenhum',
      );
    },
  );
}
