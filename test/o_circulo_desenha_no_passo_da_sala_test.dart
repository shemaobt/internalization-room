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
    'a team being heard draws its rings sixty times a second, not at the panel rate',
    (tester) async {
      await _pumpCircle(tester, VoiceState.listening);

      expect(
        await _redrawsOverASecondAt120Hz(tester),
        inInclusiveRange(59, 61),
        reason:
            'os dois anéis que crescem enquanto a equipe fala '
            '(globals.css:381-382) andavam cada um no seu vsync, a 120 '
            'quadros por segundo',
      );
    },
  );

  testWidgets(
    'a team that stops being heard lets the circle slow back to thirty, not stay at sixty',
    (tester) async {
      await _pumpCircle(tester, VoiceState.listening);
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
    'a thinking circle draws its breath thirty times a second, not at the panel rate',
    (tester) async {
      await _pumpCircle(tester, VoiceState.thinking);

      expect(
        await _redrawsOverASecondAt120Hz(tester),
        inInclusiveRange(29, 31),
        reason:
            'sem arcos, o pensar não tem nada que precise do relógio rápido: '
            'a respiração e o brilho bastam no mesmo passo do convite',
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
        closeTo(1, 1e-9),
        reason: 'uma volta e meia depois, o chamado está no pico',
      );

      await breathing(const Duration(milliseconds: 4600));
      expect(
        breath.last,
        closeTo(1, 1e-9),
        reason:
            'o disco saltava no instante em que o chamado virava convite: a '
            'respiração recomeçava a contar do tempo todo, do mesmo pico, '
            'no ritmo novo',
      );

      await tester.pump(const Duration(milliseconds: 100));
      expect(
        breath.last,
        lessThan(1),
        reason:
            'e o que estava no pico passava a descer — a troca de ritmo não '
            'reabre um fôlego novo do zero',
      );
    },
  );

  testWidgets(
    'a ring whose pace changes mid-lap answers to the new pace, not the one it woke up with',
    (tester) async {
      double? drawn;
      Future<void> ring(int period, int wait) => tester.pumpWidget(
        Ripple(
          period: Duration(milliseconds: period),
          delay: Duration(milliseconds: wait),
          curve: Curves.linear,
          builder: (context, t) {
            drawn = t;
            return const SizedBox.shrink();
          },
        ),
      );

      await ring(3200, 0);
      await tester.pump(const Duration(milliseconds: 1000));
      await ring(3400, 500);
      await tester.pump(const Duration(milliseconds: 3900));

      expect(
        drawn,
        closeTo(0, 1e-9),
        reason:
            'o anel seguia nos 3200 ms de quando nasceu (0,06) ou contava do '
            'seu primeiro quadro (0,29) — 3,9 s depois da troca ele devia ter '
            'esperado os 500 ms e voltado ao começo do laço novo de 3400 ms',
      );
    },
  );

  testWidgets(
    'a ring given a new wait mid-lap waits it from the rebuild, not from its first frame',
    (tester) async {
      double? drawn;
      Future<void> ring(int wait) => tester.pumpWidget(
        Ripple(
          period: const Duration(milliseconds: 3200),
          delay: Duration(milliseconds: wait),
          curve: Curves.linear,
          builder: (context, t) {
            drawn = t;
            return const SizedBox.shrink();
          },
        ),
      );

      await ring(0);
      await tester.pump(const Duration(milliseconds: 1000));
      await ring(500);
      await tester.pump(const Duration(milliseconds: 3700));

      expect(
        drawn,
        closeTo(0, 1e-9),
        reason:
            'com o mesmo laço a espera nova não reabria o anel: ele contava '
            'do primeiro quadro e estava a 0,31 em vez de no começo',
      );
    },
  );

  testWidgets(
    'a rebuild that keeps her pace does not reopen the ring from the start',
    (tester) async {
      await _pumpCircle(tester, VoiceState.listening);
      await tester.pump(const Duration(milliseconds: 850));
      await _pumpCircle(tester, VoiceState.listening);
      await tester.pump(const Duration(milliseconds: 2150));

      final scales = tester
          .widgetList<Transform>(
            find.descendant(
              of: find.byType(Ripple),
              matching: find.byType(Transform),
            ),
          )
          .map((moved) => moved.transform.storage[0]);

      expect(
        scales,
        contains(closeTo(.62, 1e-9)),
        reason:
            'nada em period ou phase mudou entre as duas reconstruções — só '
            'o laço de 3 s inteiro dela, medido desde o primeiro quadro, '
            'devia fechar de volta ao .62 em que o anel nasce '
            '(globals.css:202); reabrir a cada reconstrução deixaria o anel '
            'a 0,72 do laço',
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
