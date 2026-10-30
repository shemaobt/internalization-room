import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/unsent_notice.dart';

import 'scenario_helpers.dart' show byLabel;

const _enviarAGravacao = 'Enviar a gravação';

const _umaParte = Duration(seconds: 48);

Future<List<int>> _pumpTheNotice(
  WidgetTester tester,
  SalaSessionState session,
) async {
  final sent = <int>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: UnsentNotice(session: session, language: 'pt', onSend: sent.add),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  return sent;
}

Finder get _sendNow => find.ancestor(
  of: find.text('Cena 1 · 0:48 — enviar agora'),
  matching: find.byType(TextButton),
);

const _unsent = {1: UnsentPart(fromAnEarlierVisit: true, length: _umaParte)};

void main() {
  testWidgets(
    'while a bring-back runs, «enviar agora» rests and a tap sends nothing',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final sent = await _pumpTheNotice(
        tester,
        const SalaSessionState(unsentParts: _unsent, bringingBack: 2),
      );

      expect(
        tester.widget<TextButton>(_sendNow).onPressed,
        isNull,
        reason:
            'o «enviar agora» ficava aceso enquanto a sala trazia as traduções',
      );
      expect(
        tester
            .getSemantics(byLabel(_enviarAGravacao))
            .flagsCollection
            .isEnabled,
        Tristate.isFalse,
      );
      await tester.tap(_sendNow, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 100));
      expect(sent, isEmpty);
      semantics.dispose();
    },
  );

  testWidgets(
    "while the home's swap runs, «enviar agora» rests and a tap sends nothing",
    (tester) async {
      final semantics = tester.ensureSemantics();
      final sent = await _pumpTheNotice(
        tester,
        const SalaSessionState(unsentParts: _unsent, swapping: 'ensaio-2'),
      );

      expect(
        tester.widget<TextButton>(_sendNow).onPressed,
        isNull,
        reason:
            'o «enviar agora» ficava aceso enquanto a troca do ensaio subia',
      );
      expect(
        tester
            .getSemantics(byLabel(_enviarAGravacao))
            .flagsCollection
            .isEnabled,
        Tristate.isFalse,
      );
      await tester.tap(_sendNow, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 100));
      expect(sent, isEmpty);
      semantics.dispose();
    },
  );

  testWidgets(
    'with nothing in the air, a tap on «enviar agora» sends its scene',
    (tester) async {
      final sent = await _pumpTheNotice(
        tester,
        const SalaSessionState(unsentParts: _unsent),
      );

      await tester.tap(_sendNow);
      await tester.pump(const Duration(milliseconds: 100));

      expect(sent, [1]);
    },
  );
}
