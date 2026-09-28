import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';
import 'session_notifier_test.dart' show inConversa;

/// A whole turn, from the team touching the circle to the room hearing it.
Future<void> _aTurn(SalaSessionNotifier notifier) async {
  notifier.conversaTap();
  await settle();
  notifier.conversaTap();
  await settle();
}

void main() {
  test('a warning stands while the room goes on', () async {
    final harness = SalaHarness()
      ..room.serverStatus = 'needs_person'
      ..room.serverHalt = HaltKind.warning;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    await waitFor('a sala reler o estado', () => stateReads(harness) > 0);
    await settle(const Duration(milliseconds: 300));

    expect(
      read().warning,
      isTrue,
      reason:
          'o aviso chega numa leitura de estado comum, sem parar a sala — '
          'e é isso que tem de acender a marca ao lado do círculo, não uma '
          'parada que nunca chegou a existir',
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
          'a sala segue de pé sob o aviso — a marca ao lado do círculo numa '
          'sala que na verdade tivesse parado seria a mesma mentira de '
          'antes, só que na cor oposta',
    );
  });

  test('the warning goes away on the next state read that does not carry it', () async {
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
    // Either read turns it off: the tail of this turn, or the beat of the watch the
    // warning armed. What the case is about is the reading, not which one got there.
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
  });

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
    // The warning armed the watch, so the room can learn the halt turned blocking on a
    // beat of its own; the turn is the other way in, and either one stops the team.
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
