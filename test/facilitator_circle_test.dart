import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/core/theme/sala_colors.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/bead_styles.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';

Future<void> _pumpCircle(
  WidgetTester tester,
  VoiceState voice, {
  bool peerCue = false,
  bool noteMode = false,
}) =>
    tester.pumpWidget(MaterialApp(
      key: ValueKey('$voice-$peerCue-$noteMode'),
      theme: AppTheme.light,
      home: Scaffold(
        body: Center(
          child: FacilitatorCircle(
            size: 158,
            voice: voice,
            peerCue: peerCue,
            noteMode: noteMode,
            semanticLabel: 'circulo',
            onTap: () {},
          ),
        ),
      ),
    ));

/// The fill of the disc at the centre, which is the only painting in the circle that
/// carries a gradient — the rings around it are borders on nothing.
Gradient? _disc(WidgetTester tester) {
  final painted = tester
      .widgetList<Container>(find.descendant(
        of: find.byType(FacilitatorCircle),
        matching: find.byType(Container),
      ))
      .map((box) => box.decoration)
      .whereType<BoxDecoration>()
      .map((paint) => paint.gradient)
      .whereType<Gradient>()
      .toList();
  return painted.isEmpty ? null : painted.first;
}

void main() {
  testWidgets('a peer cue changes the glyph in the circle, never the circle itself',
      (tester) async {
    await _pumpCircle(tester, VoiceState.invite, peerCue: true);

    expect(_disc(tester), BeadStyles.telha(SalaColors.light),
        reason: 'a sala mandava a equipe conversar entre si e apagava, nesse '
            'mesmo instante, o único alvo que ela aprendeu a tocar — o disco '
            'inteiro virava azul e a telha sumia justo quando ela precisa '
            'achar o círculo de volta');
    expect(find.byIcon(LucideIcons.users), findsOneWidget,
        reason: 'e quem diz que a vez é deles é o glifo, que é a única coisa '
            'que tem de mudar');
  });
}
