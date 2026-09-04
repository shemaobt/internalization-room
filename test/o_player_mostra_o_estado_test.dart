import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/features/sala/presentation/widgets/onde_mora_grade.dart';
import 'package:internalization_room/features/sala/presentation/widgets/motion.dart';

const ouvirMaterna = 'Ouvir a voz de vocês, na língua materna';
const ouvirRetro = 'Ouvir o contar em português';

Finder byLabel(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);

IconData iconeDoPlayer(WidgetTester tester, String label) {
  final icon = tester.widget<Icon>(
    find.descendant(of: byLabel(label), matching: find.byType(Icon)),
  );
  return icon.icon!;
}

bool animandoOPlayer(WidgetTester tester, String label) {
  final loop = tester.widget<Loop>(
    find.ancestor(of: byLabel(label), matching: find.byType(Loop)),
  );
  return loop.animate;
}

Future<void> pumpGradeSozinha(
  WidgetTester tester, {
  bool tocandoMaterna = false,
  bool tocandoRetro = false,
}) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: Center(
        child: OndeMoraGrade(
          onOuvirMaterna: () {},
          onOuvirRetro: () {},
          onRegravarMaterna: () {},
          onRecontar: () {},
          tocandoMaterna: tocandoMaterna,
          tocandoRetro: tocandoRetro,
        ),
      ),
    ),
  ),
);

void main() {
  group('o ícone segue o estado', () {
    testWidgets('tocando mostra pausa, parado mostra tocar', (tester) async {
      await pumpGradeSozinha(tester, tocandoMaterna: true, tocandoRetro: false);

      expect(
        iconeDoPlayer(tester, ouvirMaterna),
        LucideIcons.pause,
        reason: 'a voz que está tocando mostra o ícone de pausar',
      );
      expect(
        iconeDoPlayer(tester, ouvirRetro),
        LucideIcons.play,
        reason: 'a voz parada continua com o ícone de tocar',
      );

      await pumpGradeSozinha(
        tester,
        tocandoMaterna: false,
        tocandoRetro: false,
      );

      expect(
        iconeDoPlayer(tester, ouvirMaterna),
        LucideIcons.play,
        reason: 'sem nada tocando (parado ou pausado), o ícone é tocar',
      );
      expect(iconeDoPlayer(tester, ouvirRetro), LucideIcons.play);
    });

    testWidgets('a ponte tocando mostra pausa nela e tocar na materna', (
      tester,
    ) async {
      await pumpGradeSozinha(tester, tocandoMaterna: false, tocandoRetro: true);

      expect(iconeDoPlayer(tester, ouvirRetro), LucideIcons.pause);
      expect(iconeDoPlayer(tester, ouvirMaterna), LucideIcons.play);
    });
  });

  group('a pulsação acompanha', () {
    testWidgets('tocando anima, pausado para, tocando de novo anima', (
      tester,
    ) async {
      await pumpGradeSozinha(tester, tocandoMaterna: true);
      expect(animandoOPlayer(tester, ouvirMaterna), isTrue);

      await pumpGradeSozinha(tester, tocandoMaterna: false);
      expect(
        animandoOPlayer(tester, ouvirMaterna),
        isFalse,
        reason: 'pausado é, para o player, o mesmo repouso que parado',
      );

      await pumpGradeSozinha(tester, tocandoMaterna: true);
      expect(
        animandoOPlayer(tester, ouvirMaterna),
        isTrue,
        reason: 'a terceira alternância — a que o bug escondia — também anima',
      );
    });
  });
}
