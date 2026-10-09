import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/presentation/widgets/bead_row.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/ensaio_view.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'um_ensaio_de_tres_partes.dart';
import 'scenario_helpers.dart';

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

List<BeadRowEntry> _beads(WidgetTester tester) => tester
    .widget<BeadRow>(
      find.descendant(
        of: find.byType(EnsaioView),
        matching: find.byType(BeadRow),
      ),
    )
    .entries;

Future<void> _ateAParteTerNome(
  WidgetTester tester,
  ProviderContainer container,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  bool nomeada() {
    final partes = container.read(salaSessionProvider).partes;
    return partes.length == 1 && partes.first.takeId != null;
  }

  while (!nomeada()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException(
        'esperei 10s e a sala nomear a parte não aconteceu',
        const Duration(seconds: 10),
      );
    }
    await letTheRehearsalReachTheRoom(tester);
  }
}

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
  final harness = SalaHarness(filaEmMemoria: true)
    ..room.verdictChecked = false
    ..room.verdictHasFinding = true
    ..room.verdictFindingPlace = 0
    ..room.takeLandsAfter = const Duration(seconds: 1);
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
  await _ateAParteTerNome(tester, container);
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

/// A team standing on a finding addressed to part 2 of a three-part rehearsal, every part
/// already told back whole, with the record-again for part 2 open and nothing recorded yet.
Future<Sala> _achadoNaParteDois() async {
  final it = await umEnsaioDeTresPartesContadoInteiro();
  it.harness.room
    ..verdictChecked = false
    ..verdictHasFinding = true
    ..verdictFindingPlace = 1;
  await pedirOVeredito(it);
  it.sala.gravarAParteDeNovo();
  return it;
}

/// Starts a re-record of the part a finding named and stops it, leaving the take pending —
/// waiting for the green check, not yet in the part's place. The sibling of [regravarAParte],
/// which confirms it instead.
Future<void> _regravarAParteSemConfirmar(Sala it) async {
  it.sala.ensaioTap();
  await waitFor(
    'a gravação da parte de novo começar',
    () => it.estado.ensaio == EnsaioStatus.recording,
  );
  it.sala.ensaioTap();
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
  notifier.ensaioTap();
  await tester.pump(const Duration(milliseconds: 100));
  notifier.ensaioTap();
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
  await notifier.goConversa();
  await tester.pump(const Duration(milliseconds: 200));
  notifier.goEnsaio();
  await tester.pump(const Duration(milliseconds: 100));
  for (var parte = 0; parte < 3; parte++) {
    await gravarUmaParte(tester, notifier);
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
  notifier.gravarAParteDeNovo();
  await tester.pump(const Duration(milliseconds: 200));
  return container;
}

void main() {
  testWidgets(
    'a batida no segundo bead acende o anel, toca só a parte 2 e para no '
    'fim dela',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await _ensaioDeTresPartes(tester, harness: harness);
      final partes = container.read(salaSessionProvider).partes;

      await _tocar(tester, 'Parte 2');

      expect(
        [for (final bead in _beads(tester)) bead.current],
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
        [for (final bead in _beads(tester)) bead.current],
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
      [for (final bead in _beads(tester)) bead.current],
      [true, false, false],
    );

    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      [for (final bead in _beads(tester)) bead.current],
      [false, true, false],
      reason: 'o anel atravessa a fronteira para a parte 2',
    );

    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      [for (final bead in _beads(tester)) bead.current],
      [false, false, true],
    );

    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      [for (final bead in _beads(tester)) bead.current],
      [false, false, false],
      reason: 'o ensaio acabou; nenhum bead soa',
    );
  });

  testWidgets('o bead de uma parte ainda não entregue mostra isso, e some '
      'ao ser entregue', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    harness.room.refuseTake = 'ensaio/${KeptScope.parte(2)}';
    final container = await _ensaioDeTresPartes(tester, harness: harness);
    final notifier = container.read(salaSessionProvider.notifier);
    await harness.takes.flush();
    await notifier.refreshUnsent();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      [for (final bead in _beads(tester)) bead.delivered],
      [true, false, true],
    );
    expect(
      _beads(tester)[1].semanticLabel,
      'Parte 2, ainda não enviada',
      reason: 'a única coisa que uma sala sem texto tem para dizer isso',
    );

    notifier.tocarAParte(1);
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      _beads(tester)[1].semanticLabel,
      'Parte 2, tocando, ainda não enviada',
      reason: 'soando e ainda não entregue, o bead diz as duas coisas',
    );
    notifier.tocarAParte(1);
    await tester.pump(const Duration(milliseconds: 200));

    harness.room.refuseTake = null;
    await harness.takes.flush();
    await notifier.refreshUnsent();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      [for (final bead in _beads(tester)) bead.delivered],
      [true, true, true],
      reason: 'entregue, a marca sai',
    );
    expect(_beads(tester)[1].semanticLabel, 'Parte 2');
  });

  testWidgets('tocar no bead que soa pausa; tocar em outro troca de parte', (
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
    expect(
      _beads(tester)[0].semanticLabel,
      'Parte 1, tocando',
      reason: 'soando, o bead diz que soa',
    );

    notifier.tocarAParte(0);
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
      _beads(tester)[0].semanticLabel,
      'Parte 1',
      reason: 'pausado, o bead não diz mais que soa, mesmo com o anel aceso',
    );

    notifier.tocarAParte(2);
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      harness.playback.played,
      [partes[0].path, partes[2].path],
      reason: 'o terceiro bead toca a parte 3, não retoma a 1',
    );
    expect(harness.playback.sounding, isTrue);
    expect(
      [for (final bead in _beads(tester)) bead.current],
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
        [for (final bead in _beads(tester)) bead.current],
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

    expect(
      it.estado.parteARegravar,
      1,
      reason: 'o achado aponta a parte 2 (índice 1)',
    );

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
        [for (final bead in _beads(tester)) bead.current],
        [true, false, false],
        reason:
            'o play começa na parte 1; a tela não acende a parte 2 '
            'pendente ao mesmo tempo',
      );

      harness.playback.finishPlayback();
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        [for (final bead in _beads(tester)) bead.current],
        [false, true, false],
        reason: 'o play alcança a parte pendente; só ela fica com o anel',
      );

      notifier.playTheRehearsal();
      await tester.pump(const Duration(milliseconds: 200));
    },
  );

  testWidgets(
    'o esmaecido é uma regra só: escurece e bloqueia antes da gravação, '
    'some das duas coisas quando o take fica pendente',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await _achadoNaParteDoisNaTela(tester, harness);
      final notifier = container.read(salaSessionProvider.notifier);

      expect(
        _beads(tester)[0].dimmed,
        isTrue,
        reason: 'nada gravado ainda; a parte 1 não é a que a equipe regrava',
      );
      notifier.tocarAParte(0);
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        harness.playback.sounding,
        isFalse,
        reason: 'esmaecida na tela, a batida também não toca',
      );

      await _regravarAParteSemConfirmarNaTela(tester, notifier);
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        _beads(tester)[0].dimmed,
        isFalse,
        reason: 'pendente a confirmação, a mesma conta não fica esmaecida',
      );
      notifier.tocarAParte(0);
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        harness.playback.sounding,
        isTrue,
        reason: 'e a mesma batida agora toca',
      );

      harness.playback.finishPlayback();
      await tester.pump(const Duration(milliseconds: 200));
    },
  );

  test('um bead esmaecido não toca enquanto a regravação de um achado está '
      'aberta e nada foi gravado ainda', () async {
    final it = await _achadoNaParteDois();
    final antes = it.harness.playback.played.length;

    it.sala.tocarAParte(0);

    expect(
      it.harness.playback.played,
      hasLength(antes),
      reason: 'o bead da parte 1 está esmaecido; a batida não faz nada',
    );
    expect(it.estado.parteDoEnsaioTocando, isNull);
  });

  test('com uma gravação pendente, os beads tocam como de costume, mesmo os '
      'esmaecidos', () async {
    final it = await _achadoNaParteDois();
    await _regravarAParteSemConfirmar(it);

    it.sala.tocarAParte(0);
    await waitFor('a parte 1 tocar', () => it.harness.playback.sounding);

    expect(it.harness.playback.played.last, it.partes[0].path);
    expect(
      it.estado.parteDoEnsaioTocando,
      0,
      reason:
          'pendente a confirmação, a equipe pode ouvir qualquer parte, '
          'inclusive a esmaecida',
    );
  });

  testWidgets('gravar de novo depois de pausar um bead apaga o anel', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _ensaioDeTresPartes(tester, harness: harness);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.tocarAParte(1);
    await tester.pump(const Duration(milliseconds: 200));
    notifier.tocarAParte(1);
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
      [for (final bead in _beads(tester)) bead.current],
      [false, false, false, true],
      reason:
          'nenhuma das três partes guarda o anel; o quarto bead, aberto '
          'para a gravação em curso, é o que fica com ele por padrão',
    );
  });
}
