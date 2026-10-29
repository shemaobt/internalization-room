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
      for (final entry in session.unsentParts.entries)
        if (entry.value.failure != SendFailure.gone) entry,
    ]..sort((a, b) => a.key.compareTo(b.key));
    if (unsent.isEmpty) return const SizedBox.shrink();
    final colors = SalaColors.of(context);
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
            for (final MapEntry(key: scene, value: part) in unsent)
              Semantics(
                button: true,
                label: words('sendAria'),
                onTap: () => onSend(scene),
                excludeSemantics: true,
                child: TextButton(
                  onPressed: () => onSend(scene),
                  child: Text(
                    [
                      recordingHomeLabelFor('scene', language, n: scene),
                      if (part.length case final length?)
                        ' · ${minutesAndSecondsOf(length)}',
                      ' — ${words('sendNow')}',
                    ].join(),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.telha, fontSize: 15),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
