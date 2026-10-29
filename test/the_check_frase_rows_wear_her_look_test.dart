import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/features/sala/presentation/widgets/frase_list.dart';

import 'sala_screen_test.dart' show contrastOf;

Future<void> _pump(WidgetTester tester, String look, List<FraseRow> rows) =>
    tester.pumpWidget(
      MaterialApp(
        key: ValueKey(look),
        theme: look == 'dark' ? AppTheme.dark : AppTheme.light,
        home: Scaffold(
          body: FraseList(language: 'pt', rows: rows),
        ),
      ),
    );

FraseRow _aFrase({int n = 1, int? parte, double share = 1}) =>
    FraseRow(n: n, parte: parte, share: share, onHear: () {});

Finder _aBarra(int n) => find.descendant(
  of: _oCartao(n),
  matching: find.byType(FractionallySizedBox),
);

Finder _oCartao(int n) => find
    .ancestor(
      of: find.descendant(
        of: find.byType(FraseList),
        matching: find.text('$n'),
      ),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).borderRadius ==
                BorderRadius.circular(16),
      ),
    )
    .first;

BoxDecoration _pintura(WidgetTester tester, Finder box) =>
    tester.widget<Container>(box).decoration! as BoxDecoration;

Color _oTrilho(WidgetTester tester, int n) => _pintura(
  tester,
  find.ancestor(of: _aBarra(n), matching: find.byType(Container)).first,
).color!;

Color _oPreenchimento(WidgetTester tester, int n) => _pintura(
  tester,
  find.descendant(of: _aBarra(n), matching: find.byType(Container)).first,
).color!;

BoxDecoration _oDisco(WidgetTester tester, int n) =>
    tester
            .widget<DecoratedBox>(
              find
                  .ancestor(
                    of: find.descendant(
                      of: find.byType(FraseList),
                      matching: find.text('$n'),
                    ),
                    matching: find.byType(DecoratedBox),
                  )
                  .first,
            )
            .decoration
        as BoxDecoration;

Color? _oNumero(WidgetTester tester, int n) => tester
    .widget<Text>(
      find.descendant(of: find.byType(FraseList), matching: find.text('$n')),
    )
    .style
    ?.color;

void main() {
  testWidgets('in the dark look a frase bar reads against its track, not '
      'one brown on another', (tester) async {
    await _pump(tester, 'dark', [_aFrase(share: .5)]);
    final chao = AppTheme.dark.scaffoldBackgroundColor;
    final cartao = Color.alphaBlend(_pintura(tester, _oCartao(1)).color!, chao);
    final trilho = Color.alphaBlend(_oTrilho(tester, 1), cartao);
    final barra = Color.alphaBlend(_oPreenchimento(tester, 1), trilho);

    expect(
      contrastOf(barra, trilho),
      greaterThanOrEqualTo(3),
      reason:
          'no escuro o cord 4A4336 ficava sobre um trilho de 453E34, 1,08:1, '
          'e a barra sumia',
    );
  });

  for (final (look, verdeClaro) in [
    ('light', const Color(0xFF777D45)),
    ('dark', const Color(0xFFAAB07E)),
  ]) {
    testWidgets('in the $look look a frase bar fills in her verde-claro over '
        'her sand track, not the cord over a line', (tester) async {
      await _pump(tester, look, [_aFrase(share: .5)]);

      expect(
        _oPreenchimento(tester, 1),
        verdeClaro.withValues(alpha: .85),
        reason: 'a barra enchia de cord, não do verde-claro dela a .85',
      );
      expect(
        _oTrilho(tester, 1),
        const Color.fromRGBO(199, 194, 159, .28),
        reason: 'o trilho era a linha da tela, não a areia dela a .28',
      );
    });
  }

  for (final (look, veu, areia) in [
    ('light', const Color.fromRGBO(255, 255, 255, .4), const Color(0xFFC5C29F)),
    ('dark', const Color.fromRGBO(236, 234, 220, .05), const Color(0xFF6E6A57)),
  ]) {
    testWidgets('in the $look look a frase card is her wash with a sand '
        'edge, not a solid card with a hairline', (tester) async {
      await _pump(tester, look, [_aFrase()]);
      final cartao = _pintura(tester, _oCartao(1));

      expect(
        cartao.color,
        veu,
        reason: 'o cartão era o card sólido, não o véu dela',
      );
      expect(
        (cartao.border! as Border).top.color,
        areia,
        reason: 'a borda era a linha da tela, não a areia dela',
      );
    });
  }

  for (final (look, areia, tinta) in [
    ('light', const Color(0xFFC5C29F), const Color(0xFF0A0703)),
    ('dark', const Color(0xFF6E6A57), const Color(0xFFF2EDE1)),
  ]) {
    testWidgets('in the $look look a frase number sits on her sand disc, '
        'written in ink, not paper on a muted disc', (tester) async {
      await _pump(tester, look, [_aFrase()]);

      expect(
        _oDisco(tester, 1).color,
        areia,
        reason: 'o disco era o mut da tela, não a areia dela',
      );
      expect(
        _oNumero(tester, 1),
        tinta,
        reason: 'o número era escrito no papel; na areia só a tinta se lê',
      );
    });
  }
}
