import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import '../../domain/facilitator_script.dart';

class SavedScreen extends ConsumerWidget {
  final int version;

  const SavedScreen({super.key, required this.version});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(roomLanguageProvider);
    final colors = SalaColors.of(context);
    final titulo = savedScreenLabelFor('title', language);
    final pronto = savedScreenLabelFor('done', language);
    final live = !ref.watch(salaSessionProvider).needsPerson;
    return SafeArea(
      bottom: false,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: Icon(
                  LucideIcons.check,
                  size: 56,
                  color: ShemaBrand.verdeClaro,
                ),
              ),
              const SizedBox(height: 16),
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
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Text(
                  retroLabelFor('approved', language, n: version),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.mut,
                    fontSize: 15,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              IgnorePointer(
                ignoring: !live,
                child: AnimatedOpacity(
                  opacity: live ? 1 : 0,
                  duration: const Duration(milliseconds: 400),
                  child: Semantics(
                    button: true,
                    label: pronto,
                    onTap: ref.read(salaSessionProvider.notifier).pronto,
                    child: ExcludeSemantics(
                      child: GestureDetector(
                        onTap: ref.read(salaSessionProvider.notifier).pronto,
                        behavior: HitTestBehavior.opaque,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: ShemaBrand.verdeClaro,
                            borderRadius: BorderRadius.circular(28),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 36,
                              vertical: 14,
                            ),
                            child: Text(
                              pronto,
                              style: const TextStyle(
                                color: ShemaBrand.branco,
                                fontSize: 17,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
