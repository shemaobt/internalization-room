import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/escuta_das_partes.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';

KeptTake _parte(int n, String arquivo, {String? nome}) =>
    KeptTake(scopeId: KeptScope.parte(n), path: arquivo, takeId: nome);

List<Map<String, Object?>> _relato(
  EscutaDasPartes escuta,
  List<KeptTake> partes,
) => [for (final entrada in escuta.relato(partes)) entrada.toJson()];

void main() {
  test('um ensaio de três partes ouvido inteiro é relatado parte a parte, '
      'cada uma no relógio do próprio arquivo', () {
    final escuta = EscutaDasPartes();
    final partes = [
      _parte(1, 'p1.m4a', nome: 'gravacao-1'),
      _parte(2, 'p2.m4a', nome: 'gravacao-2'),
      _parte(3, 'p3.m4a', nome: 'gravacao-3'),
    ];

    for (final (arquivo, quanto) in [
      ('p1.m4a', 10000),
      ('p2.m4a', 8000),
      ('p3.m4a', 12000),
    ]) {
      escuta.abrir(arquivo, 0);
      escuta.medida(arquivo, quanto);
      escuta.fechar(arquivo, quanto);
    }

    expect(
      _relato(escuta, partes),
      [
        {
          'take_id': 'gravacao-1',
          'played_ranges': [
            [0, 10000],
          ],
          'clip_duration_ms': 10000,
        },
        {
          'take_id': 'gravacao-2',
          'played_ranges': [
            [0, 8000],
          ],
          'clip_duration_ms': 8000,
        },
        {
          'take_id': 'gravacao-3',
          'played_ranges': [
            [0, 12000],
          ],
          'clip_duration_ms': 12000,
        },
      ],
      reason:
          'cada parte é medida contra si mesma; somadas numa régua só, '
          'a escuta de uma parte não podia ser nomeada nem sobreviver à '
          'regravação de outra',
    );
  });

  test(
    'a parte gravada de novo recomeça a escuta e as outras seguem com a sua',
    () {
      final escuta = EscutaDasPartes();
      for (final (arquivo, quanto) in [
        ('p1.m4a', 10000),
        ('p2.m4a', 8000),
        ('p3.m4a', 12000),
      ]) {
        escuta.abrir(arquivo, 0);
        escuta.medida(arquivo, quanto);
        escuta.fechar(arquivo, quanto);
      }

      final depoisDoConserto = [
        _parte(1, 'p1.m4a', nome: 'gravacao-1'),
        _parte(2, 'p2b.m4a', nome: 'gravacao-2b'),
        _parte(3, 'p3.m4a', nome: 'gravacao-3'),
      ];

      expect(
        _relato(escuta, depoisDoConserto),
        [
          {
            'take_id': 'gravacao-1',
            'played_ranges': [
              [0, 10000],
            ],
            'clip_duration_ms': 10000,
          },
          {
            'take_id': 'gravacao-3',
            'played_ranges': [
              [0, 12000],
            ],
            'clip_duration_ms': 12000,
          },
        ],
        reason:
            'a parte trocada é outro arquivo: nada foi ouvido dela ainda, '
            'e a escuta das vizinhas não tem por que ser jogada fora junto',
      );

      escuta.abrir('p2b.m4a', 0);
      escuta.medida('p2b.m4a', 5000);
      escuta.fechar('p2b.m4a', 5000);

      expect(
        _relato(escuta, depoisDoConserto),
        [
          {
            'take_id': 'gravacao-1',
            'played_ranges': [
              [0, 10000],
            ],
            'clip_duration_ms': 10000,
          },
          {
            'take_id': 'gravacao-2b',
            'played_ranges': [
              [0, 5000],
            ],
            'clip_duration_ms': 5000,
          },
          {
            'take_id': 'gravacao-3',
            'played_ranges': [
              [0, 12000],
            ],
            'clip_duration_ms': 12000,
          },
        ],
        reason:
            'a parte nova é mais curta que a que substituiu, e é contra o '
            'próprio tamanho dela que a escuta dela é medida',
      );
    },
  );

  test('uma parte ouvida inteira sem tocar entra com o alcance dela toda', () {
    final escuta = EscutaDasPartes();
    escuta.inteira('p1.m4a', 30000);

    expect(
      _relato(escuta, [_parte(1, 'p1.m4a', nome: 'gravacao-1')]),
      [
        {
          'take_id': 'gravacao-1',
          'played_ranges': [
            [0, 30000],
          ],
          'clip_duration_ms': 30000,
        },
      ],
      reason:
          'a parte que a retomada pula foi contada inteira na rodada '
          'anterior, e o portão da sala pede a evidência de ponta a ponta',
    );
  });

  test('um fecho que não é depois da abertura não registra nada', () {
    final escuta = EscutaDasPartes();
    escuta.abrir('p1.m4a', 4000);
    escuta.medida('p1.m4a', 10000);
    escuta.fechar('p1.m4a', 4000);

    expect(
      _relato(escuta, [_parte(1, 'p1.m4a', nome: 'gravacao-1')]),
      isEmpty,
      reason:
          'parar no mesmo ponto em que se começou não é ter ouvido nada, '
          'e um vão de zero milissegundos relatado como escuta é a mentira '
          'que o relato existe para não contar',
    );
  });

  test('faixas que se encostam são uma faixa só', () {
    final escuta = EscutaDasPartes();
    escuta.abrir('p1.m4a', 0);
    escuta.fechar('p1.m4a', 5000);
    escuta.abrir('p1.m4a', 5000);
    escuta.medida('p1.m4a', 10000);
    escuta.fechar('p1.m4a', 10000);

    expect(
      _relato(escuta, [_parte(1, 'p1.m4a', nome: 'gravacao-1')]),
      [
        {
          'take_id': 'gravacao-1',
          'played_ranges': [
            [0, 10000],
          ],
          'clip_duration_ms': 10000,
        },
      ],
      reason:
          'a sala une o que se encosta antes de mandar, como o portão une '
          'para ler',
    );
  });

  test('a parte que a sala ainda não nomeou fica de fora do relato', () {
    final escuta = EscutaDasPartes();
    escuta.inteira('p1.m4a', 10000);
    escuta.inteira('p2.m4a', 8000);

    expect(
      _relato(escuta, [
        _parte(1, 'p1.m4a', nome: 'gravacao-1'),
        _parte(2, 'p2.m4a'),
      ]),
      [
        {
          'take_id': 'gravacao-1',
          'played_ranges': [
            [0, 10000],
          ],
          'clip_duration_ms': 10000,
        },
      ],
      reason:
          'escuta sem sujeito não é evidência de nada: a parte sem nome '
          'é tratada como não ouvida, como o envio de trecho que não sabe '
          'nomear a gravação que fatia',
    );
  });

  test('esquecer tudo esvazia o relato', () {
    final escuta = EscutaDasPartes();
    escuta.inteira('p1.m4a', 10000);
    escuta.inteira('p2.m4a', 8000);
    escuta.esquecerTudo();

    expect(
      _relato(escuta, [
        _parte(1, 'p1.m4a', nome: 'gravacao-1'),
        _parte(2, 'p2.m4a', nome: 'gravacao-2'),
      ]),
      isEmpty,
    );
  });
}
