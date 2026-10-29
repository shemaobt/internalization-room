import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import '../../domain/facilitator_script.dart';
import '../../domain/session_state.dart';

class OuvirTudoView extends ConsumerWidget {
  const OuvirTudoView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final acabou = ref.watch(
      salaSessionProvider.select((s) => s.ouvirTudo == OuvirTudo.acabou),
    );
    final language = ref.watch(roomLanguageProvider);
    final colors = SalaColors.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: ref.read(salaSessionProvider.notifier).sairDoOuvirTudo,
      child: SizedBox.expand(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                recordingHomeLabelFor('listenAllTitle', language),
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.ink, fontSize: 26),
              ),
              if (acabou) ...[
                const SizedBox(height: 24),
                Text(
                  retroLabelFor('endOfTheRecording', language),
                  style: TextStyle(color: colors.mut, fontSize: 18),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
