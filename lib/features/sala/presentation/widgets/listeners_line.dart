import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import '../../domain/facilitator_script.dart';

class ListenersLine extends ConsumerWidget {
  final int listeners;

  const ListenersLine(this.listeners, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (listeners == 0) return const SizedBox.shrink();
    final language = ref.watch(roomLanguageProvider);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        listeners == 1
            ? retroLabelFor('listenersOne', language)
            : retroLabelFor('listeners', language, n: listeners),
        textAlign: TextAlign.center,
        style: TextStyle(color: SalaColors.of(context).mut, fontSize: 15),
      ),
    );
  }
}
