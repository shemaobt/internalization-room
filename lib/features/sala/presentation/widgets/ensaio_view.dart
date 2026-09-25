import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import '../../domain/facilitator_script.dart';
import '../../domain/session_state.dart';
import 'bead_row.dart';
import 'bead_styles.dart';
import 'facilitator_circle.dart';
import 'motion.dart';

class EnsaioView extends ConsumerWidget {
  const EnsaioView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(salaSessionProvider);
    final notifier = ref.read(salaSessionProvider.notifier);
    final language = ref.watch(roomLanguageProvider);
    final pending = session.ensaio == EnsaioStatus.recorded;

    return Column(
      children: [
        const Spacer(flex: 86),
        SizedBox(
          height: 40,
          child: BeadRow(entries: _beads(session, language), onTap: (_) {}),
        ),
        const Spacer(flex: 270),
        FacilitatorCircle(
          size: 160,
          voice: _voice(session),
          tongue: Tongue.motherTongue,
          semanticLabel: _circleLabel(session, language),
          onTap: notifier.ensaioTap,
          onLongPress: session.canResolveWithPerson
              ? notifier.resolveWithPerson
              : null,
        ),
        const Spacer(flex: 116),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            RoundActionButton(
              size: 60,
              mood: session.canPlayTheRehearsal
                  ? ButtonMood.lit
                  : ButtonMood.dimmed,
              gradient: BeadStyles.wood,
              semanticLabel: rehearsalLabelFor(
                session.playPing ? 'pause' : 'play',
                language,
              ),
              onTap: notifier.playTheRehearsal,
              child: Icon(
                session.playPing ? LucideIcons.pause : LucideIcons.play,
                size: 24,
                color: ShemaBrand.branco,
              ),
            ),
            const SizedBox(width: 24),
            RoundActionButton(
              size: 60,
              mood: pending ? ButtonMood.lit : ButtonMood.dimmed,
              gradient: BeadStyles.verde,
              semanticLabel: rehearsalLabelFor('check', language),
              onTap: notifier.takeKeep,
              child: const Icon(
                LucideIcons.check,
                size: 24,
                color: ShemaBrand.branco,
              ),
            ),
          ],
        ),
        const Spacer(flex: 66),
        FadeUp(
          child: RoundActionButton(
            size: 78,
            mood: session.ensaioDone ? ButtonMood.beckoning : ButtonMood.dimmed,
            gradient: BeadStyles.wood,
            shadows: RoundActionButton.dropShadow,
            halo: ShemaBrand.wood,
            semanticLabel: rehearsalLabelFor('advance', language),
            onTap: notifier.startRetro,
          ),
        ),
        const Spacer(flex: 304),
      ],
    );
  }

  VoiceState _voice(SalaSessionState session) {
    if (session.ensaio == EnsaioStatus.recording && !session.micTaken) {
      return VoiceState.listening;
    }
    if (session.playPing) return VoiceState.speaking;
    return VoiceState.invite;
  }

  String _circleLabel(SalaSessionState session, String language) {
    final again = session.parteARegravar;
    if (session.ensaio == EnsaioStatus.recording) {
      return rehearsalLabelFor('recording', language);
    }
    if (session.ensaio == EnsaioStatus.recorded) {
      return rehearsalLabelFor('pending', language);
    }
    if (again != null) {
      return rehearsalLabelFor('partAgain', language, part: again + 1);
    }
    if (session.partes.isNotEmpty) {
      return rehearsalLabelFor('nextPart', language);
    }
    return rehearsalLabelFor('firstPart', language);
  }

  List<BeadRowEntry> _beads(SalaSessionState session, String language) {
    final open = session.ensaio != EnsaioStatus.idle;
    final partes = session.partes;
    final again = session.parteARegravar;
    final replacing = again != null && again < partes.length;
    return [
      for (var index = 0; index < partes.length; index++)
        BeadRowEntry(
          fill: open && index == again ? BeadFill.translucent : BeadFill.solid,
          current: index == again,
          semanticLabel: rehearsalLabelFor('part', language, part: index + 1),
        ),
      if (open && !replacing)
        BeadRowEntry(
          fill: BeadFill.translucent,
          current: true,
          semanticLabel: rehearsalLabelFor(
            'part',
            language,
            part: partes.length + 1,
          ),
        ),
    ];
  }
}
