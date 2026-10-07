import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/session_notifier.dart';
import '../../domain/facilitator_script.dart';
import 'facilitator_circle.dart';

class PanoramaView extends ConsumerWidget {
  const PanoramaView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(salaSessionProvider);
    final notifier = ref.read(salaSessionProvider.notifier);
    final language = ref.watch(roomLanguageProvider);

    return Center(
      child: FacilitatorCircle(
        size: facilitatorCircleSize,
        halt: session.halt,
        voice: session.voice,
        reach: session.reach,
        semanticLabel: session.needsPerson
            ? circleLabelFor('needsPerson', language)
            : panoramaCircleLabelFor(language),
        onTap: notifier.panoramaTap,
        onLongPress: session.canResolveWithPerson
            ? notifier.resolveWithPerson
            : null,
      ),
    );
  }
}
