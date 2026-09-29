import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/bead_row.dart';
import 'package:internalization_room/features/sala/presentation/widgets/ensaio_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'session_notifier_test.dart' show inConversa;
import 'scenario_helpers.dart';

const _gravarOEnsaio = 'Tocar para gravar o ensaio';
const _gravarAProxima = 'Tocar para gravar a próxima parte';
const _terminar = 'Tocar ao terminar';
const _gravarDeNovo = 'Tocar para gravar esta parte de novo';
const _ouvirOEnsaio = 'Ouvir o ensaio até aqui';
const _pausarOEnsaio = 'Pausar o ensaio';
const _confirmar = 'Confirmar esta parte';
const _irParaATraducao = 'Ir para a tradução';

Future<ProviderContainer> _noEnsaio(
  WidgetTester tester, {
  String lingua = testLanguage,
  SalaHarness? harness,
}) async {
  final container = await pumpSala(
    tester,
    harness ?? SalaHarness(filaEmMemoria: true, lingua: lingua),
  );
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.goConversa();
  await tester.pump(const Duration(milliseconds: 200));
  notifier.goEnsaio();
  await tester.pump(const Duration(milliseconds: 400));
  return container;
}

Future<void> _tocar(WidgetTester tester, String label) async {
  await tester.tap(byLabel(label));
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _gravarEDeixarPendente(WidgetTester tester, String circulo) async {
  await _tocar(tester, circulo);
  await _tocar(tester, _terminar);
}

Future<void> _confirmarAParte(WidgetTester tester) async {
  await _tocar(tester, _confirmar);
  await letTheRehearsalReachTheRoom(tester);
}

List<BeadRowEntry> _contas(WidgetTester tester) =>
    tester.widget<BeadRow>(find.byType(BeadRow)).entries;

FacilitatorCircle _circulo(WidgetTester tester) =>
    tester.widget<FacilitatorCircle>(
      find.descendant(
        of: find.byType(EnsaioView),
        matching: find.byType(FacilitatorCircle),
      ),
    );

(bool, double) _estadoDoBotao(WidgetTester tester, String label) => (
  tester.widget<Semantics>(byLabel(label)).properties.enabled == true,
  tester
      .widget<AnimatedOpacity>(
        find
            .descendant(
              of: byLabel(label),
              matching: find.byType(AnimatedOpacity),
            )
            .first,
      )
      .opacity,
);

bool _aceso(WidgetTester tester, String label) =>
    _estadoDoBotao(tester, label) == (true, 1.0);

bool _apagado(WidgetTester tester, String label) =>
    _estadoDoBotao(tester, label) == (false, 0.35);

List<PendingTakeView> _naFila(SalaHarness harness) => [
  for (final linha in (harness.takes as FakeTakeQueue).rows)
    (path: linha.path, scope: linha.scope, chunkIndex: linha.chunkIndex),
];

typedef PendingTakeView = ({String path, String scope, int? chunkIndex});

SalaSessionNotifier _sala(ProviderContainer container) =>
    container.read(salaSessionProvider.notifier);

void main() {
  testWidgets(
    'a segunda batida deixa a parte pendente, o círculo grava por cima e o '
    'check confirma',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await _noEnsaio(tester, harness: harness);

      expect(_contas(tester), isEmpty);
      await _tocar(tester, _gravarOEnsaio);
      expect(
        [for (final conta in _contas(tester)) (conta.fill, conta.current)],
        [(BeadFill.translucent, true)],
        reason: 'a gravação aberta já é uma conta, translúcida e em evidência',
      );
      expect(_circulo(tester).voice, VoiceState.listening);
      expect(_circulo(tester).tongue, Tongue.motherTongue);

      await _tocar(tester, _terminar);
      final primeira = harness.recorder.lastPath!;
      expect(
        [for (final conta in _contas(tester)) conta.fill],
        [BeadFill.translucent],
        reason: 'a parte pendente ainda não foi confirmada',
      );
      expect(_aceso(tester, _ouvirOEnsaio), isTrue);
      expect(_aceso(tester, _confirmar), isTrue);
      expect(
        _apagado(tester, _irParaATraducao),
        isTrue,
        reason: 'com uma parte pendente o disco não leva à tradução',
      );

      await _gravarEDeixarPendente(tester, _gravarDeNovo);
      final segunda = harness.recorder.lastPath!;
      await _gravarEDeixarPendente(tester, _gravarDeNovo);
      final terceira = harness.recorder.lastPath!;

      expect(
        _contas(tester),
        hasLength(1),
        reason: 'gravar por cima é a mesma parte, não uma segunda',
      );
      expect(harness.recorder.captures, 3);
      expect(
        harness.recorder.deleted,
        containsAll([primeira, segunda]),
        reason: 'o arquivo que a gravação nova substitui sai do tablet',
      );
      expect(harness.recorder.deleted, isNot(contains(terceira)));
      await letTheRehearsalReachTheRoom(tester);
      expect(_naFila(harness), isEmpty, reason: 'nada sobe antes do check');

      await _confirmarAParte(tester);

      expect(
        [for (final conta in _contas(tester)) (conta.fill, conta.current)],
        [(BeadFill.solid, false)],
      );
      expect(_naFila(harness), [
        (path: terceira, scope: KeptScope.parte(1), chunkIndex: 1),
      ], reason: 'só a última gravação sobe, como a parte 1');
      expect(_apagado(tester, _confirmar), isTrue);
      expect(_aceso(tester, _irParaATraducao), isTrue);
      expect(byLabel(_gravarAProxima), findsOneWidget);
      expect(_circulo(tester).voice, VoiceState.invite);
      expect(container.read(salaSessionProvider).stage, SalaStage.ensaio);
    },
  );

  testWidgets(
    'o disco espera a parte pendente ser confirmada para levar à tradução',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await _noEnsaio(tester, harness: harness);
      await _gravarEDeixarPendente(tester, _gravarOEnsaio);
      await _confirmarAParte(tester);

      await _tocar(tester, _gravarAProxima);
      expect(
        _apagado(tester, _ouvirOEnsaio),
        isTrue,
        reason: 'com a parte 1 confirmada, nada toca enquanto a 2 grava',
      );
      await _tocar(tester, _terminar);
      expect(
        [for (final conta in _contas(tester)) (conta.fill, conta.current)],
        [(BeadFill.solid, false), (BeadFill.translucent, true)],
      );
      expect(_apagado(tester, _irParaATraducao), isTrue);

      await tester.tap(byLabel(_irParaATraducao), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 200));
      _sala(container).startRetro();
      await tester.pump(const Duration(milliseconds: 200));
      await letTheRehearsalReachTheRoom(tester);

      expect(
        container.read(salaSessionProvider).stage,
        SalaStage.ensaio,
        reason: 'com a parte 2 pendente o disco não leva a lado nenhum',
      );
      expect(
        _naFila(harness),
        hasLength(1),
        reason: 'e não guarda a parte pendente por conta própria',
      );
      expect(container.read(salaSessionProvider).partes, hasLength(1));
      expect(_aceso(tester, _confirmar), isTrue);

      await _confirmarAParte(tester);
      expect(_naFila(harness), hasLength(2));
      await _tocar(tester, _irParaATraducao);
      expect(container.read(salaSessionProvider).stage, SalaStage.retro);
      closeTheRoom(container);
    },
  );

  testWidgets('o play toca o ensaio até aqui, pausa e retoma', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _noEnsaio(tester, harness: harness);
    await _gravarEDeixarPendente(tester, _gravarOEnsaio);
    await _confirmarAParte(tester);
    await _gravarEDeixarPendente(tester, _gravarAProxima);
    await _confirmarAParte(tester);
    final partes = [
      for (final parte in container.read(salaSessionProvider).partes)
        parte.path,
    ];
    expect(partes, hasLength(2));

    await _tocar(tester, _ouvirOEnsaio);
    expect(harness.playback.played, [partes[0]]);
    expect(_circulo(tester).voice, VoiceState.speaking);
    expect(_circulo(tester).tongue, Tongue.motherTongue);
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 200));
    expect(harness.playback.played, partes, reason: 'a parte 1, depois a 2');

    await _tocar(tester, _pausarOEnsaio);
    expect(harness.playback.paused, isTrue);
    expect(harness.playback.sounding, isFalse);
    expect(
      harness.sounds.last,
      'playback:pause',
      reason: 'o segundo toque pausa; não para',
    );

    await _tocar(tester, _ouvirOEnsaio);
    expect(harness.playback.paused, isFalse);
    expect(harness.playback.sounding, isTrue);
    expect(
      harness.playback.played,
      partes,
      reason:
          'retomar é continuar a parte 2 de onde parou, não tocar outra vez',
    );
  });

  testWidgets('a parte que acaba durante a pausa espera o play para seguir', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _noEnsaio(tester, harness: harness);
    await _gravarEDeixarPendente(tester, _gravarOEnsaio);
    await _confirmarAParte(tester);
    await _gravarEDeixarPendente(tester, _gravarAProxima);
    await _confirmarAParte(tester);
    final partes = [
      for (final parte in container.read(salaSessionProvider).partes)
        parte.path,
    ];

    await _tocar(tester, _ouvirOEnsaio);
    await _tocar(tester, _pausarOEnsaio);
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      harness.playback.played,
      [partes[0]],
      reason: 'pausado, o ensaio não segue sozinho para a parte 2',
    );
    expect(byLabel(_ouvirOEnsaio), findsOneWidget);

    await _tocar(tester, _ouvirOEnsaio);

    expect(harness.playback.played, partes, reason: 'o play segue para a 2');
    expect(harness.playback.sounding, isTrue);
  });

  testWidgets('o play toca a parte pendente depois das confirmadas', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _noEnsaio(tester, harness: harness);
    await _gravarEDeixarPendente(tester, _gravarOEnsaio);
    await _confirmarAParte(tester);
    await _gravarEDeixarPendente(tester, _gravarAProxima);
    final pendente = harness.recorder.lastPath!;
    final confirmada = container.read(salaSessionProvider).partes.single.path;

    await _tocar(tester, _ouvirOEnsaio);
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 200));

    expect(harness.playback.played, [confirmada, pendente]);
  });

  testWidgets('só a parte pendente já se ouve no play', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    await _noEnsaio(tester, harness: harness);
    expect(_apagado(tester, _ouvirOEnsaio), isTrue);
    await _gravarEDeixarPendente(tester, _gravarOEnsaio);

    await _tocar(tester, _ouvirOEnsaio);

    expect(harness.playback.played, [harness.recorder.lastPath]);
  });

  test(
    'a gravação por cima que não volta deixa a parte pendente de antes',
    () async {
      final harness = SalaHarness();
      final container = await inConversa(harness);
      addTearDown(container.dispose);
      final sala = _sala(container);
      EnsaioStatus ensaio() => container.read(salaSessionProvider).ensaio;
      sala.goEnsaio();
      sala.ensaioTap();
      await waitFor('gravar', () => ensaio() == EnsaioStatus.recording);
      sala.ensaioTap();
      await waitFor(
        'a parte ficar pendente',
        () => ensaio() == EnsaioStatus.recorded,
      );
      final pendente = harness.recorder.lastPath!;

      harness.recorder.returnsNothing = true;
      sala.ensaioTap();
      await waitFor(
        'gravar por cima',
        () => ensaio() == EnsaioStatus.recording,
      );
      sala.ensaioTap();
      await waitFor(
        'a sala chamar uma pessoa',
        () => container.read(salaSessionProvider).needsPerson,
      );

      expect(
        ensaio(),
        EnsaioStatus.recorded,
        reason: 'a captura falhou; a parte que já estava pendente continua',
      );
      expect(harness.recorder.deleted, isNot(contains(pendente)));
      harness.recorder.returnsNothing = false;
      sala.resolveWithPerson();
      sala.playTheRehearsal();
      await waitFor('tocar', () => harness.playback.played.isNotEmpty);
      expect(harness.playback.played, [pendente]);
    },
  );

  testWidgets(
    'o microfone que não abre por cima deixa a parte pendente de antes',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await _noEnsaio(tester, harness: harness);
      await _gravarEDeixarPendente(tester, _gravarOEnsaio);
      await _confirmarAParte(tester);
      await _gravarEDeixarPendente(tester, _gravarAProxima);

      harness.recorder.startThrows = true;
      await _tocar(tester, _gravarDeNovo);

      expect(container.read(salaSessionProvider).ensaio, EnsaioStatus.recorded);
      expect(_aceso(tester, _confirmar), isTrue);
      expect(_apagado(tester, _irParaATraducao), isTrue);
    },
  );

  test(
    'o microfone recusado por cima deixa a parte pendente de antes',
    () async {
      final harness = SalaHarness();
      final container = await inConversa(harness);
      addTearDown(container.dispose);
      final sala = _sala(container);
      EnsaioStatus ensaio() => container.read(salaSessionProvider).ensaio;
      sala.goEnsaio();
      sala.ensaioTap();
      await waitFor('gravar', () => ensaio() == EnsaioStatus.recording);
      sala.ensaioTap();
      await waitFor(
        'a parte ficar pendente',
        () => ensaio() == EnsaioStatus.recorded,
      );
      final pendente = harness.recorder.lastPath!;

      harness.recorder.permitted = false;
      sala.ensaioTap();
      await waitFor('a recusa voltar', () => harness.recorder.captures == 2);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(ensaio(), EnsaioStatus.recorded);
      harness.recorder.permitted = true;
      sala.takeKeep();
      await waitFor(
        'a parte pendente de antes ser confirmada',
        () => container.read(salaSessionProvider).partes.isNotEmpty,
      );
      expect(container.read(salaSessionProvider).partes.single.path, pendente);
    },
  );

  testWidgets('o círculo não grava sobre o ensaio que soa', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    await _noEnsaio(tester, harness: harness);
    await _gravarEDeixarPendente(tester, _gravarOEnsaio);
    await _tocar(tester, _ouvirOEnsaio);
    final capturas = harness.recorder.captures;

    await _tocar(tester, _gravarDeNovo);

    expect(harness.recorder.captures, capturas);
    expect(harness.playback.sounding, isTrue);
  });

  testWidgets('o check cala o ensaio que está tocando', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    await _noEnsaio(tester, harness: harness);
    await _gravarEDeixarPendente(tester, _gravarOEnsaio);
    await _tocar(tester, _ouvirOEnsaio);
    expect(harness.playback.sounding, isTrue);

    await _confirmarAParte(tester);

    expect(harness.playback.sounding, isFalse);
    expect(byLabel(_ouvirOEnsaio), findsOneWidget);
  });

  testWidgets('nada aposentado é desenhado no ensaio', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    await _noEnsaio(tester, harness: harness);

    void nadaAposentado(String quando) {
      expect(
        find.descendant(
          of: find.byType(EnsaioView),
          matching: find.byIcon(LucideIcons.mic),
        ),
        findsNothing,
        reason: '$quando: nenhum microfone no ensaio',
      );
      for (final aposentado in [
        'Ouvir a gravação',
        'Gravar de novo',
        'Guardar esta gravação',
        'Ouvir o ensaio guardado antes de gravar',
        'Parar de ouvir o ensaio guardado',
      ]) {
        expect(
          byLabel(aposentado),
          findsNothing,
          reason: '$quando: $aposentado',
        );
      }
      final tocar = byLabel(_ouvirOEnsaio).evaluate().isNotEmpty
          ? _ouvirOEnsaio
          : _pausarOEnsaio;
      expect(byLabel(tocar), findsOneWidget, reason: quando);
      expect(byLabel(_confirmar), findsOneWidget, reason: quando);
      expect(byLabel(_irParaATraducao), findsOneWidget, reason: quando);
    }

    nadaAposentado('vazio');
    await _tocar(tester, _gravarOEnsaio);
    nadaAposentado('gravando');
    await _tocar(tester, _terminar);
    nadaAposentado('pendente');
    await _confirmarAParte(tester);
    nadaAposentado('confirmada');
    await _tocar(tester, _ouvirOEnsaio);
    nadaAposentado('tocando');
  });

  testWidgets('os rótulos falam a língua da sala', (tester) async {
    await _noEnsaio(tester, lingua: 'en');

    expect(byLabel('Tap to record the rehearsal'), findsOneWidget);
    expect(byLabel('Hear the rehearsal so far'), findsOneWidget);
    expect(byLabel('Confirm this part'), findsOneWidget);
    expect(byLabel('Go to the translation'), findsOneWidget);

    await _tocar(tester, 'Tap to record the rehearsal');
    expect(byLabel('Tap when you finish'), findsOneWidget);
    expect(byLabel('Part 1'), findsOneWidget);
    await _tocar(tester, 'Tap when you finish');
    expect(byLabel('Tap to record this part again'), findsOneWidget);

    await _tocar(tester, 'Hear the rehearsal so far');
    expect(byLabel('Pause the rehearsal'), findsOneWidget);
    await _tocar(tester, 'Pause the rehearsal');

    await _tocar(tester, 'Confirm this part');
    await letTheRehearsalReachTheRoom(tester);
    expect(byLabel('Tap to record the next part'), findsOneWidget);
    expect(byLabel('Part 1'), findsOneWidget);
  });
}
