import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import '../../domain/ensaio_final_plan.dart';
import '../../domain/facilitator_script.dart';
import '../../domain/session_state.dart';
import 'stage_heading.dart';

/// Her Ensaio Final plan: «pensando…» while the room is read, then her heading and line,
/// and «Gravar cena por cena» at the foot.
class EnsaioFinalPlanView extends ConsumerWidget {
  const EnsaioFinalPlanView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(salaSessionProvider);
    final notifier = ref.read(salaSessionProvider.notifier);
    final language = ref.watch(roomLanguageProvider);
    final colors = SalaColors.of(context);

    if (session.ensaioFinalPlan is! PlanRead) {
      return Center(
        child: Semantics(
          liveRegion: true,
          child: Text(
            ensaioFinalPlanLabelFor('thinking', language),
            style: TextStyle(color: colors.mut, fontSize: 15),
          ),
        ),
      );
    }
    return SafeArea(
      bottom: false,
      child: SizedBox.expand(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              StageHeading(
                stage: SalaStage.ensaio,
                text: ensaioFinalPlanLabelFor('title', language),
                style: TextStyle(
                  color: colors.ink,
                  fontSize: 26,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Text(
                  ensaioFinalPlanLabelFor('sub', language),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.mut,
                    fontSize: 15,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: notifier.recordSceneByScene,
                child: Text(
                  ensaioFinalPlanLabelFor('sceneByScene', language),
                  style: TextStyle(color: colors.telha, fontSize: 15),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
