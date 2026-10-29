import 'dart:async';

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'um_ensaio_de_tres_partes.dart';
import 'scenario_helpers.dart';

const _gravarOEnsaio = 'Gravar';
const _gravarAProxima = 'Gravar';
const _terminar = 'Parar';
const _confirmar = 'Enviar a gravação';

Future<void> _tocar(WidgetTester tester, String label) async {
  await tester.ensureVisible(offTheRows(label));
  await tester.tap(offTheRows(label));
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _gravarEConfirmar(
  WidgetTester tester,
  ProviderContainer container,
  SalaHarness harness,
  String circulo,
) async {
  await _tocar(tester, circulo);
  await _tocar(tester, _terminar);
  await _tocar(tester, _confirmar);
  final parts = container.read(salaSessionProvider).partes.length;
  if (harness.room.refuseTake == null) {
    await theRoomNamesTheParts(tester, container, parts: parts);
  } else {
    await waitFor(
      'a sala ser pedida pela parte $parts',
      () =>
          harness.room.calls.where((call) => call == 'sendTake').length >=
          parts,
      step: () => letTheRehearsalReachTheRoom(tester),
    );
  }
}

Future<void> _ateEnsaio(
  WidgetTester tester,
  ProviderContainer container,
  EnsaioStatus alvo,
) => waitFor(
  'o ensaio chegar a $alvo',
  () => container.read(salaSessionProvider).ensaio == alvo,
  limit: const Duration(seconds: 2),
  step: () => tester.pump(const Duration(milliseconds: 100)),
);

List<SemanticsProperties> _linhas(WidgetTester tester) => [
  for (var cena = 1; linhaDoEnsaio(cena).evaluate().isNotEmpty; cena++)
    tester.widget<Semantics>(linhaDoEnsaio(cena)).properties,
];

/// The rehearsal, recorded and confirmed in three parts, standing with the play and the
/// advance disc both ready and nothing pressed yet.
Future<ProviderContainer> _ensaioDeTresPartes(
  WidgetTester tester, {
  SalaHarness? harness,
}) async {
  final room = harness ?? SalaHarness(filaEmMemoria: true);
  final container = await pumpSala(tester, room);
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.goConversa(book: 'Ruth');
  await tester.pump(const Duration(milliseconds: 200));
  notifier.goEnsaio();
  await tester.pump(const Duration(milliseconds: 400));
  await _gravarEConfirmar(tester, container, room, _gravarOEnsaio);
  await _gravarEConfirmar(tester, container, room, _gravarAProxima);
  await _gravarEConfirmar(tester, container, room, _gravarAProxima);
  return container;
}

/// A team standing on a finding addressed to part 2 of a three-part rehearsal, every part
/// already told back whole, back on the rehearsal with nothing recorded yet.
Future<Sala> _achadoNaParteDois() async {
  final it = await umEnsaioDeTresPartesContadoInteiro();
  it.harness.room
    ..verdictChecked = false
    ..verdictHasFinding = true
    ..verdictFindingPlace = 1;
  await pedirOVeredito(it);
  it.sala.leaveTheBackTranslation();
  return it;
}

/// Starts a re-record of the part a finding named and stops it, leaving the take pending —
/// waiting for the green check, not yet in the part's place. The sibling of [regravarAParte],
/// which confirms it instead.
Future<void> _regravarAParteSemConfirmar(Sala it) async {
  it.sala.gravarACena(2);
  await waitFor(
    'a gravação da parte de novo começar',
    () => it.estado.ensaio == EnsaioStatus.recording,
  );
  it.sala.gravarACena(2);
  await waitFor(
    'a gravação da parte de novo terminar',
    () => it.estado.ensaio == EnsaioStatus.recorded,
  );
}

/// The same re-record, driven by fixed pumps instead of [waitFor]: `testWidgets` fakes time
/// for the whole test body, so a real `Future.delayed` never fires without one.
Future<void> _regravarAParteSemConfirmarNaTela(
  WidgetTester tester,
  SalaSessionNotifier notifier,
) async {
  notifier.gravarACena(2);
  await tester.pump(const Duration(milliseconds: 100));
  notifier.gravarACena(2);
  await tester.pump(const Duration(milliseconds: 100));
}

/// The widget-tree sibling of [_achadoNaParteDois]: the same three-part rehearsal, told
/// back whole and addressed by a finding at part 2, reached entirely through gestures the
/// team has on screen (no [waitFor]), so it can be pumped inside a `testWidgets` body.
Future<ProviderContainer> _achadoNaParteDoisNaTela(
  WidgetTester tester,
  SalaHarness harness,
) async {
  harness.room
    ..verdictChecked = false
    ..verdictHasFinding = true
    ..verdictFindingPlace = 1;
  harness.playback.length = umaParteInteira;
  final container = harness.container();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await tester.pump(const Duration(milliseconds: 100));

  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.goConversa(book: 'Ruth');
  await tester.pump(const Duration(milliseconds: 200));
  notifier.goEnsaio();
  await tester.pump(const Duration(milliseconds: 100));
  for (var parte = 0; parte < 3; parte++) {
    await gravarUmaParte(tester, container);
  }
  notifier.startRetro();
  await tester.pump(const Duration(milliseconds: 200));
  for (var parte = 0; parte < 3; parte++) {
    await traduzirAParteInteira(tester, harness, container);
    if (parte < 2) {
      notifier.ouvirGravacao();
      await tester.pump(const Duration(milliseconds: 200));
    }
  }
  await notifier.finishBackTranslation();
  await tester.pump(const Duration(milliseconds: 300));
  notifier.leaveTheBackTranslation();
  await tester.pump(const Duration(milliseconds: 200));
  return container;
}

void main() {
  testWidgets(
    'the three parts are all named by the room when the helper returns, not after a clock',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true)
        ..room.takeLandsAfter = const Duration(seconds: 1);
      final container = await _ensaioDeTresPartes(tester, harness: harness);

      final partes = container.read(salaSessionProvider).partes;
      expect(partes, hasLength(3));
      expect(
        partes.map((parte) => parte.takeId),
        everyElement(isNotNull),
        reason:
            'as partes seguiam sem nome quando o ajudante voltava, e a '
            'batida no bead tocava uma parte que a sala ainda não tinha dado',
      );
      closeTheRoom(container);
    },
  );

  testWidgets(
    'a wait for a rehearsal status that never comes fails at its deadline, '
    'not in silence',
    (tester) async {
      final container = await _ensaioDeTresPartes(tester);

      await expectLater(
        () => _ateEnsaio(tester, container, EnsaioStatus.recording),
        throwsA(isA<TimeoutException>()),
        reason:
            'a espera devolvia depois de quarenta quadros sem ter visto o '
            'estado, e o teste seguia como se ele tivesse chegado',
      );
      closeTheRoom(container);
    },
  );

  testWidgets(
    'a batida no segundo bead acende o anel, toca só a parte 2 e para no '
    'fim dela',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await _ensaioDeTresPartes(tester, harness: harness);
      final partes = container.read(salaSessionProvider).partes;

      await tester.tap(
        find.descendant(of: linhaDoEnsaio(2), matching: byLabel('Ouvir')),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        [for (final linha in _linhas(tester)) linha.selected == true],
        [false, true, false, false],
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
        [for (final linha in _linhas(tester)) linha.selected == true],
        [false, false, false, false],
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
      [for (final linha in _linhas(tester)) linha.selected == true],
      [true, false, false, false],
    );

    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      [for (final linha in _linhas(tester)) linha.selected == true],
      [false, true, false, false],
      reason: 'o anel atravessa a fronteira para a parte 2',
    );

    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      [for (final linha in _linhas(tester)) linha.selected == true],
      [false, false, true, false],
    );

    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      [for (final linha in _linhas(tester)) linha.selected == true],
      [false, false, false, false],
      reason: 'o ensaio acabou; nenhum bead soa',
    );
  });

  testWidgets('a linha de uma parte que falhou ao subir diz isso, e a marca '
      'some ao ser entregue', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    harness.room.refuseTake = 'ensaio/${KeptScope.parte(2)}';
    final container = await _ensaioDeTresPartes(tester, harness: harness);
    final notifier = container.read(salaSessionProvider.notifier);
    await harness.takes.flush();
    await notifier.refreshUnsent();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      [
        for (var cena = 1; cena <= 4; cena++)
          find
              .descendant(
                of: linhaDoEnsaio(cena),
                matching: byLabel('Tentar enviar de novo'),
              )
              .evaluate()
              .isNotEmpty,
      ],
      [false, true, false, false],
    );
    expect(_linhas(tester)[1].label, 'Cena 2');

    harness.room.refuseTake = null;
    await harness.takes.flush();
    await notifier.refreshUnsent();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      byLabel('Tentar enviar de novo'),
      findsNothing,
      reason: 'entregue, a marca sai',
    );
    expect(_linhas(tester)[1].label, 'Cena 2');
  });

  testWidgets('tocar no bead que soa pausa; tocar em outro troca de parte', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _ensaioDeTresPartes(tester, harness: harness);
    final notifier = container.read(salaSessionProvider.notifier);
    final partes = container.read(salaSessionProvider).partes;

    notifier.ouvirACena(1);
    await tester.pump(const Duration(milliseconds: 200));
    expect(harness.playback.sounding, isTrue);
    expect(harness.playback.played, [partes[0].path]);
    expect(
      _linhas(tester)[0].label,
      'Cena 1, tocando',
      reason: 'soando, o bead diz que soa',
    );

    notifier.ouvirACena(1);
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      harness.playback.sounding,
      isFalse,
      reason: 'o mesmo bead pausa; não para',
    );
    expect(harness.playback.paused, isTrue);
    expect(
      container.read(salaSessionProvider).parteDoEnsaioTocando,
      0,
      reason: 'o anel continua na parte pausada',
    );
    expect(
      _linhas(tester)[0].label,
      'Cena 1',
      reason: 'pausado, o bead não diz mais que soa, mesmo com o anel aceso',
    );

    notifier.ouvirACena(3);
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      harness.playback.played,
      [partes[0].path, partes[2].path],
      reason: 'o terceiro bead toca a parte 3, não retoma a 1',
    );
    expect(harness.playback.sounding, isTrue);
    expect(
      [for (final linha in _linhas(tester)) linha.selected == true],
      [false, false, true, false],
    );
  });

  testWidgets(
    'o bead aberto de uma parte nova não acende sozinho enquanto o play '
    'está numa parte anterior, mesmo com uma gravação pendente',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await _ensaioDeTresPartes(tester, harness: harness);
      final notifier = container.read(salaSessionProvider.notifier);

      notifier.ensaioTap();
      await _ateEnsaio(tester, container, EnsaioStatus.recording);
      notifier.ensaioTap();
      await _ateEnsaio(tester, container, EnsaioStatus.recorded);

      notifier.playTheRehearsal();
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        [for (final linha in _linhas(tester)) linha.selected == true],
        [true, false, false, false],
        reason:
            'o play começa na parte 1; o quarto bead (a gravação pendente '
            'da parte nova) não fica com o anel só porque está aberto',
      );
    },
  );

  test('o anel segue a parte pendente que ficou no lugar da regravação, só '
      'quando o play chega nela', () async {
    final it = await _achadoNaParteDois();

    await _regravarAParteSemConfirmar(it);
    expect(
      it.estado.ensaio,
      EnsaioStatus.recorded,
      reason: 'gravada, mas ainda não confirmada com o V',
    );

    it.sala.playTheRehearsal();
    await waitFor(
      'o ensaio começar a tocar',
      () => it.harness.playback.sounding,
    );

    expect(
      it.estado.parteDoEnsaioTocando,
      0,
      reason: 'o play começa na parte 1, não na 2 pendente',
    );

    it.harness.playback.finishPlayback();
    await waitFor(
      'o play chegar na parte pendente',
      () => it.estado.parteDoEnsaioTocando == 1,
    );
    expect(
      it.harness.playback.played.last,
      it.harness.recorder.lastPath,
      reason: 'a parte 2 toca a gravação pendente, não a antiga',
    );

    it.harness.playback.finishPlayback();
    await waitFor(
      'o play chegar na parte 3',
      () => it.estado.parteDoEnsaioTocando == 2,
    );
    expect(
      it.harness.playback.played.last,
      it.partes[2].path,
      reason: 'a parte 3 segue tocando a sua própria gravação',
    );
  });

  testWidgets(
    'na tela, o anel não dobra numa regravação pendente: acende na parte 1 '
    'e só troca para a parte 2 quando o play chega nela',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await _achadoNaParteDoisNaTela(tester, harness);
      final notifier = container.read(salaSessionProvider.notifier);
      await _regravarAParteSemConfirmarNaTela(tester, notifier);

      notifier.playTheRehearsal();
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        [for (final linha in _linhas(tester)) linha.selected == true],
        [true, false, false, false],
        reason:
            'o play começa na parte 1; a tela não acende a parte 2 '
            'pendente ao mesmo tempo',
      );

      harness.playback.finishPlayback();
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        [for (final linha in _linhas(tester)) linha.selected == true],
        [false, true, false, false],
        reason: 'o play alcança a parte pendente; só ela fica com o anel',
      );

      notifier.playTheRehearsal();
      await tester.pump(const Duration(milliseconds: 200));
    },
  );

  testWidgets('gravar de novo depois de pausar um bead apaga o anel', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _ensaioDeTresPartes(tester, harness: harness);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.ouvirACena(2);
    await tester.pump(const Duration(milliseconds: 200));
    notifier.ouvirACena(2);
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      container.read(salaSessionProvider).parteDoEnsaioTocando,
      1,
      reason: 'pausado, o bead da parte 2 ainda guarda o anel',
    );

    notifier.ensaioTap();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      container.read(salaSessionProvider).parteDoEnsaioTocando,
      isNull,
      reason: 'gravar de novo interrompe e apaga o anel',
    );
    expect(
      [for (final linha in _linhas(tester)) linha.selected == true],
      [false, false, false, false],
      reason: 'nenhuma das três partes guarda o anel',
    );
    expect(
      naLinhaDoEnsaio(tester, 'Parar'),
      [null, null, null, true],
      reason: 'a gravação em curso é a da linha nova',
    );
  });
}
