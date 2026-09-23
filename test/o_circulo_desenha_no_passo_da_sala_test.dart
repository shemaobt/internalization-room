import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/features/sala/presentation/widgets/motion.dart';

const _umQuadroA120Hz = Duration(milliseconds: 8);

Future<void> _pumpCircle(WidgetTester tester, VoiceState voice) =>
    tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: FacilitatorCircle(
              size: 158,
              voice: voice,
              semanticLabel: 'circulo',
              onTap: () {},
            ),
          ),
        ),
      ),
    );

List<Transform> _drawn(WidgetTester tester) => tester
    .widgetList<Transform>(
      find.descendant(
        of: find.byType(FacilitatorCircle),
        matching: find.byType(Transform),
      ),
    )
    .toList();

Future<int> _redrawsOverASecondAt120Hz(WidgetTester tester) async {
  var redraws = 0;
  var before = _drawn(tester);
  for (var frame = 0; frame < 125; frame++) {
    await tester.pump(_umQuadroA120Hz);
    final now = _drawn(tester);
    final redrawn =
        now.length != before.length ||
        [
          for (var i = 0; i < now.length; i++) !identical(now[i], before[i]),
        ].any((changed) => changed);
    if (redrawn) redraws++;
    before = now;
  }
  return redraws;
}

void main() {
  testWidgets(
    'a room waiting on the invite draws its breath thirty times a second, not at the panel rate',
    (tester) async {
      await _pumpCircle(tester, VoiceState.invite);

      expect(
        await _redrawsOverASecondAt120Hz(tester),
        inInclusiveRange(29, 31),
        reason:
            'com a sala parada no convite, o tablet redesenhava o círculo '
            'a cada quadro de uma tela de 120 Hz — e o colar inteiro junto — '
            'para uma respiração que ninguém distingue de trinta quadros',
      );
    },
  );

  testWidgets(
    'a voice speaking draws its rings sixty times a second, not at the panel rate',
    (tester) async {
      await _pumpCircle(tester, VoiceState.speaking);

      expect(
        await _redrawsOverASecondAt120Hz(tester),
        inInclusiveRange(59, 61),
        reason:
            'enquanto o Guia falava, o disco e os dois anéis andavam cada '
            'um no seu vsync, a 120 quadros por segundo',
      );
    },
  );

  testWidgets(
    'a voice that stops speaking lets the circle slow back to thirty, not stay at sixty',
    (tester) async {
      await _pumpCircle(tester, VoiceState.speaking);
      await tester.pump(const Duration(seconds: 1));
      await _pumpCircle(tester, VoiceState.invite);

      expect(
        await _redrawsOverASecondAt120Hz(tester),
        inInclusiveRange(29, 31),
        reason:
            'o convite nunca abre sozinho: chega sempre de dentro de outra '
            'voz, e os anéis que saem precisam levar o passo rápido com eles',
      );
    },
  );

  testWidgets(
    'a beckon that settles into the invite carries on from where its breath was, not from a new one',
    (tester) async {
      final breath = <double>[];
      Future<void> breathing(Duration period) => tester.pumpWidget(
        Loop(
          period: period,
          builder: (context, t) {
            breath.add(t);
            return const SizedBox.shrink();
          },
        ),
      );

      await breathing(const Duration(milliseconds: 1800));
      await tester.pump(const Duration(milliseconds: 2700));
      expect(
        breath.last,
        closeTo(0.5, 1e-9),
        reason:
            'uma volta e meia depois, o chamado está a meio caminho, descendo',
      );

      await breathing(const Duration(milliseconds: 4600));
      expect(
        breath.last,
        closeTo(0.5, 1e-9),
        reason:
            'o disco saltava no instante em que o chamado virava convite: a '
            'respiração recomeçava a contar do tempo todo, no ritmo novo',
      );

      await tester.pump(const Duration(milliseconds: 100));
      expect(
        breath.last,
        lessThan(0.5),
        reason:
            'e o que descia passava a subir — a troca de ritmo virava a '
            'respiração do avesso no meio do fôlego',
      );
    },
  );

  testWidgets(
    'a tablet put away stops drawing the circle, and draws it again when it comes back',
    (tester) async {
      await _pumpCircle(tester, VoiceState.invite);

      for (final away in const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(away);
      }
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(
        tester.element(find.byType(Loop)).dirty,
        isFalse,
        reason:
            'o relógio da respiração continuava batendo com o tablet na '
            'gaveta e pedindo um quadro a cada tique: um Timer não para '
            'sozinho como o vsync para',
      );

      for (final back in const [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(back);
      }
      expect(
        await _redrawsOverASecondAt120Hz(tester),
        inInclusiveRange(29, 31),
        reason: 'e a sala que volta à mão volta a respirar',
      );
    },
  );
}
