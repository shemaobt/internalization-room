import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/scene_question.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart';
import 'the_kept_retellings_are_numbered_buttons_on_the_conversation_test.dart'
    show aKept;

const _cenas = [
  Scene(sceneId: 'S1', title: 'A fome em Belém'),
  Scene(sceneId: 'S2', title: 'Noemi decide voltar'),
  Scene(sceneId: 'S3', title: 'Rute fica com Noemi'),
  Scene(sceneId: 'S4', title: 'A chegada a Belém'),
];

const _comoContaram = 'Ouvir como vocês contaram esta parte';
const _aPassagemInteira = 'ouvir como vocês contaram a passagem inteira';
const _gravar = 'Gravar';
const _ouvir = 'Ouvir';
const _gravarDeNovo = 'Gravar de novo';
const _parar = 'Parar';
const _tocando = 'tocando';
const _falhou = 'falhou — toque para tentar de novo';
const _enviarAGravacao = 'Enviar a gravação';
const _gravarAPassagemInteira = 'Gravar a passagem inteira';
const _passagemInteira = 'A passagem inteira';

final _s1 = aKept('S1', 4);
final _s2 = aKept('S2', 6);
final _s3 = aKept('S3', 8);
final _inteira = aKept('whole', 10);

void _umIpadEmPe(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(820, 1180)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

List<int> _bytesOf(KeptRetelling kept) => switch (kept.scope) {
  'S1' => List.filled(8, 41),
  'S2' => List.filled(8, 42),
  'S3' => List.filled(8, 43),
  _ => List.filled(8, 49),
};

Future<(SalaHarness, ProviderContainer)> _naCasa(
  WidgetTester tester,
  List<KeptRetelling> guardados, {
  SalaHarness? harness,
}) async {
  _umIpadEmPe(tester);
  final sala = harness ?? SalaHarness(filaEmMemoria: true);
  sala.room
    ..passageScenes = _cenas
    ..keptRetellings = guardados
    ..keptAudio = {
      for (final kept in guardados)
        kept.audioUrl: Uint8List.fromList(_bytesOf(kept)),
    };
  final container = await pumpSala(tester, sala);
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.goConversa(book: 'Ruth');
  await tester.pump(const Duration(milliseconds: 200));
  notifier.goEnsaio();
  await tester.pump(const Duration(milliseconds: 400));
  return (sala, container);
}

String _cena(int n) => 'Cena $n — ${_cenas[n - 1].title}';

Finder _linha(int n) => find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      (widget.properties.label == _cena(n) ||
          (widget.properties.label?.startsWith('${_cena(n)}, ') ?? false)),
);

Finder _naLinha(int n, String controle) =>
    find.descendant(of: _linha(n), matching: byLabel(controle));

Finder _textoNaLinha(int n, String texto) =>
    find.descendant(of: _linha(n), matching: find.text(texto));

final _algumaLinhaTocando = find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      (widget.properties.label?.startsWith('Cena ') ?? false) &&
      widget.properties.label!.endsWith(', $_tocando'),
);

Future<void> _passo(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 100));

Future<void> _ate(
  WidgetTester tester,
  String oQue,
  bool Function() pronto, {
  Duration limit = const Duration(seconds: 5),
}) => waitFor(oQue, pronto, limit: limit, step: () => _passo(tester));

Future<void> _tocar(WidgetTester tester, Finder alvo) async {
  await tester.ensureVisible(alvo);
  await tester.tap(alvo, warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 200));
}

bool _tocou(SalaHarness harness, KeptRetelling kept) =>
    harness.playback.played.any(
      (path) =>
          File(path).existsSync() &&
          _iguais(File(path).readAsBytesSync(), _bytesOf(kept)),
    );

bool _tocaPorUltimo(SalaHarness harness, KeptRetelling kept) =>
    harness.playback.played.isNotEmpty &&
    File(harness.playback.played.last).existsSync() &&
    _iguais(
      File(harness.playback.played.last).readAsBytesSync(),
      _bytesOf(kept),
    );

bool _iguais(List<int> a, List<int> b) =>
    a.length == b.length &&
    [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((same) => same);

bool _viva(WidgetTester tester, Finder alvo) =>
    tester.widget<Semantics>(alvo).properties.enabled ?? true;

double _centro(WidgetTester tester, Finder alvo) => tester.getCenter(alvo).dx;

Future<void> _gravarEGuardar(WidgetTester tester, int n) async {
  await _tocar(tester, _naLinha(n, _gravar));
  await _tocar(tester, _naLinha(n, _parar));
  await _tocar(tester, offTheRows(_enviarAGravacao));
  await letTheRehearsalReachTheRoom(tester);
}

Future<void> _aSalaNomear(
  WidgetTester tester,
  ProviderContainer container,
  int partes,
) => theRoomNamesTheParts(tester, container, parts: partes);

void main() {
  testWidgets(
    'a scene row whose scene has a kept retelling offers «Ouvir como vocês '
    'contaram esta parte» before its record control',
    (tester) async {
      final (_, container) = await _naCasa(tester, [_s2]);

      final botao = _naLinha(2, _comoContaram);
      expect(botao, findsOneWidget);
      expect(_viva(tester, botao), isTrue);
      expect(
        _centro(tester, botao),
        lessThan(_centro(tester, _naLinha(2, _gravar))),
        reason: 'o botão do conto guardado não vinha antes de «Gravar»',
      );
      closeTheRoom(container);
    },
  );

  testWidgets('once the scene has a take its kept retelling sits before '
      '«Ouvir»', (tester) async {
    final (_, container) = await _naCasa(tester, [_s2]);

    await _gravarEGuardar(tester, 2);
    await _aSalaNomear(tester, container, 1);

    final botao = _naLinha(2, _comoContaram);
    expect(botao, findsOneWidget);
    expect(
      _centro(tester, botao),
      lessThan(_centro(tester, _naLinha(2, _ouvir))),
    );
    expect(
      _centro(tester, _naLinha(2, _ouvir)),
      lessThan(_centro(tester, _naLinha(2, _gravarDeNovo))),
    );
    closeTheRoom(container);
  });

  testWidgets('a tap on a scene row\'s kept retelling plays that retelling', (
    tester,
  ) async {
    final (harness, container) = await _naCasa(tester, [_s1, _s2]);

    await _tocar(tester, _naLinha(2, _comoContaram));
    await _ate(
      tester,
      'o conto da cena 2 tocar',
      () => _tocaPorUltimo(harness, _s2),
    );

    expect(harness.room.keptRetellingsFetched, contains(_s2.audioUrl));
    expect(_tocou(harness, _s1), isFalse, reason: 'tocou o conto da cena 1');
    closeTheRoom(container);
  });

  testWidgets('a tap on a kept retelling stops the part that was playing', (
    tester,
  ) async {
    final (harness, container) = await _naCasa(tester, [_s2]);
    await _gravarEGuardar(tester, 1);
    await _aSalaNomear(tester, container, 1);
    await _tocar(tester, _naLinha(1, _ouvir));
    await _ate(
      tester,
      'a parte 1 tocar',
      () => _algumaLinhaTocando.evaluate().isNotEmpty,
    );

    await _tocar(tester, _naLinha(2, _comoContaram));
    await _ate(
      tester,
      'o conto da cena 2 tocar',
      () => _tocaPorUltimo(harness, _s2),
    );

    expect(_tocaPorUltimo(harness, _s2), isTrue);
    expect(
      byLabel('${_cena(1)}, $_tocando'),
      findsNothing,
      reason: 'a linha 1 seguia «tocando» com o conto no ar',
    );
    closeTheRoom(container);
  });

  testWidgets(
    'a kept retelling playing on the home is no part: no row reads «tocando», '
    'the wood play still reads «Ouvir», and «Gravar» on a row stops it and '
    'records',
    (tester) async {
      final (harness, container) = await _naCasa(tester, [_s2]);
      await _gravarEGuardar(tester, 1);
      await _aSalaNomear(tester, container, 1);

      await _tocar(tester, _naLinha(2, _comoContaram));
      await _ate(
        tester,
        'o conto da cena 2 soar',
        () => _tocaPorUltimo(harness, _s2) && harness.playback.sounding,
      );

      expect(_algumaLinhaTocando, findsNothing);
      expect(offTheRows(_ouvir), findsOneWidget);
      expect(offTheRows(_parar), findsNothing);

      await _tocar(tester, _naLinha(3, _gravar));

      expect(
        harness.playback.sounding,
        isFalse,
        reason: 'o conto seguia soando com a cena 3 gravando',
      );
      expect(_naLinha(3, _parar), findsOneWidget);
      closeTheRoom(container);
    },
  );

  testWidgets(
    'a scene-by-scene home with a whole-passage kept retelling shows «ouvir '
    'como vocês contaram a passagem inteira» under the rows, and its tap '
    'plays it',
    (tester) async {
      final (harness, container) = await _naCasa(tester, [_inteira]);

      final inteira = find.text(_aPassagemInteira);
      expect(inteira, findsOneWidget);
      expect(
        tester.getTopLeft(inteira).dy,
        greaterThan(tester.getBottomLeft(_linha(4)).dy),
      );

      await _tocar(tester, inteira);
      await _ate(
        tester,
        'o conto inteiro tocar',
        () => _tocaPorUltimo(harness, _inteira),
      );
      expect(_tocaPorUltimo(harness, _inteira), isTrue);
      closeTheRoom(container);
    },
  );

  testWidgets(
    'a whole-passage home offers its kept whole retelling on its one row and '
    'no «a passagem inteira» line',
    (tester) async {
      final (_, container) = await _naCasa(tester, [_inteira]);

      await _tocar(tester, find.text(_gravarAPassagemInteira));
      await _ate(
        tester,
        'a casa gravar a passagem inteira',
        () => container.read(salaSessionProvider).recordsTheWhole,
      );

      expect(byLabel(_passagemInteira), findsOneWidget);
      final botao = onTheRows(_comoContaram);
      expect(botao, findsOneWidget);
      expect(
        _centro(tester, botao),
        lessThan(_centro(tester, onTheRows(_gravar))),
      );
      expect(find.text(_aPassagemInteira), findsNothing);
      closeTheRoom(container);
    },
  );

  testWidgets(
    'while a take records, every row\'s kept retelling and «a passagem '
    'inteira» are disabled and a tap plays nothing',
    (tester) async {
      final (harness, container) = await _naCasa(tester, [_s2, _inteira]);

      await _tocar(tester, _naLinha(1, _gravar));

      final botao = _naLinha(2, _comoContaram);
      final inteira = inTheHome(_aPassagemInteira);
      expect(_viva(tester, botao), isFalse);
      expect(_viva(tester, inteira), isFalse);
      await _tocar(tester, botao);
      await _tocar(tester, inteira);
      await _passo(tester);
      expect(harness.room.keptRetellingsFetched, isEmpty);
      expect(_tocou(harness, _s2), isFalse);
      expect(_tocou(harness, _inteira), isFalse);

      await _tocar(tester, _naLinha(1, _parar));
      await _ate(
        tester,
        'os contos voltarem a viver',
        () => _viva(tester, botao) && _viva(tester, inteira),
      );
      expect(_viva(tester, botao), isTrue);
      expect(_viva(tester, inteira), isTrue);
      closeTheRoom(container);
    },
  );

  group('a kept retelling still being fetched does not play late', () {
    testWidgets(
      'a kept retelling still being fetched when a take starts recording '
      'does not play over it',
      (tester) async {
        final (harness, container) = await _naCasa(tester, [_s2]);
        harness.room.holdNextKeptRetelling();

        await _tocar(tester, _naLinha(2, _comoContaram));
        await _tocar(tester, _naLinha(1, _gravar));
        harness.room.finishHeldKeptRetelling();
        for (var vez = 0; vez < 10; vez++) {
          await _passo(tester);
        }

        expect(harness.room.keptRetellingsFetched, contains(_s2.audioUrl));
        expect(_tocou(harness, _s2), isFalse);
        expect(_naLinha(1, _parar), findsOneWidget);
        closeTheRoom(container);
      },
    );

    testWidgets(
      'a kept retelling that lands after another was tapped never plays',
      (tester) async {
        final (harness, container) = await _naCasa(tester, [_s2, _s3]);
        await _tocar(tester, _naLinha(3, _comoContaram));
        await _ate(
          tester,
          'o conto da cena 3 tocar',
          () => _tocaPorUltimo(harness, _s3),
        );
        harness.room.holdNextKeptRetelling();

        await _tocar(tester, _naLinha(2, _comoContaram));
        await _tocar(tester, _naLinha(3, _comoContaram));
        harness.room.finishHeldKeptRetelling();
        for (var vez = 0; vez < 10; vez++) {
          await _passo(tester);
        }

        expect(harness.room.keptRetellingsFetched, contains(_s2.audioUrl));
        expect(_tocaPorUltimo(harness, _s3), isTrue);
        expect(_tocou(harness, _s2), isFalse);
        closeTheRoom(container);
      },
    );

    testWidgets(
      'a kept retelling that lands after a take was recorded and stopped '
      'never plays',
      (tester) async {
        final (harness, container) = await _naCasa(tester, [_s2]);
        harness.room.holdNextKeptRetelling();

        await _tocar(tester, _naLinha(2, _comoContaram));
        await _tocar(tester, _naLinha(1, _gravar));
        await _tocar(tester, _naLinha(1, _parar));
        await _ate(
          tester,
          'a tomada esperar o visto',
          () =>
              container.read(salaSessionProvider).ensaio ==
              EnsaioStatus.recorded,
        );
        harness.room.finishHeldKeptRetelling();
        for (var vez = 0; vez < 10; vez++) {
          await _passo(tester);
        }

        expect(harness.room.keptRetellingsFetched, contains(_s2.audioUrl));
        expect(_tocou(harness, _s2), isFalse);
        closeTheRoom(container);
      },
    );
  });

  group('a row with no kept retelling shows no button, and a home with none '
      'offers no kept retelling at all', () {
    testWidgets('only the scene with a kept retelling offers one', (
      tester,
    ) async {
      final (_, container) = await _naCasa(tester, [_s2]);

      expect(_naLinha(2, _comoContaram), findsOneWidget);
      for (final n in [1, 3, 4]) {
        expect(_naLinha(n, _comoContaram), findsNothing, reason: 'linha $n');
      }
      expect(find.text(_aPassagemInteira), findsNothing);
      closeTheRoom(container);
    });

    testWidgets('a home with no kept retelling offers none', (tester) async {
      final (_, container) = await _naCasa(tester, const []);

      expect(_linha(1), findsOneWidget);
      expect(byLabel(_comoContaram), findsNothing);
      expect(find.text(_aPassagemInteira), findsNothing);
      closeTheRoom(container);
    });
  });

  group('a row whose part is going up or failed hides its kept retelling; '
      'the other rows\' stay live', () {
    testWidgets('a part being kept hides its row\'s kept retelling until it '
        'is named by the room', (tester) async {
      final (harness, container) = await _naCasa(tester, [_s1, _s2]);
      final fila = harness.takes as FakeTakeQueue;
      fila.holdNextKeep();

      await _gravarEGuardar(tester, 1);

      expect(_naLinha(1, _comoContaram), findsNothing);
      final botao = _naLinha(2, _comoContaram);
      expect(_viva(tester, botao), isTrue);
      await _tocar(tester, botao);
      await _ate(
        tester,
        'o conto da cena 2 tocar',
        () => _tocaPorUltimo(harness, _s2),
      );

      fila.finishHeldKeep();
      await _aSalaNomear(tester, container, 1);
      expect(_naLinha(1, _comoContaram), findsOneWidget);
      closeTheRoom(container);
    });

    testWidgets('a part whose send failed hides its row\'s kept retelling', (
      tester,
    ) async {
      final (harness, container) = await _naCasa(tester, [
        _s1,
        _s2,
      ], harness: SalaHarness());
      await tester.pump(const Duration(seconds: 1));
      harness.room.unreachableTake = 'ensaio/parte-1';

      await _gravarEGuardar(tester, 1);
      await waitFor(
        'a cena 1 falhar',
        () => _textoNaLinha(1, _falhou).evaluate().isNotEmpty,
        limit: const Duration(seconds: 20),
        step: () => letTheRehearsalReachTheRoom(tester),
      );

      expect(_naLinha(1, _comoContaram), findsNothing);
      expect(_viva(tester, _naLinha(2, _comoContaram)), isTrue);
      closeTheRoom(container);
    });
  });

  test('a kept retelling tapped over a part takes the Channel alone', () {
    const parte = PartSound(0, 'parte-1.m4a');
    const conto = KeptRetellingSound('conto-S2.m4a', scope: 'S2');

    final (machine, effects) = reduce(
      const Machine(
        station: Ensaio(),
        channel: PartPlaying(parte, opened: true),
      ),
      const BeadTapped([conto]),
    );

    expect(machine.channel, const KeptRetellingPlaying(conto));
    expect(effects, contains(const PlayKeptRetelling(conto)));
    expect(effects.whereType<PlayPart>(), isEmpty);
  });
}
