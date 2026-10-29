import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import '../../domain/facilitator_script.dart';
import '../../domain/session_state.dart';

class ExternalCheckButton extends ConsumerWidget {
  const ExternalCheckButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(salaSessionProvider);
    final notifier = ref.read(salaSessionProvider.notifier);
    final language = ref.watch(roomLanguageProvider);
    final colors = SalaColors.of(context);
    final abre =
        !session.microphoneOpen &&
        session.voice != VoiceState.speaking &&
        session.voice != VoiceState.thinking;
    final rotulo = retroLabelFor('externalCheck', language);
    return Semantics(
      button: true,
      enabled: abre,
      label: rotulo,
      onTap: abre ? notifier.abrirAChecagemExterna : null,
      child: Opacity(
        opacity: abre ? 1 : 0.4,
        child: ExcludeSemantics(
          child: GestureDetector(
            onTap: abre ? notifier.abrirAChecagemExterna : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: colors.mut),
              ),
              child: Text(
                rotulo,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.ink, fontSize: 15),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
