import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/presentation/widgets/codigo_view.dart';

import 'a_change_over_an_approved_draft_takes_the_armed_tap_test.dart'
    show aprovadaNaConferida, tocarNaLista, tocarOCirculo;
import 'a_wav_take.dart';
import 'fakes.dart';
import 'scenario_helpers.dart' show byLabel;

const _checagem = 'Checagem externa';
const _conferida = '✓ traduzida e conferida';
const _badge = '✓ aprovado como rascunho final (v1)';
const _naoAbre =
    'a checagem externa abre depois que o rascunho final é aprovado';
const _naoDeu = 'não deu para abrir a checagem externa — tentem de novo';
const _sinal = 'Um momento para uma pessoa';

bool _aberto(WidgetTester tester) =>
    tester.widget<Semantics>(byLabel(_checagem)).properties.enabled ?? true;

int _leituras(SalaHarness harness) =>
    harness.room.calls.where((call) => call == 'fetchState').length;

Future<void> _tocarNaChecagem(WidgetTester tester) async {
  await tester.ensureVisible(byLabel(_checagem));
  await tester.tap(byLabel(_checagem));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('after approval with two listeners, the Back-translation shows '
      'both ticks, (v1), the listeners and «Checagem externa»', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aprovadaNaConferida(
      tester,
      harness,
      approved: const ApprovedDraft(version: 1, listeners: 2),
    );

    expect(find.text(_conferida), findsOneWidget);
    expect(find.text(_badge), findsOneWidget);
    expect(find.text('checagem externa: 2 ouvintes'), findsOneWidget);
    expect(byLabel(_checagem), findsOneWidget);
    expect(
      tester.widget<Semantics>(byLabel(_checagem)).properties.button,
      true,
    );
    expect(_aberto(tester), isTrue);
    closeTheRoom(container);
  });

  testWidgets('one listener reads «checagem externa: 1 ouvinte»', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aprovadaNaConferida(
      tester,
      harness,
      approved: const ApprovedDraft(version: 1, listeners: 1),
    );

    expect(find.text('checagem externa: 1 ouvinte'), findsOneWidget);
    closeTheRoom(container);
  });

  testWidgets('no listener draws no count, and the button is still there', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aprovadaNaConferida(tester, harness);

    expect(find.textContaining('checagem externa:'), findsNothing);
    expect(byLabel(_checagem), findsOneWidget);
    closeTheRoom(container);
  });

  testWidgets('«Pronto» lands on «Checagem externa»', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aprovadaNaConferida(tester, harness);

    expect(byLabel(_checagem), findsOneWidget);
    closeTheRoom(container);
  });

  testWidgets('while recording, «Checagem externa» is closed', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aprovadaNaConferida(tester, harness);
    await tocarNaLista(tester, 'regravar a frase 2');
    await tester.pump(const Duration(seconds: 2));
    await tocarNaLista(
      tester,
      'toquem de novo: isto abre de novo o rascunho aprovado',
    );
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    await tocarOCirculo(tester);

    expect(_aberto(tester), isFalse);
    final antes = _leituras(harness);
    await _tocarNaChecagem(tester);
    expect(
      _leituras(harness),
      antes,
      reason: 'a checagem abria com o microfone aberto',
    );

    harness.recorder.rehearsalSpeaks = aSpokenWav(
      length: const Duration(milliseconds: 200),
    );
    await tocarOCirculo(tester);
    await tester.pump(const Duration(milliseconds: 100));

    expect(_aberto(tester), isTrue);
    closeTheRoom(container);
  });

  testWidgets('«Checagem externa» needs no facilitator\'s code, and over a '
      'draft the room no longer holds as approved it says why', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aprovadaNaConferida(tester, harness);
    harness.room.approvedDraft = null;

    await _tocarNaChecagem(tester);

    expect(find.text(_naoAbre), findsOneWidget);
    expect(byLabel(_checagem), findsNothing);
    expect(find.text(_badge), findsNothing);
    expect(find.byType(CodigoView), findsNothing);
    closeTheRoom(container);
  });

  testWidgets('when the room cannot answer, it says «$_naoDeu»', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aprovadaNaConferida(tester, harness);
    harness.room.failStateOnceWith = const NetworkFailed('sem rede');

    await _tocarNaChecagem(tester);

    expect(find.text(_naoDeu), findsOneWidget);
    expect(find.text(_sinal), findsNothing);
    expect(byLabel(_sinal), findsNothing);
    closeTheRoom(container);
  });

  testWidgets('a tap the room answers takes «$_naoDeu» away', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aprovadaNaConferida(tester, harness);
    harness.room.failStateOnceWith = const NetworkFailed('sem rede');
    await _tocarNaChecagem(tester);

    await _tocarNaChecagem(tester);

    expect(find.text(_naoDeu), findsNothing);
    expect(byLabel(_checagem), findsOneWidget);
    closeTheRoom(container);
  });

  testWidgets('in English', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true, lingua: 'en');
    final container = await aprovadaNaConferida(
      tester,
      harness,
      approved: const ApprovedDraft(version: 1, listeners: 2),
      caminho: (
        terminei: 'done',
        aprovar: 'Approve as the final draft',
        salvo: 'Rehearsal saved',
        pronto: 'Done',
      ),
    );

    expect(byLabel('External check'), findsOneWidget);
    expect(find.text('external check: 2 listeners'), findsOneWidget);

    await tocarNaLista(tester, 're-record sentence 2');

    expect(
      find.text('tap again: this re-opens the approved draft'),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 7));
    closeTheRoom(container);
  });
}
