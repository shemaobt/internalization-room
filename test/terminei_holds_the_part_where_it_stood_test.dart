import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show settle;
import 'um_ensaio_de_tres_partes.dart';

Duration _s(double seconds) => Duration(milliseconds: (seconds * 1000).round());

const _aParte = Duration(seconds: 10);

Future<Sala> _umaParteOuvidaInteiraTocandoAosTres() async {
  final it = await umEnsaioGravado(const [_aParte]);
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
  await traduzirUmTrecho(it, _s(1.0));
  await waitFor(
    'a equipe voltar ao círculo',
    () => it.estado.btPhase == BtPhase.playing,
  );
  if (!it.estado.btClipRodando) it.sala.ouvirGravacao();
  await waitFor('a parte tocar', () => it.estado.btClipRodando);
  it.harness.playback.at = _s(3.0);
  return it;
}

void main() {
  test(
    'after a verdict the first circle tap marks a pause where the take stood '
    'at terminei, instead of doing nothing until play',
    () async {
      final it = await _umaParteOuvidaInteiraTocandoAosTres();
      it.harness.room
        ..verdictChecked = false
        ..verdictHasFinding = true;

      await pedirOVeredito(it);
      await settle();

      expect(it.estado.btPhase, BtPhase.playing);
      expect(
        it.estado.btClipPausada,
        isTrue,
        reason:
            'o terminei parava a gravação em vez de segurá-la, e a cabeça se '
            'perdia no veredito',
      );
      expect(it.harness.playback.at, _s(3.0));

      it.sala.retroTap();
      await settle();

      expect(
        it.estado.btCortado,
        isTrue,
        reason:
            'o primeiro toque no círculo depois do veredito não fazia nada: a '
            'equipe tinha de tocar, pausar e tocar de novo',
      );
      expect(it.estado.btCorte, _s(3.0));
      expect(
        it.estado.btPhase,
        BtPhase.playing,
        reason: 'o toque marca a pausa, não abre o microfone',
      );
    },
  );

  test('after her P2 pressed mid-part, ouvir goes on with the held part, not '
      'with the first part from the start', () async {
    final it = await _umaParteOuvidaInteiraTocandoAosTres();
    final take = it.partes.single.takeId!;
    it.harness.room
      ..verdictRefusal = CheckRefusal.partUnheard
      ..verdictFixedLine = 'P2'
      ..verdictUnheardTakeIds = [take]
      ..listeningUnheardTakeIds = [take];

    await pedirOVeredito(it);
    await settle();
    expect(it.estado.btRecusa, CheckRefusal.partUnheard);
    final tocadas = it.harness.playback.played.length;

    it.sala.ouvirGravacao();
    await waitFor('a gravação voltar', () => it.estado.btClipRodando);

    expect(
      it.harness.playback.played.length,
      tocadas,
      reason:
          'o toque em ouvir recomeçava a primeira parte do começo, em vez '
          'de seguir de onde o terminei a segurou',
    );
    expect(it.harness.playback.at, _s(3.0));
  });
}
