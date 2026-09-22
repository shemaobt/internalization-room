import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';

Future<void> settle([Duration delay = const Duration(milliseconds: 120)]) =>
    Future<void>.delayed(delay);

class _Sala {
  final SalaHarness harness;
  final ProviderContainer container;

  _Sala(this.harness, this.container);

  SalaSessionNotifier get sala => container.read(salaSessionProvider.notifier);

  SalaSessionState get estado => container.read(salaSessionProvider);

  /// Enter a passage the wheel offers, and wait for the circle to invite the team.
  Future<void> entrar(String pericope) async {
    await sala.goConversa(pericope: pericope);
    await waitFor(
      'a passagem $pericope abrir para a equipe',
      () =>
          estado.stage == SalaStage.conversa &&
          estado.voice == VoiceState.invite,
    );
  }

  /// The team says one whole turn: the circle opens the microphone and closes it.
  Future<void> falar(int turno) async {
    sala.conversaTap();
    await waitFor(
      'o microfone abrir',
      () => estado.voice == VoiceState.listening,
    );
    sala.conversaTap();
    await waitFor(
      'a fala da equipe chegar à sala',
      () => harness.room.turnsSent == turno,
    );
  }
}

Future<_Sala> _aRodaAberta() async {
  final harness = SalaHarness();
  final container = harness.container();
  addTearDown(container.dispose);
  final sala = _Sala(harness, container);
  await sala.sala.abrirEscolha();
  await waitFor('a roda abrir', () => sala.estado.naRoda != null);
  return sala;
}

/// The lines the room said to fill a wait, in the order it said them. They rotate, so a
/// passage that starts over and hears the second one first is a passage carrying the
/// count of the one before it.
List<String> _esperasDitas(SalaHarness harness) => [
  for (final asset in harness.voice.assets)
    if (instantAckLines.any(
      (line) => asset == fixedLineAsset(line, testLanguage),
    ))
      asset,
];

void main() {
  test('a passagem nova não herda as falhas de captura da anterior', () async {
    final it = await _aRodaAberta();
    await it.entrar('P01');
    it.harness.recorder.startThrows = true;
    it.sala.conversaTap();
    await waitFor(
      'a sala responder ao gravador que não abriu',
      () =>
          it.harness.recorder.captures == 1 &&
          it.estado.voice != VoiceState.listening,
    );

    await it.entrar('P02');
    it.sala.conversaTap();
    await waitFor(
      'a sala responder ao gravador que não abriu na passagem nova',
      () =>
          it.harness.recorder.captures == 2 &&
          it.estado.voice != VoiceState.listening,
    );

    expect(
      it.estado.needsPerson,
      isFalse,
      reason:
          'a conta das falhas de captura é por passagem: herdada, a '
          'primeira falha da passagem nova já chama uma pessoa',
    );
  });

  test('a passagem nova começa a rodar as esperas do início', () async {
    final it = await _aRodaAberta();
    await it.entrar('P01');
    await it.falar(1);

    await it.entrar('P02');
    await it.falar(2);

    final primeira = fixedLineAsset(instantAckLines.first, testLanguage);
    expect(
      _esperasDitas(it.harness),
      [primeira, primeira],
      reason:
          'a rotação das esperas é da passagem: herdada, a equipe ouve '
          'a passagem nova começar no meio da volta anterior',
    );
  });

  test(
    'a passagem nova abre o microfone depois de um que ficou a abrir',
    () async {
      final it = await _aRodaAberta();
      await it.entrar('P01');
      it.harness.recorder.holdNextStart();
      addTearDown(it.harness.recorder.finishStart);
      it.sala.conversaTap();
      await waitFor(
        'o microfone da passagem anterior ficar a abrir',
        () => it.estado.voice == VoiceState.listening,
      );

      await it.entrar('P02');
      it.sala.conversaTap();
      await waitFor(
        'o gravador ser mesmo chamado na passagem nova',
        () =>
            it.harness.sounds.where((som) => som == 'recorder:start').length ==
            2,
      );

      expect(
        it.estado.voice,
        VoiceState.listening,
        reason:
            'a tranca do microfone a abrir é da passagem: herdada, o '
            'primeiro toque da passagem nova é engolido em silêncio',
      );
    },
  );

  test(
    'o microfone que a passagem anterior deixou a abrir não solta o desta',
    () async {
      final it = await _aRodaAberta();
      await it.entrar('P01');
      it.harness.recorder.holdNextStart();
      it.sala.conversaTap();
      await waitFor(
        'o microfone da passagem anterior ficar a abrir',
        () => it.estado.voice == VoiceState.listening,
      );

      await it.entrar('P02');
      it.harness.recorder.holdNextStart();
      addTearDown(it.harness.recorder.finishStart);
      it.sala.conversaTap();
      await waitFor(
        'o microfone desta passagem ficar a abrir',
        () =>
            it.harness.sounds.where((som) => som == 'recorder:start').length ==
            2,
      );
      it.harness.recorder.finishStart();
      await settle();

      it.sala.conversaTap();
      await settle();

      expect(
        it.harness.room.turnsSent,
        0,
        reason:
            'a resposta de um microfone de outra passagem não abre a '
            'tranca desta: o segundo toque cairia num stop sobre um gravador '
            'que ainda abre, e mandaria à sala uma fala que ninguém gravou',
      );
      expect(it.estado.voice, VoiceState.listening);
    },
  );
}
