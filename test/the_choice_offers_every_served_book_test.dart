import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/sala_colors.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show settle;
import 'served_books.dart';

const _panoramaPt = '◈ Panorama do Livro';

SalaHarness _aRoomServing(List<String> books, {String? lingua = 'pt'}) =>
    SalaHarness(filaEmMemoria: true, lingua: lingua)
      ..room.books = books
      ..room.passagesOfBook = {
        'Esther': estherList,
        'Jonah': jonahList,
        'Ruth': ruthList,
      };

Future<ProviderContainer> _theChoice(
  WidgetTester tester,
  SalaHarness harness,
) async {
  final container = await pumpSala(tester, harness);
  await _catchUp(tester);
  return container;
}

Future<void> _catchUp(WidgetTester tester) async {
  await tester.runAsync(settle);
  await tester.pump(const Duration(milliseconds: 1500));
}

double _top(WidgetTester tester, Finder finder) => tester.getTopLeft(finder).dy;

Finder _pillOf(Finder words) => find
    .ancestor(
      of: words,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).border != null,
      ),
    )
    .first;

bool _tinted(WidgetTester tester, Finder words) {
  final decoration =
      tester.widget<DecoratedBox>(_pillOf(words)).decoration as BoxDecoration;
  return decoration.color == ShemaBrand.azul.withValues(alpha: 0.18);
}

void main() {
  testWidgets(
    'the Choice shows one block per served book, Ester, Jonas and Rute, each '
    'starting with «◈ Panorama do Livro»',
    (tester) async {
      await _theChoice(tester, _aRoomServing(servedBooks));

      final panoramas = find.text(_panoramaPt);
      expect(panoramas, findsNWidgets(3));
      final topToBottom = [
        find.text('ESTER'),
        panoramas.at(0),
        find.text('Ester 1:1–9'),
        find.text('JONAS'),
        panoramas.at(1),
        find.text('Jonas 1:1–3'),
        find.text('RUTE'),
        panoramas.at(2),
        find.text('Rute 1:1–5'),
      ];
      final heights = [for (final line in topToBottom) _top(tester, line)];
      expect(heights, orderedEquals([...heights]..sort()));
      expect(heights.toSet(), hasLength(heights.length));
    },
  );

  testWidgets(
    'each block holds its book\'s passages, 18 in Ester, 5 in Jonas, 14 in Rute',
    (tester) async {
      await _theChoice(tester, _aRoomServing(servedBooks));

      expect(find.textContaining(RegExp(r'^Ester \d')), findsNWidgets(18));
      expect(find.textContaining(RegExp(r'^Jonas \d')), findsNWidgets(5));
      expect(find.textContaining(RegExp(r'^Rute \d')), findsNWidgets(14));
      expect(find.text('Jonas 2:10–3:10'), findsOneWidget);
      expect(find.text('Rute 4:18-22'), findsOneWidget);
    },
  );

  testWidgets('the blocks follow the room\'s order, not the tablet\'s', (
    tester,
  ) async {
    await _theChoice(tester, _aRoomServing(const ['Ruth', 'Jonah']));

    expect(find.text('ESTER'), findsNothing);
    expect(
      _top(tester, find.text('RUTE')),
      lessThan(_top(tester, find.text('JONAS'))),
    );
  });

  testWidgets('only the Panorama the team left is tinted', (tester) async {
    final container = await _theChoice(tester, _aRoomServing(servedBooks));

    await tester.ensureVisible(find.text(_panoramaPt).at(1));
    await tester.tap(find.text(_panoramaPt).at(1));
    await _catchUp(tester);
    expect(container.read(salaSessionProvider).panoramaSessionId, isNotNull);
    container.read(salaSessionProvider.notifier).leaveThePassage();
    await _catchUp(tester);

    final panoramas = find.text(_panoramaPt);
    expect(
      [for (var at = 0; at < 3; at++) _tinted(tester, panoramas.at(at))],
      [false, true, false],
    );
  });

  testWidgets(
    'in English the blocks read Esther, Jonah and Ruth, and the Panorama reads '
    '«◈ Book Panorama»',
    (tester) async {
      await _theChoice(tester, _aRoomServing(servedBooks, lingua: null));

      await tester.tap(find.text('EN'));
      await _catchUp(tester);

      final heights = [
        for (final heading in ['ESTHER', 'JONAH', 'RUTH'])
          _top(tester, find.text(heading)),
      ];
      expect(heights, orderedEquals([...heights]..sort()));
      expect(find.text('◈ Book Panorama'), findsNWidgets(3));
      expect(find.text(_panoramaPt), findsNothing);
    },
  );
}
