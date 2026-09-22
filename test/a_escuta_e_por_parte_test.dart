import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _notifierPath = 'lib/features/sala/data/session_notifier.dart';
const _escutaPath = 'lib/features/sala/domain/escuta_das_partes.dart';

/// The names of the concatenated timeline. Anything that writes the listening ledger with
/// one of these is measuring a part against the passage the parts are glued into, which is
/// the coordinate a re-recorded part destroys.
const _aritmeticaGlobal = [
  '_inicioDaParteMs',
  '_fimDaParteMs',
  'btFimDasPartesMs',
  '_posicaoGlobal',
];

/// Where the ledger is written, and how many times each writer is called. Reading it back
/// is not one of them: the report is drawn against the parts, which is a list and not a
/// place.
///
/// The count is part of the net. A method losing one of its two call sites is a write the
/// room stopped doing — holding the rehearsal and letting it run again, say — and a set of
/// names alone answers that nothing changed.
const _escrevemNaEscuta = {'abrir': 2, 'fechar': 1, 'medida': 1, 'inteira': 1};

/// Every position the room is allowed to hand the ledger: the player's own answer, the
/// length a part measured of itself, the length a part was measured at without playing,
/// and the part's own beginning.
const _posicoesLocais = {
  '0',
  '_playback.position.inMilliseconds',
  'medido',
  'quanto.inMilliseconds',
  'fim',
};

/// The one name in [_posicoesLocais] that is not itself a reading of the player, pinned to
/// its definition so the allowlist cannot be satisfied by a global under the same name.
const _fimEOQueOPlayerDiz =
    'final fim = ate ?? _playback.position.inMilliseconds;';

final _commentPattern = RegExp(r'//.*$', multiLine: true);

String _fonteSemComentarios(String path) =>
    File(path).readAsStringSync().replaceAll(_commentPattern, '');

/// Every call to the ledger in [fonte], as (method, arguments as written).
List<(String, List<String>)> _chamadasAEscuta(String fonte) {
  final chamadas = <(String, List<String>)>[];
  final abertura = RegExp(r'_escuta\.(\w+)\(');
  for (final match in abertura.allMatches(fonte)) {
    var profundidade = 1;
    var onde = match.end;
    while (onde < fonte.length && profundidade > 0) {
      if (fonte[onde] == '(') profundidade++;
      if (fonte[onde] == ')') profundidade--;
      onde++;
    }
    final dentro = fonte.substring(match.end, onde - 1);
    chamadas.add((match.group(1)!, _argumentos(dentro)));
  }
  return chamadas;
}

List<String> _argumentos(String dentro) {
  final argumentos = <String>[];
  var profundidade = 0;
  var comeco = 0;
  for (var onde = 0; onde < dentro.length; onde++) {
    final caractere = dentro[onde];
    if (caractere == '(' || caractere == '[') profundidade++;
    if (caractere == ')' || caractere == ']') profundidade--;
    if (caractere == ',' && profundidade == 0) {
      argumentos.add(dentro.substring(comeco, onde).trim());
      comeco = onde + 1;
    }
  }
  final ultimo = dentro.substring(comeco).trim();
  if (ultimo.isNotEmpty) argumentos.add(ultimo);
  return argumentos;
}

void main() {
  test('o registro da escuta não conhece a régua da passagem colada', () {
    final fonte = _fonteSemComentarios(_escutaPath);

    for (final nome in _aritmeticaGlobal) {
      expect(
        fonte.contains(nome),
        isFalse,
        reason:
            'o registro mede cada parte contra ela mesma; $nome é a '
            'coordenada da passagem colada, que a regravação de uma parte '
            'destrói',
      );
    }
  });

  test('tudo o que escreve na escuta entrega posição do próprio arquivo', () {
    final fonte = _fonteSemComentarios(_notifierPath);
    final chamadas = _chamadasAEscuta(fonte);

    expect(
      chamadas,
      isNotEmpty,
      reason: 'se nada chama o registro, esta rede não guarda coisa nenhuma',
    );

    expect(
      {
        for (final metodo in chamadas.map((chamada) => chamada.$1).toSet())
          metodo: chamadas.where((chamada) => chamada.$1 == metodo).length,
      }..removeWhere((metodo, _) => !_escrevemNaEscuta.containsKey(metodo)),
      _escrevemNaEscuta,
      reason:
          'a rede só vale enquanto conhece cada escritor do registro e '
          'quantas vezes ele é chamado: um método novo, ou um lugar de '
          'escrita que sumiu, passaria por ela sem ser visto',
    );

    for (final (metodo, argumentos) in chamadas) {
      if (!_escrevemNaEscuta.containsKey(metodo)) continue;
      final posicao = argumentos.last;
      expect(
        _posicoesLocais,
        contains(posicao),
        reason:
            '_escuta.$metodo recebe "$posicao", que não é uma posição '
            'lida do arquivo que está tocando',
      );
    }
  });

  test(
    'o fim de um trecho de escuta é o que o player responde, e nada mais',
    () {
      final fonte = _fonteSemComentarios(_notifierPath);

      expect(
        fonte.contains(_fimEOQueOPlayerDiz),
        isTrue,
        reason:
            'fim é o único nome da lista que não se lê sozinho: preso à '
            'sua definição, a lista não pode ser satisfeita por um global '
            'batizado com o mesmo nome',
      );
    },
  );

  test('a sala não diz mais recontar nem retrotradução', () {
    final retirada = RegExp(
      r'recont|retrotradução|contandoDeNovo',
      caseSensitive: false,
    );
    final ofensores = <String>[];

    for (final arquivo
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((arquivo) => arquivo.path.endsWith('.dart'))) {
      final fonte = arquivo.readAsStringSync().replaceAll(_commentPattern, '');
      if (retirada.hasMatch(fonte)) ofensores.add(arquivo.path);
    }

    expect(
      ofensores,
      isEmpty,
      reason:
          'retrotradução e recontar são as palavras que a Retro deixou '
          'de usar: contar é da Conversa e recontar é da Verificação '
          'Externa: $ofensores',
    );
  });
}
