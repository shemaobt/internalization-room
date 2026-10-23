import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import '../../domain/facilitator_script.dart';

class ChecagemExternaView extends ConsumerWidget {
  const ChecagemExternaView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(roomLanguageProvider);
    final colors = SalaColors.of(context);
    final titulo = externalCheckLabelFor('title', language);
    final novoOuvinte = externalCheckLabelFor('newListener', language);
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
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Text(
                      externalCheckLabelFor('subIdle', language),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colors.mut,
                        fontSize: 15,
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Semantics(
                    button: true,
                    enabled: false,
                    label: novoOuvinte,
                    child: ExcludeSemantics(
                      child: Opacity(
                        opacity: 0.4,
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
                              novoOuvinte,
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
