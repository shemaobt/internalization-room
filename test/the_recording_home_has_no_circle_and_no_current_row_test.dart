import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/scene_question.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/bead_styles.dart';
import 'package:internalization_room/features/sala/presentation/widgets/ensaio_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart';

const _cenas = [
  Scene(sceneId: 'S1', title: 'A fome em Belém'),
  Scene(sceneId: 'S2', title: 'Noemi decide voltar'),
  Scene(sceneId: 'S3', title: 'Rute fica com Noemi'),
];

const _gravar = 'Gravar';
const _parar = 'Parar';
const _gravarDeNovo = 'Gravar de novo';
const _ouvir = 'Ouvir';
const _tocando = 'tocando';
const _enviarAGravacao = 'Enviar a gravação';
const _irParaATraducao = 'Traduzir a gravação';

void _umIpadEmPe(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(820, 1180)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

SalaHarness _umaSala() =>
    SalaHarness(filaEmMemoria: true, takesHome: aTempHome('sala-1872'))
      ..room.passageScenes = _cenas;

Future<ProviderContainer> _naCasaDoEnsaio(
  WidgetTester tester,
  SalaHarness harness,
) async {
  _umIpadEmPe(tester);
  final container = await pumpSala(tester, harness);
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.goConversa(book: 'Ruth', pericope: 'P01');
  await tester.pump(const Duration(milliseconds: 200));
  notifier.goEnsaio();
  await tester.pump(const Duration(milliseconds: 400));
  return container;
}

SalaSessionState _estado(ProviderContainer container) =>
    container.read(salaSessionProvider);

Finder _linha(int n) => find.descendant(
  of: find.byType(EnsaioView),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is Semantics &&
        (widget.properties.label ?? '').startsWith(
          'Cena $n — ${_cenas[n - 1].title}',
        ),
  ),
);

Finder _naLinha(int n, String controle) =>
    find.descendant(of: _linha(n), matching: byLabel(controle));

Finder get _circuloNaCasa => find.descendant(
  of: find.byType(EnsaioView),
  matching: find.byType(FacilitatorCircle),
);

Finder get _linhaSelecionada => find.descendant(
  of: find.byType(EnsaioView),
  matching: find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.selected == true,
  ),
);

Finder get _umaCena => find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      (widget.properties.label ?? '').startsWith('Cena '),
);

bool _discoAceso(WidgetTester tester) =>
    tester.widget<Semantics>(inTheHome(_irParaATraducao)).properties.enabled ==
    true;

ButtonMood _humor(WidgetTester tester, Finder controle) => tester
    .widget<RoundActionButton>(
      find.ancestor(of: controle, matching: find.byType(RoundActionButton)),
    )
    .mood;

Future<void> _tocar(WidgetTester tester, Finder alvo) async {
  await tester.ensureVisible(alvo);
  await tester.tap(alvo, warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _guardar(
  WidgetTester tester,
  ProviderContainer container, {
  required int partes,
}) async {
  await _tocar(tester, offTheRows(_enviarAGravacao));
  await letTheRehearsalReachTheRoom(tester);
  await theRoomNamesTheParts(tester, container, parts: partes);
}

Future<void> _gravarNaLinha(
  WidgetTester tester,
  ProviderContainer container,
  int n, {
  required int partes,
  bool deNovo = false,
}) async {
  await _tocar(tester, _naLinha(n, deNovo ? _gravarDeNovo : _gravar));
  await _tocar(tester, _naLinha(n, _parar));
  await _guardar(tester, container, partes: partes);
}

KeptTake _aParte(ProviderContainer container, int n) => _estado(
  container,
).partes.singleWhere((take) => take.scopeId == KeptScope.parte(n));

List<String> _escopos(ProviderContainer container) => [
  for (final take in _estado(container).partes) take.scopeId,
];

/// The three scenes recorded through their rows and told back whole, the room's verdict
/// naming part 2, and the team taken back to record it again.
Future<ProviderContainer> _devoltaPeloAchadoNaParteDois(
  WidgetTester tester,
  SalaHarness harness,
) async {
  harness.room
    ..verdictChecked = false
    ..verdictHasFinding = true
    ..verdictFindingPlace = 1;
  harness.playback.length = umaParteInteira;
  final container = await _naCasaDoEnsaio(tester, harness);
  for (var n = 1; n <= 3; n++) {
    await _gravarNaLinha(tester, container, n, partes: n);
  }
  final notifier = container.read(salaSessionProvider.notifier);
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
  await tester.pump(const Duration(milliseconds: 400));
  expect(
    _estado(container).stage,
    SalaStage.ensaio,
    reason: 'o caso só mede alguma coisa se a equipe voltar à casa',
  );
  return container;
}

void main() {
  testWidgets('the recording home draws no circle', (tester) async {
    await _naCasaDoEnsaio(tester, _umaSala());

    expect(find.byType(EnsaioView), findsOneWidget);
    expect(_circuloNaCasa, findsNothing);
    expect(
      find.descendant(
        of: find.byType(EnsaioView),
        matching: offTheRows(_gravar),
      ),
      findsNothing,
      reason: 'só as linhas gravam',
    );
  });

  testWidgets(
    'a Scene row\'s own controls record, stop and record again that scene',
    (tester) async {
      final container = await _naCasaDoEnsaio(tester, _umaSala());

      await _tocar(tester, _naLinha(2, _gravar));
      expect(_estado(container).ensaio, EnsaioStatus.recording);
      expect(_naLinha(2, _parar), findsOneWidget);

      await _tocar(tester, _naLinha(2, _parar));
      await _guardar(tester, container, partes: 1);
      expect(_escopos(container), [KeptScope.parte(2)]);
      expect(_naLinha(2, _gravarDeNovo), findsOneWidget);
      final primeira = _aParte(container, 2);

      await _gravarNaLinha(tester, container, 2, partes: 1, deNovo: true);

      final segunda = _aParte(container, 2);
      expect(_escopos(container), [KeptScope.parte(2)]);
      expect(segunda.path, isNot(primeira.path));
      expect(segunda.pass, primeira.pass + 1);
    },
  );

  testWidgets(
    'a tap on scene 3\'s row records scene 3 while scenes 1 and 2 have no part',
    (tester) async {
      final container = await _naCasaDoEnsaio(tester, _umaSala());

      await _gravarNaLinha(tester, container, 3, partes: 1);

      expect(_escopos(container), [KeptScope.parte(3)]);
      expect(_naLinha(1, _gravar), findsOneWidget);
      expect(_naLinha(2, _gravar), findsOneWidget);
    },
  );

  testWidgets('while one row records, another row\'s record does nothing', (
    tester,
  ) async {
    final harness = _umaSala();
    final container = await _naCasaDoEnsaio(tester, harness);
    final antes = harness.recorder.captures;

    await _tocar(tester, _naLinha(1, _gravar));
    await _tocar(tester, _naLinha(3, _gravar));

    expect(_estado(container).ensaio, EnsaioStatus.recording);
    expect(_naLinha(1, _parar), findsOneWidget);
    expect(_naLinha(3, _parar), findsNothing);
    expect(harness.recorder.captures, antes + 1);
  });

  testWidgets('no Scene row is drawn selected while a part plays', (
    tester,
  ) async {
    final harness = _umaSala();
    final container = await _naCasaDoEnsaio(tester, harness);
    for (var n = 1; n <= 3; n++) {
      await _gravarNaLinha(tester, container, n, partes: n);
    }

    await _tocar(tester, offTheRows(_ouvir));
    for (var n = 1; n <= 3; n++) {
      expect(
        _linhaSelecionada,
        findsNothing,
        reason: 'a parte $n soa, e nenhuma linha se acende',
      );
      expect(byLabel('Cena $n — ${_cenas[n - 1].title}, $_tocando'), findsOne);
      expect(
        find.descendant(
          of: _linha(n),
          matching: find.byIcon(LucideIcons.pause),
        ),
        findsOneWidget,
      );
      harness.playback.finishPlayback();
      await tester.pump(const Duration(milliseconds: 200));
    }

    await _tocar(tester, _naLinha(2, _ouvir));
    expect(_linhaSelecionada, findsNothing);
    expect(byLabel('Cena 2 — ${_cenas[1].title}, $_tocando'), findsOne);
    expect(
      find.descendant(of: _linha(2), matching: find.byIcon(LucideIcons.pause)),
      findsOneWidget,
    );
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets(
    '«voltar e regravar uma parte» lands on a recording home with no row '
    'selected and every row live',
    (tester) async {
      final container = await _devoltaPeloAchadoNaParteDois(tester, _umaSala());
      final antes = _estado(container).partes;

      expect(_linhaSelecionada, findsNothing);
      expect(
        _discoAceso(tester),
        isTrue,
        reason: 'com toda cena gravada, o disco não espera a parte do achado',
      );
      for (var n = 1; n <= 3; n++) {
        expect(
          _humor(tester, _naLinha(n, _gravarDeNovo)),
          ButtonMood.lit,
          reason: 'a linha $n fica viva, como na dela',
        );
      }

      await _gravarNaLinha(tester, container, 2, partes: 3, deNovo: true);

      final agora = _estado(container).partes;
      expect(_escopos(container), [
        KeptScope.parte(1),
        KeptScope.parte(2),
        KeptScope.parte(3),
      ]);
      expect(agora[1].path, isNot(antes[1].path));
      expect(agora[1].pass, antes[1].pass + 1);
      expect([agora[0].path, agora[2].path], [antes[0].path, antes[2].path]);
    },
  );

  testWidgets('a warning on the recording home draws no warning mark', (
    tester,
  ) async {
    _umIpadEmPe(tester);
    final casa = aTempHome('sala-1872-aviso');
    final gravada = File('${casa.path}/p1.m4a')..writeAsBytesSync([1, 2, 3]);
    final harness = _umaSala()
      ..room.serverStatus = 'needs_person'
      ..room.serverHalt = HaltKind.warning;
    harness.emAberto.rows['Ruth/P01/pt'] = ResumePoint(
      sessionId: 'sessao-antiga',
      stage: SalaStage.ensaio,
      takes: [
        KeptTake(
          scopeId: KeptScope.parte(1),
          path: gravada.path,
          takeId: 'gravacao-1',
        ),
      ],
    );
    final container = harness.container();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SalaApp()),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final notifier = container.read(salaSessionProvider.notifier);
    await tester.runAsync(notifier.abrirEscolha);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.runAsync(
      () => notifier.goConversa(book: 'Ruth', pericope: 'P01'),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(
      (_estado(container).stage, _estado(container).warning),
      (SalaStage.ensaio, true),
      reason: 'o caso só mede alguma coisa com o aviso de pé na casa',
    );

    expect(_circuloNaCasa, findsNothing);
    expect(_humor(tester, _naLinha(2, _gravar)), ButtonMood.lit);
    expect(_humor(tester, _naLinha(3, _gravar)), ButtonMood.lit);
    closeTheRoom(container);
  });

  testWidgets('a Scene row does not record while the external check is '
      'opening', (tester) async {
    final harness = _umaSala();
    final container = await _naCasaDoEnsaio(tester, harness);
    await _gravarNaLinha(tester, container, 1, partes: 1);
    harness.room
      ..retroSoFar = const BackTranslationProgress(checked: true)
      ..approvedDraft = const ApprovedDraft(version: 1);
    final notifier = container.read(salaSessionProvider.notifier);
    notifier.goEnsaio();
    await tester.pump(const Duration(seconds: 2));
    harness.room.holdNextExternalCheck();
    notifier.abrirAChecagemExterna();
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      harness.room.externalChecksOpened,
      isNotEmpty,
      reason: 'o caso só mede alguma coisa com a checagem a caminho',
    );

    final antes = harness.recorder.captures;
    await _tocar(tester, _naLinha(2, _gravar));

    expect(_estado(container).ensaio, EnsaioStatus.idle);
    harness.room.finishHeldExternalCheck();
    await tester.pump(const Duration(milliseconds: 300));
    expect(_estado(container).ensaio, EnsaioStatus.idle);
    expect(harness.recorder.captures, antes);
    closeTheRoom(container);
  });

  testWidgets(
    'a recording home whose scene list never answered offers nothing to record',
    (tester) async {
      final harness = _umaSala()
        ..room.failScenesWith = const NetworkFailed('sem rede');
      await _naCasaDoEnsaio(tester, harness);
      await tester.pump(const Duration(seconds: 12));
      final antes = harness.recorder.captures;
      final gravar = find.descendant(
        of: find.byType(EnsaioView),
        matching: byLabel(_gravar),
      );
      for (final alvo in gravar.evaluate().toList()) {
        await tester.tap(find.byWidget(alvo.widget), warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 200));
      }

      expect(find.byType(EnsaioView), findsOneWidget);
      expect(onTheRows(_gravar), findsNothing);
      expect(onTheRows(_gravarDeNovo), findsNothing);
      expect(
        find.descendant(of: find.byType(EnsaioView), matching: _umaCena),
        findsNothing,
      );
      expect(harness.recorder.captures, antes);
    },
  );

  testWidgets('a session reopened after «voltar e regravar uma parte» opens '
      'its recording home with no row marked', (tester) async {
    final harness = _umaSala();
    final container = await _devoltaPeloAchadoNaParteDois(tester, harness);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox.shrink());
    closeTheRoom(container);

    final reaberta = harness.container();
    addTearDown(reaberta.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: reaberta, child: const SalaApp()),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final notifier = reaberta.read(salaSessionProvider.notifier);
    await tester.runAsync(notifier.abrirEscolha);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.runAsync(
      () => notifier.goConversa(book: 'Ruth', pericope: 'P01'),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    for (var i = 0; i < 20 && _estado(reaberta).partes.length < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      (_estado(reaberta).stage, _estado(reaberta).partes.length),
      (SalaStage.ensaio, 3),
      reason: 'o caso precisa reabrir dentro do Ensaio com as três partes',
    );

    expect(_linhaSelecionada, findsNothing);
    for (var n = 1; n <= 3; n++) {
      expect(_humor(tester, _naLinha(n, _gravarDeNovo)), ButtonMood.lit);
    }
    expect(_discoAceso(tester), isTrue);
  });
}
