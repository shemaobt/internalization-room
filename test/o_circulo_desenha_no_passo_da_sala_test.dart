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
    'a thinking circle turns its arcs sixty times a second, and hands the clock back at thirty',
    (tester) async {
      await _pumpCircle(tester, VoiceState.thinking);

      expect(
        await _redrawsOverASecondAt120Hz(tester),
        inInclusiveRange(59, 61),
        reason:
            'a trinta quadros o arco de 1,6 s da volta pulava uns 15 px por '
            'quadro na borda de um círculo de 196 px — um giro que tropeça '
            'lê como um aplicativo engasgado, que é o contrário do que ele diz',
      );

      await _pumpCircle(tester, VoiceState.invite);
      expect(
        await _redrawsOverASecondAt120Hz(tester),
        inInclusiveRange(29, 31),
        reason:
            'e quando o pensar acaba, os arcos levam os sessenta com eles e o '
            'convite volta a respirar a trinta',
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
    'a turn goes round at one speed and starts over, never easing into its ends',
    (tester) async {
      final turn = <double>[];
      await tester.pumpWidget(
        Spin(
          period: const Duration(milliseconds: 1600),
          builder: (context, t) {
            turn.add(t);
            return const SizedBox.shrink();
          },
        ),
      );

      await tester.pump(const Duration(milliseconds: 400));
      expect(
        turn.last,
        closeTo(0.25, 1e-9),
        reason:
            'o arco dela gira linear: um quarto do tempo é um quarto da volta, '
            'não o arranque de uma curva que desacelera no fim',
      );

      await tester.pump(const Duration(milliseconds: 800));
      expect(turn.last, closeTo(0.75, 1e-9));

      await tester.pump(const Duration(milliseconds: 400));
      expect(
        turn.last,
        closeTo(0, 1e-9),
        reason:
            'uma volta inteira depois o arco está de novo no começo, seguindo '
            'no mesmo sentido — não voltando pelo caminho de ida como um fôlego',
      );
    },
  );

  testWidgets(
    'a tablet that asks for less motion gets a turn that stays where it began',
    (tester) async {
      final turn = <double>[];
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Spin(
            period: const Duration(milliseconds: 1600),
            builder: (context, t) {
              turn.add(t);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        turn.toSet(),
        {0.0},
        reason:
            'com o movimento reduzido os arcos dela ficam parados: girar é '
            'exatamente o movimento que essa preferência pede para tirar',
      );
    },
  );

  testWidgets(
    'a ring that crosses from listening into speaking answers to her new pace, not the one it woke up with',
    (tester) async {
      await _pumpCircle(tester, VoiceState.listening);
      await _pumpCircle(tester, VoiceState.speaking);
      await tester.pump(const Duration(milliseconds: 1190));

      final secondRing = tester
          .widgetList<Ripple>(
            find.descendant(
              of: find.byType(FacilitatorCircle),
              matching: find.byType(Ripple),
            ),
          )
          .firstWhere((ring) => ring.phase == 0.65);

      final scale = tester
          .widget<Transform>(
            find.descendant(
              of: find.byWidget(secondRing),
              matching: find.byType(Transform),
            ),
          )
          .transform
          .getMaxScaleOnAxis();

      expect(
        scale,
        closeTo(1.0, 1e-9),
        reason:
            'o anel ainda estava na fase 0,5 dos 3200 ms de quando ouvia — '
            '1190 ms depois da troca ele devia ter voltado ao começo do '
            'laço novo (3400 ms, fase 0,65), não seguir a 0,87 do laço velho',
      );
    },
  );

  testWidgets(
    'a rebuild that keeps her pace does not reopen the ring from the start',
    (tester) async {
      await _pumpCircle(tester, VoiceState.speaking);
      await tester.pump(const Duration(milliseconds: 850));
      await _pumpCircle(tester, VoiceState.speaking);
      await tester.pump(const Duration(milliseconds: 2550));

      final firstRing = tester
          .widgetList<Ripple>(
            find.descendant(
              of: find.byType(FacilitatorCircle),
              matching: find.byType(Ripple),
            ),
          )
          .firstWhere((ring) => ring.phase == 0);

      final scale = tester
          .widget<Transform>(
            find.descendant(
              of: find.byWidget(firstRing),
              matching: find.byType(Transform),
            ),
          )
          .transform
          .getMaxScaleOnAxis();

      expect(
        scale,
        closeTo(1.0, 1e-9),
        reason:
            'nada em period ou phase mudou entre as duas reconstruções — só '
            'o laço de 3400 ms inteiro, medido desde o primeiro quadro, '
            'devia fechar de volta ao começo; reabrir a cada reconstrução '
            'deixaria o anel a 0,75 do laço, não de volta a zero',
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
