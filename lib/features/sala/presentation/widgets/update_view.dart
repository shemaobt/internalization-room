import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/store_build_gate.dart';
import '../../domain/facilitator_script.dart';
import 'shema_mark.dart';

const _rem = 16.0;

class UpdateView extends ConsumerWidget {
  final String language;

  const UpdateView({super.key, required this.language});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = SalaColors.of(context);
    final screen = MediaQuery.sizeOf(context);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        screen.width * 0.08,
        screen.height * 0.13,
        screen.width * 0.08,
        screen.height * 0.12,
      ),
      child: Center(
        child: Column(
          spacing: 1.6 * _rem,
          children: [
            const ShemaMark(size: 56, opacity: 0.82),
            Text(
              updateLabelFor('line', language),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 1.5 * _rem,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.01 * 1.5 * _rem,
                color: colors.momentoInk,
              ),
            ),
            Semantics(
              button: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () =>
                    ref.read(storeBuildGateProvider.notifier).openTheStore(),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(width: 1.5, color: colors.azul),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 0.6 * _rem,
                      horizontal: 1.05 * _rem,
                    ),
                    child: Text(
                      updateLabelFor('button', language),
                      style: TextStyle(
                        fontSize: 0.95 * _rem,
                        color: colors.momentoInk,
                      ),
                    ),
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
