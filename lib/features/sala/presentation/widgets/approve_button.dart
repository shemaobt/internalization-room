import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import '../../domain/facilitator_script.dart';

class ApproveButton extends ConsumerWidget {
  final bool live;

  const ApproveButton({super.key, required this.live});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(salaSessionProvider.notifier);
    final colors = SalaColors.of(context);
    final rotulo = retroLabelFor('approve', ref.watch(roomLanguageProvider));
    return Semantics(
      button: true,
      enabled: live,
      label: rotulo,
      child: Opacity(
        opacity: live ? 1 : 0.35,
        child: GestureDetector(
          onTap: live ? notifier.aprovarRascunhoFinal : null,
          child: ExcludeSemantics(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 35, vertical: 13),
              decoration: BoxDecoration(
                color: colors.verdeClaro,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                rotulo,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.paper,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
