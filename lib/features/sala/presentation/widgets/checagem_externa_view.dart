import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import '../../domain/facilitator_script.dart';
import '../../domain/session_state.dart';
import 'facilitator_circle.dart';
import 'motion.dart';

class ChecagemExternaView extends ConsumerWidget {
  const ChecagemExternaView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(roomLanguageProvider);
    final session = ref.watch(salaSessionProvider);
    final colors = SalaColors.of(context);
    final titulo = externalCheckLabelFor('title', language);
    return SafeArea(
      bottom: false,
      child: Stack(
        children: [
          Positioned(
            left: 14,
            top: 14,
            child: Semantics(
              button: true,
              label: externalCheckLabelFor('back', language),
              child: GestureDetector(
                onTap: ref
                    .read(salaSessionProvider.notifier)
                    .leaveTheExternalCheck,
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 46,
                  height: 46,
                  child: Opacity(
                    opacity: 0.5,
                    child: Icon(
                      LucideIcons.chevronLeft,
                      size: 24,
                      color: colors.mut,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    header: true,
                    label: titulo,
                    child: ExcludeSemantics(
                      child: Text(
                        titulo,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colors.ink,
                          fontSize: 26,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  ..._theListener(context, ref, session, language),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _theListener(
    BuildContext context,
    WidgetRef ref,
    SalaSessionState session,
    String language,
  ) {
    final notifier = ref.read(salaSessionProvider.notifier);
    final colors = SalaColors.of(context);
    final shown = session.externalCheck;
    final sub = TextStyle(color: colors.mut, fontSize: 15, height: 1.35);
    final failed = switch (shown.line) {
      ListenerLine.openFailed => externalCheckLabelFor('openFail', language),
      ListenerLine.clipFailed => externalCheckLabelFor('clipFail', language),
      null => null,
    };
    Widget line(String text) => ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 600),
      child: Text(text, textAlign: TextAlign.center, style: sub),
    );
    if (shown.step == ListenerStep.idle) {
      return [
        const SizedBox(height: 12),
        line(externalCheckLabelFor('subIdle', language)),
        const SizedBox(height: 28),
        _Control(
          label: externalCheckLabelFor('newListener', language),
          enabled: !shown.sending,
          onTap: notifier.newListener,
        ),
        if (failed != null) ...[const SizedBox(height: 16), line(failed)],
      ];
    }
    final retell = shown.step == ListenerStep.retell;
    final open = session.listenerCircleOpen;
    final recording = session.listenerRecording;
    final since = shown.recordingSince;
    return [
      const SizedBox(height: 6),
      line(externalCheckLabelFor('listener', language, n: shown.listener)),
      const SizedBox(height: 12),
      line(
        externalCheckLabelFor(retell ? 'subRetell' : 'subPlaying', language),
      ),
      const SizedBox(height: 28),
      FacilitatorCircle(
        size: facilitatorCircleSize,
        halt: session.halt,
        voice: session.voice,
        answersATouch: open,
        semanticLabel: externalCheckLabelFor('retellAria', language),
        onTap: open ? notifier.listenerTap : null,
      ),
      const SizedBox(height: 16),
      if (recording && since != null)
        Loop(
          period: const Duration(seconds: 1),
          reducible: false,
          builder: (context, _) => line(
            '${externalCheckLabelFor('recording', language)} · '
            '${_elapsed(clock.now().difference(since))}',
          ),
        )
      else if (open)
        line(externalCheckLabelFor('recordHint', language)),
      if (retell || shown.stalled) ...[
        const SizedBox(height: 20),
        _Control(
          label: externalCheckLabelFor('hearAgain', language),
          enabled: session.listenerMayHearItAgain,
          onTap: notifier.hearTheWholePassageAgain,
        ),
      ],
      if (failed != null) ...[const SizedBox(height: 16), line(failed)],
    ];
  }
}

String _elapsed(Duration elapsed) =>
    '${elapsed.inMinutes}:${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}';

class _Control extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _Control({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = SalaColors.of(context);
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: enabled ? onTap : null,
          behavior: HitTestBehavior.opaque,
          child: Opacity(
            opacity: enabled ? 1 : 0.4,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: colors.line),
                borderRadius: BorderRadius.circular(28),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 36,
                  vertical: 14,
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: colors.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
