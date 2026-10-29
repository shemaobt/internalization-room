import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/approval_answer.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';

import 'a_change_over_an_approved_draft_takes_the_armed_tap_test.dart'
    show aprovadaNaConferida;
import 'fakes.dart';
import 'scenario_helpers.dart' show byLabel;
import 'the_back_translation_is_told_by_beads_test.dart' show tocar;

const _aprovar = 'Aprovar como rascunho final';
const _salvo = 'Ensaio salvo';
const _pronto = 'Pronto';
const _naoDeu = 'não deu para conferir agora — tentem de novo';
const _forcada = ApprovedDraft(version: 1, forced: true);

String _badge(int v) => '✓ aprovado como rascunho final (v$v)';

Future<void> _passo(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 100));

Future<void> _naCasa(
  WidgetTester tester,
  SalaHarness harness,
  ProviderContainer container, {
  bool checked = true,
}) async {
  harness.room.retroSoFar = BackTranslationProgress(checked: checked);
  container.read(salaSessionProvider.notifier).goEnsaio();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(seconds: 2));
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _aprovadaDeNovoComoV2(
  WidgetTester tester,
  SalaHarness harness,
) async {
  harness.room.release = const ApprovalAnswer(releaseId: 'solta-2', version: 2);
  harness.room.approvedDraft = const ApprovedDraft(version: 2);
  await tocar(tester, _aprovar);
  await waitFor(
    'o ensaio salvo',
    () => find.text(_salvo).evaluate().isNotEmpty,
    step: () => _passo(tester),
  );
  await tester.tap(byLabel(_pronto));
  await tester.pump(const Duration(milliseconds: 800));
}

void main() {
  testWidgets('a forced draft whose telling is conferida offers «$_aprovar» '
      'with its badge under it, and the press approves it as v2', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aprovadaNaConferida(
      tester,
      harness,
      approved: _forcada,
    );

    expect(find.text(_badge(1)), findsOneWidget);
    expect(
      byLabel(_aprovar),
      findsOneWidget,
      reason:
          'a narração conferida de uma versão forçada não podia ser aprovada',
    );
    expect(
      tester.getBottomLeft(byLabel(_aprovar)).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.text(_badge(1))).dy),
      reason: 'o selo não vinha debaixo do botão, como o dela',
    );

    await _aprovadaDeNovoComoV2(tester, harness);

    expect(harness.room.releasesAsked, hasLength(2));
    expect(find.text(_badge(2)), findsOneWidget);
    expect(byLabel(_aprovar), findsNothing);
    closeTheRoom(container);
  });

  testWidgets('on a phone as narrow as the iPhone SE the forced draft\'s '
      'checked phase draws «$_aprovar» and its badge, and nothing overflows', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aprovadaNaConferida(
      tester,
      harness,
      approved: _forcada,
    );
    tester.view
      ..physicalSize = const Size(375, 667)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _passo(tester);

    expect(
      tester.takeException(),
      isNull,
      reason: 'a fileira do botão e do selo transbordava no iPhone SE',
    );
    expect(byLabel(_aprovar), findsOneWidget);
    expect(find.text(_badge(1)), findsOneWidget);
    closeTheRoom(container);
  });

  testWidgets('a forced draft the room never called checked is never offered '
      '«$_aprovar»', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aprovadaNaConferida(
      tester,
      harness,
      approved: _forcada,
    );

    await _naCasa(tester, harness, container, checked: false);

    expect(find.text(_badge(1)), findsOneWidget);
    expect(
      byLabel(_aprovar),
      findsNothing,
      reason: 'uma versão forçada sem conferência oferecia aprovar de novo',
    );
    closeTheRoom(container);
  });

  testWidgets('a draft nobody forced never offers «$_aprovar» again', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aprovadaNaConferida(tester, harness);

    expect(find.text(_badge(1)), findsOneWidget);
    expect(byLabel(_aprovar), findsNothing);

    await _naCasa(tester, harness, container);

    expect(find.text(_badge(1)), findsOneWidget);
    expect(byLabel(_aprovar), findsNothing);
    closeTheRoom(container);
  });

  testWidgets('the recording home of a forced, checked draft offers '
      '«$_aprovar» beside its badge, and the press approves it as v2', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aprovadaNaConferida(
      tester,
      harness,
      approved: _forcada,
    );
    await _naCasa(tester, harness, container);

    expect(find.text(_badge(1)), findsOneWidget);
    expect(
      byLabel(_aprovar),
      findsOneWidget,
      reason: 'a casa de uma versão forçada e conferida não oferecia aprovar',
    );

    await _aprovadaDeNovoComoV2(tester, harness);

    expect(harness.room.releasesAsked, hasLength(2));
    expect(find.text(_badge(2)), findsOneWidget);
    expect(byLabel(_aprovar), findsNothing);
    closeTheRoom(container);
  });

  testWidgets('a room that answers with the forced version itself approved '
      'nothing: no «$_salvo», and «$_naoDeu»', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aprovadaNaConferida(
      tester,
      harness,
      approved: _forcada,
    );

    await tocar(tester, _aprovar);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 1));

    expect(harness.room.releasesAsked, hasLength(2));
    expect(
      find.text(_salvo),
      findsNothing,
      reason: 'a sala devolvia a v1 forçada e o tablet dizia que aprovou',
    );
    expect(find.text(_naoDeu), findsOneWidget);
    closeTheRoom(container);
  });
}
