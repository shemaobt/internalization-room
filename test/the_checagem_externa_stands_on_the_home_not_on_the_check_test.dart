import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/codigo_view.dart';

import 'a_change_over_an_approved_draft_takes_the_armed_tap_test.dart'
    show aprovadaNaCasa, aprovadaNaConferida;
import 'fakes.dart';
import 'scenario_helpers.dart' show byLabel, thePersonSign;

const _checagem = 'Checagem externa';
const _conferida = '✓ traduzida e conferida';
const _badge = '✓ aprovado como rascunho final (v1)';
const _doisOuvintes = 'checagem externa: 2 ouvintes';
const _naoAbre =
    'a checagem externa abre depois que o rascunho final é aprovado';
const _naoDeu = 'não deu para abrir a checagem externa — tentem de novo';
const _sinal = 'Um momento para uma pessoa';

bool _aberto(WidgetTester tester) =>
    tester.widget<Semantics>(byLabel(_checagem)).properties.enabled ?? true;

Future<void> _tocarNaChecagem(WidgetTester tester) async {
  await tester.ensureVisible(byLabel(_checagem));
  await tester.tap(byLabel(_checagem));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

SalaSessionState _sala(ProviderContainer container) =>
    container.read(salaSessionProvider);

void main() {
  testWidgets('after approval with two listeners, the check draws the (v1) '
      'badge and neither the listeners nor «Checagem externa», as hers draws '
      'them on the home only', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aprovadaNaConferida(
      tester,
      harness,
      approved: const ApprovedDraft(version: 1, listeners: 2),
    );

    expect(find.text(_badge), findsOneWidget);
    expect(
      find.text(_conferida),
      findsNothing,
      reason: 'a tela da checagem aprovada escrevia a linha que é só da casa',
    );
    expect(
      find.text(_doisOuvintes),
      findsNothing,
      reason: 'a tela da checagem escrevia a contagem de ouvintes da casa',
    );
    expect(
      byLabel(_checagem),
      findsNothing,
      reason: 'a tela da checagem oferecia a «Checagem externa» da casa',
    );
    closeTheRoom(container);
  });

  testWidgets('on the home, two listeners read «checagem externa: 2 ouvintes» '
      'beside the (v1) badge and «Checagem externa»', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aprovadaNaCasa(
      tester,
      harness,
      approved: const ApprovedDraft(version: 1, listeners: 2),
    );

    expect(find.text(_badge), findsOneWidget);
    expect(find.text(_doisOuvintes), findsOneWidget);
    expect(byLabel(_checagem), findsOneWidget);
    expect(
      tester.widget<Semantics>(byLabel(_checagem)).properties.button,
      true,
    );
    expect(_aberto(tester), isTrue);
    closeTheRoom(container);
  });

  testWidgets('one listener reads «checagem externa: 1 ouvinte» on the home', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aprovadaNaCasa(
      tester,
      harness,
      approved: const ApprovedDraft(version: 1, listeners: 1),
    );

    expect(find.text('checagem externa: 1 ouvinte'), findsOneWidget);
    closeTheRoom(container);
  });

  testWidgets('no listener draws no count on the home, and the button is '
      'still there', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aprovadaNaCasa(tester, harness);

    expect(find.textContaining('checagem externa:'), findsNothing);
    expect(byLabel(_checagem), findsOneWidget);
    closeTheRoom(container);
  });

  testWidgets('while a scene records, no lit «Checagem externa» stands on the '
      'home and the open asks the room nothing', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aprovadaNaCasa(tester, harness);
    final notifier = container.read(salaSessionProvider.notifier);
    notifier.gravarACena(1);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      _sala(container).microphoneOpen,
      isTrue,
      reason: 'o caso só mede alguma coisa com o microfone aberto',
    );

    expect(
      tester
          .widgetList<Semantics>(byLabel(_checagem))
          .where((button) => button.properties.enabled ?? true),
      isEmpty,
    );
    notifier.abrirAChecagemExterna();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      harness.room.externalChecksOpened,
      isEmpty,
      reason: 'a checagem abria enquanto uma cena gravava na casa',
    );
    closeTheRoom(container);
  });

  testWidgets('«Checagem externa» needs no facilitator\'s code, and over a '
      'draft the room no longer holds as approved the home says why, and the '
      'button and the badge leave with the read', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aprovadaNaCasa(tester, harness);
    harness.room.approvedDraft = null;

    await _tocarNaChecagem(tester);

    expect(
      find.text(_naoAbre),
      findsOneWidget,
      reason:
          'a recusa da abertura na casa não dizia nada, e a tela da checagem '
          'era a única que escrevia a linha dela',
    );
    expect(_sala(container).stage, SalaStage.ensaio);
    expect(byLabel(_checagem), findsNothing);
    expect(find.text(_badge), findsNothing);
    expect(find.byType(CodigoView), findsNothing);
    closeTheRoom(container);
  });

  testWidgets('when the room cannot answer, the home says «$_naoDeu»', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aprovadaNaCasa(tester, harness);
    harness.room.failExternalCheckOnceWith = const NetworkFailed('sem rede');

    await _tocarNaChecagem(tester);

    expect(find.text(_naoDeu), findsOneWidget);
    expect(find.text(_sinal), findsNothing);
    expect(thePersonSign, findsNothing);
    closeTheRoom(container);
  });

  testWidgets('a tap the room answers takes «$_naoDeu» away', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aprovadaNaCasa(tester, harness);
    harness.room.failExternalCheckOnceWith = const NetworkFailed('sem rede');
    await _tocarNaChecagem(tester);

    await _tocarNaChecagem(tester);

    expect(find.text(_naoDeu), findsNothing);
    expect(_sala(container).stage, SalaStage.checagem);
    closeTheRoom(container);
  });

  testWidgets('in English', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true, lingua: 'en');
    final container = await aprovadaNaCasa(
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
    closeTheRoom(container);
  });
}
