import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _retroViewPath =
    'lib/features/sala/presentation/widgets/retro_view.dart';
const _ondeMoraGradePath =
    'lib/features/sala/presentation/widgets/onde_mora_grade.dart';
// The Conversation's line moved out of the view and into the script the circle reads by
// the room's language (ENG-823); the guard follows the line to where it lives now.
const _conversaViewPath = 'lib/features/sala/domain/facilitator_script.dart';

const _conversaLine =
    "'Conversem entre vocês — tocar quando quiserem me contar'";

const _rotulosDeTraduzir = {
  'Cortar aqui e traduzir esta parte',
  'Traduzir esta parte na língua ponte',
  'Ouvir e traduzir a gravação de novo',
  'Terminei de traduzir',
  'Tocar para traduzir este pedaço em português',
  'Traduzida',
  'Ouvir a tradução em português',
  'Traduzir de novo só em português',
};

final _literalPattern = RegExp(r"'([^'\\]|\\.)*'");
final _aspaDuplaPattern = RegExp(r'"([^"\\]|\\.)*"');
final _literalAdjacentePattern = RegExp(r"'([^'\\]|\\.)*'\s*'");
final _retiradaPattern =
    RegExp(r'contar|contad[ao]|recont', caseSensitive: false);
final _commentPattern = RegExp(r'//.*$', multiLine: true);

String _fonteSemComentarios(String path) =>
    File(path).readAsStringSync().replaceAll(_commentPattern, '');

Set<String> _literaisEm(String path) => _literalPattern
    .allMatches(_fonteSemComentarios(path))
    .map((match) => match.group(0)!)
    .map((literal) => literal.substring(1, literal.length - 1))
    .toSet();

void main() {
  test(
      'RetroView e OndeMoraGrade não carregam mais a palavra retirada '
      'da retroverificação', () {
    for (final path in [_retroViewPath, _ondeMoraGradePath]) {
      final offensores = _literaisEm(path)
          .where((literal) => _retiradaPattern.hasMatch(literal))
          .toList();

      expect(offensores, isEmpty,
          reason: 'a palavra retirada da retroverificação ainda aparece em '
              '$path: $offensores');
    }
  });

  test(
      'o conjunto de rótulos que dizem traduzir/tradução é exatamente o da '
      'tabela da regra', () {
    final literais = {
      ..._literaisEm(_retroViewPath),
      ..._literaisEm(_ondeMoraGradePath),
    };
    final comTradu = literais
        .where((literal) => literal.toLowerCase().contains('tradu'));

    expect(comTradu.toSet(), _rotulosDeTraduzir,
        reason: 'um rótulo a mais, a menos ou reescrito diferente da tabela '
            'da regra escapa desta rede');
  });

  test(
      'nenhum literal escapa da extração por aspa simples: nem aspa dupla, '
      'nem literal partido em dois', () {
    for (final path in [_retroViewPath, _ondeMoraGradePath]) {
      final fonte = _fonteSemComentarios(path);

      expect(_aspaDuplaPattern.hasMatch(fonte), isFalse,
          reason: 'um rótulo escrito com aspa dupla em $path escaparia da '
              'rede, que só lê aspa simples');
      expect(_literalAdjacentePattern.hasMatch(fonte), isFalse,
          reason: 'dois literais de aspa simples adjacentes em $path '
              'seriam lidos como dois rótulos separados, não um só');
    }
  });

  test('a Conversa com o Guia continua dizendo contar', () {
    final source = File(_conversaViewPath).readAsStringSync();

    expect(source.contains(_conversaLine), isTrue,
        reason: 'a varredura da retroverificação não pode levar junto a '
            'linha da Conversa, que é a exceção da regra');
  });
}
