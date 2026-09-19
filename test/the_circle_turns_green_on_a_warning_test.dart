import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'session_notifier_test.dart' show inConversa, settle;

/// How many times the tablet has asked the room what it is doing.
int _stateReads(SalaHarness harness) =>
    harness.room.calls.where((call) => call == 'fetchState').length;

/// A whole turn, from the team touching the circle to the room hearing it.
Future<void> _aTurn(SalaSessionNotifier notifier) async {
  notifier.conversaTap();
  await settle();
  notifier.conversaTap();
  await settle();
}

void main() {
  test('a warning turns the circle green while the room goes on', () async {
    final harness = SalaHarness()
      ..room.serverStatus = 'needs_person'
      ..room.serverHalt = HaltKind.warning;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    await waitFor('a sala reler o estado', () => _stateReads(harness) > 0);
    await settle(const Duration(milliseconds: 300));

    expect(
      read().warning,
      isTrue,
      reason:
          'o aviso chega numa leitura de estado comum, sem parar a sala — '
          'e é isso que tem de acender o círculo, não uma parada que nunca chegou '
          'a existir',
    );
    expect(
      read().voice,
      VoiceState.invite,
      reason: 'nada é recusado à equipe: o aviso não é uma parada',
    );

    final turns = harness.room.turnsSent;
    await _aTurn(notifier);
    await waitFor(
      'o turno chegar à sala',
      () => harness.room.turnsSent > turns,
    );

    expect(
      harness.room.turnsSent,
      turns + 1,
      reason:
          'a sala segue de pé sob o aviso — um círculo verde sobre uma sala '
          'que na verdade tivesse parado seria a mesma mentira de antes, só que '
          'na cor oposta',
    );
  });

  test('a warning on a retold chunk turns the circle green too', () async {
    final harness = SalaHarness()..room.chunkNeedsPerson = true;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    notifier.startRetro();
    await settle();

    harness.playback.at = const Duration(seconds: 12);
    notifier.cortarTrecho();
    await settle();
    notifier.retroTap();
    await settle();

    expect(
      read().warning,
      isTrue,
      reason:
          'o pedaço veio com needs_person: true — o orçamento de retraduções '
          'do ENG-706, ou qualquer outro motivo do servidor — e isso é lido '
          'como aviso, não como parada (needsPerson continua falso)',
    );
    expect(
      read().needsPerson,
      isFalse,
      reason:
          'o mesmo pedaço não pode acender as duas leituras: uma pessoa é '
          'chamada para olhar, e nada é recusado à equipe',
    );

    final chunks = harness.room.chunksSent;
    harness.playback.at = const Duration(seconds: 30);
    notifier.cortarTrecho();
    await settle();
    notifier.retroTap();
    await settle();

    expect(
      harness.room.chunksSent,
      chunks + 1,
      reason:
          'e a retro segue de pé: o trecho seguinte é ouvido como qualquer '
          'outro, sob o aviso',
    );
  });

  test('a warning on a chunk the room never captured is not dropped', () async {
    final harness = SalaHarness()..room.chunkNeedsPerson = true;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    notifier.startRetro();
    await settle();

    // captured and needsPerson are independent on the wire: the very chunk that
    // carries the warning can also be the one the room made nothing out of.
    harness.room.chunkCaptured = false;
    harness.playback.at = const Duration(seconds: 12);
    notifier.cortarTrecho();
    await settle();
    notifier.retroTap();
    await settle();

    expect(
      read().warning,
      isTrue,
      reason:
          'a captura ter falhado não é o servidor recuando do aviso: as duas '
          'notícias chegam juntas, e perder uma para tratar a outra deixaria '
          'a equipe sem saber que uma pessoa foi chamada',
    );
  });

  test(
    'the warning goes away on the next state read that does not carry it',
    () async {
      final harness = SalaHarness()
        ..room.serverStatus = 'needs_person'
        ..room.serverHalt = HaltKind.warning;
      final container = await inConversa(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);

      await waitFor('o aviso chegar', () => read().warning);

      harness.room.serverStatus = 'in_progress';
      harness.room.serverHalt = HaltKind.unnamed;
      // A state read only happens on the tail of a turn — the same gesture the desk's
      // attending stands in for on this side of the fake.
      await _aTurn(notifier);
      await waitFor('a sala reler de novo', () => !read().warning);

      expect(
        read().warning,
        isFalse,
        reason:
            'um turno ter acontecido, ou a mesa ter marcado a sessão como '
            'atendida, chegam aqui do mesmo jeito: uma leitura de estado que não '
            'diz mais "warning" — e é ela, não o aviso em si, que apaga o círculo',
      );
      expect(read().needsPerson, isFalse);
    },
  );

  test('a blocking halt is not a warning, even mid-warning', () async {
    final harness = SalaHarness()
      ..room.serverStatus = 'needs_person'
      ..room.serverHalt = HaltKind.warning;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    await waitFor('o aviso chegar', () => read().warning);

    harness.room.serverHalt = HaltKind.blocking;
    // A warning starts no watch of its own — nothing was halted to watch — so the
    // room only learns the halt turned blocking on the tail of another turn, same as
    // any other state read in this file.
    await _aTurn(notifier);
    await waitFor('a sala parar de vez', () => read().needsPerson);

    expect(
      read().needsPerson,
      isTrue,
      reason:
          'a parada bloqueante é a parada de sempre, e continua parando a '
          'sala mesmo tendo chegado logo depois de um aviso',
    );
    expect(
      read().warning,
      isFalse,
      reason:
          'a leitura que bloqueia não é a leitura que avisa: um aviso de '
          'segundos atrás não sobrevive nela',
    );
  });
}
