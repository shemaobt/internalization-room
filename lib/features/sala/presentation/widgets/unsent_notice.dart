import 'package:flutter/material.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../domain/facilitator_script.dart';
import '../../domain/kept_take.dart';
import '../../domain/session_state.dart';

class UnsentNotice extends StatelessWidget {
  final SalaSessionState session;
  final String language;
  final void Function(int scene) onSend;

  const UnsentNotice({
    super.key,
    required this.session,
    required this.language,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final unsent = [
      for (final MapEntry(key: scene, value: part)
          in session.unsentParts.entries)
        if (sendNowLabelFor(
              part,
              session.scopeOfRow(scene) == KeptScope.whole
                  ? recordingHomeLabelFor('wholePassage', language)
                  : recordingHomeLabelFor('scene', language, n: scene),
              language,
            )
            case final label?)
          (scene, label),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    if (unsent.isEmpty) return const SizedBox.shrink();
    final colors = SalaColors.of(context);
    final rests = session.sendNowRests;
    String words(String key) => recordingHomeLabelFor(key, language);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Column(
          children: [
            Semantics(
              liveRegion: true,
              child: Text(
                words('pending'),
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.telha, fontSize: 15),
              ),
            ),
            for (final (scene, label) in unsent)
              Semantics(
                button: true,
                enabled: !rests,
                label: words('sendAria'),
                onTap: rests ? null : () => onSend(scene),
                excludeSemantics: true,
                child: Opacity(
                  opacity: rests ? 0.5 : 1,
                  child: TextButton(
                    onPressed: rests ? null : () => onSend(scene),
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.telha, fontSize: 15),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
