import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

KeptTake _parte(int n) => KeptTake(
  scopeId: KeptScope.parte(n),
  path: 'parte-$n.m4a',
  takeId: 'gravacao-$n',
);

const _inteiro = KeptTake(
  scopeId: KeptScope.whole,
  path: 'inteiro.m4a',
  takeId: 'gravacao-inteira',
);

Trecho _trecho(String nome, int parte, {bool contado = true}) => Trecho(
  segmentId: nome,
  takeId: 'gravacao-de-$nome',
  parte: parte,
  from: Duration.zero,
  to: const Duration(seconds: 4),
  contado: contado,
  lugarFrom: Duration.zero,
  lugarTo: const Duration(seconds: 4),
);

List<(String?, int?)> _naTela(SalaSessionState estado, List<Trecho> trechos) =>
    [
      for (final trecho in trechos)
        (
          trecho.segmentId,
          trecho.parte < 0
              ? null
              : switch (estado.partes.elementAtOrNull(trecho.parte)) {
                  final parte? => KeptScope.numberOf(parte.scopeId) ?? 0,
                  null => null,
                },
        ),
    ];

void main() {
  test('a part laid in below a told frase leaves every frase on its own part, '
      'and one with no part stays without one', () {
    final antes = SalaSessionState(
      keptTakes: [_parte(1), _parte(3)],
      btTrechos: [
        _trecho('trecho-1', 0),
        _trecho('trecho-3', 1),
        _trecho('trecho-de-fora', -1),
      ],
      btTrechosRegravados: [_trecho('trecho-velho-3', 1)],
    );

    final depois = antes.copyWith(keptTakes: [...antes.keptTakes, _parte(2)]);

    expect(
      _naTela(depois, depois.btTrechos),
      [('trecho-1', 1), ('trecho-3', 3), ('trecho-de-fora', null)],
      reason:
          'a parte 2 entrava antes da 3 e a frase contada da parte 3 passava '
          'a ler «parte 2»',
    );
    expect(_naTela(depois, depois.btTrechosRegravados), [
      ('trecho-velho-3', 3),
    ]);
  });

  test('a part that leaves from below a told frase moves the frase down with '
      'its part, never onto the next one', () {
    final antes = SalaSessionState(
      keptTakes: [_parte(1), _parte(2), _parte(3)],
      btTrechos: [_trecho('trecho-1', 0), _trecho('trecho-3', 2)],
      btTrechosRegravados: [_trecho('trecho-velho-3', 2)],
    );

    final depois = antes.copyWith(keptTakes: [_parte(1), _parte(3)]);

    expect(
      _naTela(depois, depois.btTrechos),
      [('trecho-1', 1), ('trecho-3', 3)],
      reason:
          'a parte 2 saía e a frase da parte 3 apontava para depois da última '
          'parte',
    );
    expect(_naTela(depois, depois.btTrechosRegravados), [
      ('trecho-velho-3', 3),
    ]);
  });

  test('a whole set aside by the first scene part takes its re-recorded frases '
      'with it, so none reads «parte 1»', () {
    final antes = SalaSessionState(
      keptTakes: const [_inteiro],
      btTrechosRegravados: [_trecho('trecho-velho-do-inteiro', 0)],
    );

    final depois = antes.copyWith(keptTakes: [_inteiro, _parte(1)]);

    expect(
      _naTela(depois, depois.btTrechosRegravados),
      isEmpty,
      reason:
          'a frase regravada do inteiro ficava no lugar 0 e lia «parte 1» '
          'quando a cena 1 chegava',
    );
  });

  test('a part named in place leaves the row of frases untouched, so a read '
      'sent before it still lands', () {
    final antes = SalaSessionState(
      keptTakes: [
        _parte(1),
        KeptTake(scopeId: KeptScope.parte(2), path: 'parte-2.m4a'),
      ],
      btTrechos: [_trecho('trecho-1', 0), _trecho('trecho-2', 1)],
    );

    final depois = antes.copyWith(keptTakes: [_parte(1), _parte(2)]);

    expect(
      identical(depois.btTrechos, antes.btTrechos),
      isTrue,
      reason:
          'dar nome a uma parte refazia a fila de frases, e a releitura da '
          'sala achava que a equipe tinha mexido nela',
    );
  });
}
