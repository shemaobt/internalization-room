import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/presentation/widgets/bead_row.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/ensaio_view.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;

Finder byLabel(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);

const _gravarOEnsaio = 'Tocar para gravar o ensaio';
const _gravarAProxima = 'Tocar para gravar a próxima parte';
const _terminar = 'Tocar ao terminar';
const _confirmar = 'Confirmar esta parte';
const _gravarDeNovo = 'Tocar para gravar esta parte de novo';

Future<void> _tocar(WidgetTester tester, String label) async {
  await tester.tap(byLabel(label));
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _gravarEConfirmar(WidgetTester tester, String circulo) async {
  await _tocar(tester, circulo);
  await _tocar(tester, _terminar);
  await _tocar(tester, _confirmar);
  await letTheRehearsalReachTheRoom(tester);
}

Future<void> _ateEnsaio(
  WidgetTester tester,
  ProviderContainer container,
  EnsaioStatus alvo,
) async {
  for (
    var vezes = 0;
    vezes < 40 && container.read(salaSessionProvider).ensaio != alvo;
    vezes++
  ) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

List<BeadRowEntry> _contas(WidgetTester tester) => tester
    .widget<BeadRow>(
      find.descendant(
        of: find.byType(EnsaioView),
        matching: find.byType(BeadRow),
      ),
    )
    .entries;

/// The rehearsal, recorded and confirmed in three parts, standing with the play and the
/// advance disc both ready and nothing pressed yet.
Future<ProviderContainer> _ensaioDeTresPartes(
  WidgetTester tester, {
  SalaHarness? harness,
}) async {
  final container = await pumpSala(
    tester,
    harness ?? SalaHarness(filaEmMemoria: true),
  );
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.goConversa();
  await tester.pump(const Duration(milliseconds: 200));
  notifier.goEnsaio();
  await tester.pump(const Duration(milliseconds: 400));
  await _gravarEConfirmar(tester, _gravarOEnsaio);
  await _gravarEConfirmar(tester, _gravarAProxima);
  await _gravarEConfirmar(tester, _gravarAProxima);
  return container;
}

/// A team standing on a finding the analyst addressed to the one part recorded, on the
/// rehearsal screen with the microphone inviting a re-record.
Future<(ProviderContainer, SalaHarness)> _achadoNaParteUm(
  WidgetTester tester,
) async {
  final harness = SalaHarness()
    ..room.verdictChecked = false
    ..room.verdictFinding = BtFindingKind.missing
    ..room.verdictFindingPlace = 0;
  final container = await pumpSala(tester, harness);
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.goConversa();
  await tester.pump(const Duration(milliseconds: 200));
  notifier.goEnsaio();
  await tester.pump(const Duration(milliseconds: 100));
  notifier.ensaioTap();
  notifier.ensaioTap();
  await tester.pump(const Duration(milliseconds: 100));
  notifier.takeKeep();
  for (
    var vezes = 0;
    vezes < 40 &&
        container.read(salaSessionProvider).partes.first.takeId == null;
    vezes++
  ) {
    await letTheRehearsalReachTheRoom(tester);
  }
  notifier.startRetro();
  await tester.pump(const Duration(milliseconds: 200));
  harness.playback.at = const Duration(seconds: 10);
  notifier.cortarTrecho();
  notifier.retroTap();
  await tester.pump(const Duration(milliseconds: 200));
  notifier.retroTap();
  await tester.pump(const Duration(milliseconds: 300));
  await notifier.confirmarTraducao();
  await tester.pump(const Duration(milliseconds: 600));
  harness.playback.finishPlayback();
  await tester.pump(const Duration(milliseconds: 200));
  await notifier.finishBackTranslation();
  await tester.pump(const Duration(milliseconds: 300));
  notifier.gravarAParteDeNovo();
  await tester.pump(const Duration(milliseconds: 200));
  return (container, harness);
}

void main() {
  testWidgets(
    'a batida na segunda conta acende o anel, toca só a parte 2 e para no '
    'fim dela',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await _ensaioDeTresPartes(tester, harness: harness);
      final partes = container.read(salaSessionProvider).partes;

      await _tocar(tester, 'Parte 2');

      expect(
        [for (final conta in _contas(tester)) conta.current],
        [false, true, false],
      );
      expect(harness.playback.played, [partes[1].path]);
      expect(harness.playback.playedFrom, [Duration.zero]);

      harness.playback.finishPlayback();
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        harness.playback.played,
        [partes[1].path],
        reason: 'a parte 2 termina sem carregar para a parte 3',
      );
      expect(
        [for (final conta in _contas(tester)) conta.current],
        [false, false, false],
        reason: 'nada mais soa; o anel se apaga',
      );
    },
  );

  testWidgets('o anel segue a parte que soa enquanto o ensaio inteiro toca', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _ensaioDeTresPartes(tester, harness: harness);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.playTheRehearsal();
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      [for (final conta in _contas(tester)) conta.current],
      [true, false, false],
    );

    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      [for (final conta in _contas(tester)) conta.current],
      [false, true, false],
      reason: 'o anel atravessa a fronteira para a parte 2',
    );

    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      [for (final conta in _contas(tester)) conta.current],
      [false, false, true],
    );

    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      [for (final conta in _contas(tester)) conta.current],
      [false, false, false],
      reason: 'o ensaio acabou; nenhuma conta soa',
    );
  });

  testWidgets('a conta de uma parte ainda não entregue mostra isso', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    harness.room.refuseTake = 'ensaio/${KeptScope.parte(2)}';
    final container = await _ensaioDeTresPartes(tester, harness: harness);
    final notifier = container.read(salaSessionProvider.notifier);
    await harness.takes.flush();
    await notifier.refreshUnsent();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      [for (final conta in _contas(tester)) conta.delivered],
      [true, false, true],
    );
    expect(
      _contas(tester)[1].semanticLabel,
      'Parte 2, ainda não enviada',
      reason: 'a única coisa que uma sala sem texto tem para dizer isso',
    );
  });

  testWidgets('tocar na conta que soa pausa; tocar em outra troca de parte', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _ensaioDeTresPartes(tester, harness: harness);
    final notifier = container.read(salaSessionProvider.notifier);
    final partes = container.read(salaSessionProvider).partes;

    notifier.tocarAParte(0);
    await tester.pump(const Duration(milliseconds: 200));
    expect(harness.playback.sounding, isTrue);
    expect(harness.playback.played, [partes[0].path]);

    notifier.tocarAParte(0);
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      harness.playback.sounding,
      isFalse,
      reason: 'a mesma conta pausa; não para',
    );
    expect(harness.playback.paused, isTrue);
    expect(
      container.read(salaSessionProvider).parteTocando,
      0,
      reason: 'o anel continua na parte pausada',
    );

    notifier.tocarAParte(2);
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      harness.playback.played,
      [partes[0].path, partes[2].path],
      reason: 'a terceira conta toca a parte 3, não retoma a 1',
    );
    expect(harness.playback.sounding, isTrue);
    expect(
      [for (final conta in _contas(tester)) conta.current],
      [false, false, true],
    );
  });

  testWidgets(
    'o círculo de uma parte devolvida por um achado diz o texto da placa',
    (tester) async {
      await _achadoNaParteUm(tester);

      expect(byLabel(_gravarDeNovo), findsOneWidget);
    },
  );

  testWidgets(
    'o anel segue a parte pendente que ficou no lugar da regravação',
    (tester) async {
      final (container, harness) = await _achadoNaParteUm(tester);
      final notifier = container.read(salaSessionProvider.notifier);
      notifier.ensaioTap();
      await _ateEnsaio(tester, container, EnsaioStatus.recording);
      notifier.ensaioTap();
      await _ateEnsaio(tester, container, EnsaioStatus.recorded);

      notifier.playTheRehearsal();
      for (var vezes = 0; vezes < 40 && !harness.playback.sounding; vezes++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(
        [for (final conta in _contas(tester)) conta.current],
        [true],
        reason: 'o anel segue a gravação pendente que ficou no lugar da parte',
      );
      expect(harness.playback.sounding, isTrue);

      harness.playback.finishPlayback();
      await tester.pump(const Duration(milliseconds: 200));
    },
  );
}
