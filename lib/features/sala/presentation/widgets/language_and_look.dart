import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/look_ledger.dart';
import '../../data/session_notifier.dart';
import '../../domain/facilitator_script.dart';
import '../../domain/session_state.dart';

class LanguageAndLook extends ConsumerWidget {
  const LanguageAndLook({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(salaSessionProvider.select((it) => it.stage)) !=
        SalaStage.escolha) {
      return const SizedBox.shrink();
    }
    final language = ref.watch(roomLanguageProvider);
    final light = Theme.of(context).brightness == Brightness.light;
    final look = ref.read(lookProvider.notifier);
    final room = ref.read(salaSessionProvider.notifier);
    final screen = MediaQuery.sizeOf(context);

    return Positioned(
      right: screen.width * 0.06,
      top: max(screen.height * 0.05, MediaQuery.viewPaddingOf(context).top),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _Pill(
            children: [
              _Choice(
                label: escolhaLabelFor('light', language),
                selected: light,
                onTap: () => look.choose(ThemeMode.light),
                child: const Icon(LucideIcons.sun, size: 18),
              ),
              _Choice(
                label: escolhaLabelFor('dark', language),
                selected: !light,
                onTap: () => look.choose(ThemeMode.dark),
                child: const Icon(LucideIcons.moon, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _Pill(
            children: [
              for (final code in languages)
                _Choice(
                  label: code.toUpperCase(),
                  selected: code == language,
                  onTap: () => room.chooseTheLanguage(code),
                  child: Text(
                    code.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final List<Widget> children;

  const _Pill({required this.children});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: SalaColors.of(context).areia, width: 1.4),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

class _Choice extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colors = SalaColors.of(context);
    final ink = selected ? colors.branco : colors.verdeClaro;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ExcludeSemantics(
          child: Container(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 44),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? colors.azul : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: IconTheme.merge(
              data: IconThemeData(color: ink),
              child: DefaultTextStyle.merge(
                style: TextStyle(color: ink),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
