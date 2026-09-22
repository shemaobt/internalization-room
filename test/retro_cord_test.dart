import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/retro_cord.dart';

double _at(
  int ms, {
  required int partes,
  List<int> fimDasPartes = const [],
  int parteNoArMs = 0,
}) => cordFraction(
  atMs: ms,
  partes: partes,
  fimDasPartes: fimDasPartes,
  parteNoArMs: parteNoArMs,
);

Trecho _trecho(int from, int to, {int parte = 0}) => Trecho(
  segmentId: 'trecho-$from',
  takeId: 'gravacao-${parte + 1}',
  parte: parte,
  from: Duration(milliseconds: from),
  to: Duration(milliseconds: to),
  lugarFrom: Duration(milliseconds: from),
  lugarTo: Duration(milliseconds: to),
);

Future<void> _pump(WidgetTester tester, RetroCord cord) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: SizedBox(width: 390, height: 812, child: cord)),
    ),
  );
  await tester.pump(const Duration(milliseconds: 80));
}

void main() {
  test('a rehearsal not yet opened puts the mark at the beginning', () {
    expect(
      _at(0, partes: 2),
      0.0,
      reason:
          'sem nenhuma parte medida, dividir pela duração era dividir por zero',
    );
  });

  test('a rehearsal kept in one take still fills a whole cord', () {
    expect(_at(5000, partes: 1, parteNoArMs: 10000), 0.5);
    expect(
      _at(10000, partes: 1, fimDasPartes: [10000]),
      1.0,
      reason:
          'um ensaio guardado de uma vez só é o caso comum, e um cordão de uma '
          'conta só não diz nada à equipe',
    );
  });

  test('a part still opening holds the mark at that part\'s own edge', () {
    expect(
      _at(10000, partes: 2, fimDasPartes: [10000], parteNoArMs: 0),
      0.5,
      reason:
          'a parte abriu e ainda não foi medida — a marca não pode saltar para o '
          'fim do cordão por causa disso',
    );
  });

  test('the last part ending fills the cord and stops there', () {
    expect(_at(21000, partes: 2, fimDasPartes: [10000, 21000]), 1.0);
    expect(
      _at(99000, partes: 2, fimDasPartes: [10000, 21000]),
      1.0,
      reason:
          'a marca corria para fora do cordão quando o áudio passava do fim medido',
    );
  });

  test('splitting a stretch in two covers the same cord, not more', () {
    final inteiro = _at(9000, partes: 1, fimDasPartes: [9000]);
    final metade = _at(4500, partes: 1, fimDasPartes: [9000]);

    expect(
      metade,
      inteiro / 2,
      reason:
          'a fileira de contas crescia a cada corte e transbordava na décima; '
          'o cordão é o mesmo por mais fino que a equipe corte',
    );
  });

  test('a stretch out of a part the cord has not measured is not placed', () {
    expect(
      cordStartMs(parte: 0, dentroMs: 4000, fimDasPartes: const []),
      4000,
      reason:
          'a primeira parte começa no zero do cordão, e isso se sabe sem '
          'ter tocado nada',
    );
    expect(
      cordStartMs(parte: 1, dentroMs: 0, fimDasPartes: const [10000]),
      10000,
    );
    expect(
      cordStartMs(parte: 1, dentroMs: 0, fimDasPartes: const []),
      isNull,
      reason:
          'numa retro retomada as fronteiras ainda não foram aprendidas, e '
          'os trechos da segunda parte empilhavam no começo do cordão — em cima '
          'dos da primeira, que é o único progresso que a sala mostra',
    );
  });

  testWidgets('a stretch the room refused leaves its own length of cord bare', (
    tester,
  ) async {
    await _pump(
      tester,
      RetroCord(
        partes: 1,
        fimDasPartes: const [10000],
        parteNoArMs: 0,
        ouvidoMs: 9000,
        trechos: [_trecho(0, 4000)],
      ),
    );

    expect(
      find.descendant(
        of: find.byType(RetroCord),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
      reason:
          'o trecho recusado não vira conta oca: fica como cordão vazio, que é o '
          'tanto de ensaio que a sala ainda deve',
    );
  });

  testWidgets('the retro cord takes no touch at all', (tester) async {
    await _pump(
      tester,
      const RetroCord(
        partes: 2,
        fimDasPartes: [10000],
        parteNoArMs: 8000,
        ouvidoMs: 4000,
        trechos: [],
      ),
    );

    expect(
      find.descendant(
        of: find.byType(RetroCord),
        matching: find.byType(GestureDetector),
      ),
      findsNothing,
      reason:
          'é leitura, não controle — uma régua aqui deixaria pular trechos que a '
          'sala ainda não ouviu',
    );
  });

  testWidgets('a rehearsal with no parts draws no cord at all', (tester) async {
    await _pump(
      tester,
      const RetroCord(
        partes: 0,
        fimDasPartes: [],
        parteNoArMs: 0,
        ouvidoMs: 0,
        trechos: [],
      ),
    );

    expect(
      find.descendant(
        of: find.byType(RetroCord),
        matching: find.byType(CustomPaint),
      ),
      findsNothing,
      reason:
          'sem partes não há ensaio para medir, e um cordão vazio diria que há',
    );
  });
}
