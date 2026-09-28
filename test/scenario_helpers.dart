import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/bead_row.dart';
import 'package:internalization_room/features/sala/presentation/widgets/retro_view.dart';

import 'fakes.dart';
import 'um_ensaio_de_tres_partes.dart';

/// Finds a widget by the label its `Semantics` node carries — the room's own
/// tests read the screen the way a screen reader would, not by widget type.
Finder byLabel(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);

/// How many times the room has been asked to read the session's state back —
/// the only witness that a watch actually re-polled, since the watch itself
/// has no other observable trace.
int stateReads(SalaHarness harness) =>
    harness.room.calls.where((call) => call == 'fetchState').length;

/// Cut the stretch in the air at its end and tell it back whole.
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

/// Every stretch a `RetroView`'s bead row is showing, one entry per bead.
List<String> contas(WidgetTester tester) => [
  for (final conta
      in tester
          .widget<BeadRow>(
            find.descendant(
              of: find.byType(RetroView),
              matching: find.byType(BeadRow),
            ),
          )
          .entries)
    '${conta.fill.name}${conta.current ? ' com anel' : ''}',
];
