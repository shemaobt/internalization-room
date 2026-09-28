import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import '../../domain/facilitator_script.dart';
import '../../domain/kept_take.dart';
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
          child: BeadRow(
            entries: _beads(session, language),
            onTap: notifier.tocarAParte,
          ),
        ),
        const Spacer(flex: 270),
        FacilitatorCircle(
          size: facilitatorCircleSize,
          voice: _voice(session),
          tongue: Tongue.motherTongue,
          warning: session.warning ? warningNoticeLabelFor(language) : null,
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
    if (session.ensaio == EnsaioStatus.recording) {
      return rehearsalLabelFor('recording', language);
    }
    if (session.ensaio == EnsaioStatus.recorded) {
      return rehearsalLabelFor('pending', language);
    }
    if (session.parteARegravar != null) {
      return rehearsalLabelFor('pending', language);
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
    final tocando = session.parteDoEnsaioTocando;
    final replacing = again != null && again < partes.length;
    return [
      for (var index = 0; index < partes.length; index++)
        _beadEntry(
          session,
          language,
          index: index,
          fill: index != again
              ? BeadFill.solid
              : open
              ? BeadFill.translucent
              : BeadFill.drained,
          current: index == (tocando ?? again),
          dimmed: session.beadIsDimmed(index),
          sounding: tocando == index && session.playPing,
        ),
      if (open && !replacing)
        BeadRowEntry(
          fill: BeadFill.translucent,
          current: tocando == null || tocando == partes.length,
          semanticLabel: rehearsalLabelFor(
            'part',
            language,
            part: partes.length + 1,
          ),
        ),
    ];
  }

  BeadRowEntry _beadEntry(
    SalaSessionState session,
    String language, {
    required int index,
    required BeadFill fill,
    required bool current,
    required bool dimmed,
    required bool sounding,
  }) {
    final delivered = !session.unsentTakeScopes.contains(
      KeptScope.parte(index + 1),
    );
    return BeadRowEntry(
      fill: fill,
      current: current,
      dimmed: dimmed,
      delivered: delivered,
      semanticLabel: _beadLabel(
        language,
        part: index + 1,
        sounding: sounding,
        delivered: delivered,
      ),
    );
  }

  String _beadLabel(
    String language, {
    required int part,
    required bool sounding,
    required bool delivered,
  }) {
    final key = switch ((sounding, delivered)) {
      (true, true) => 'partPlaying',
      (true, false) => 'partPlayingNotDelivered',
      (false, true) => 'part',
      (false, false) => 'partNotDelivered',
    };
    return rehearsalLabelFor(key, language, part: part);
  }
}
