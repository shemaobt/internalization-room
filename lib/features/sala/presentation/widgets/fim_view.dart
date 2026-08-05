import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../data/session_notifier.dart';

class FimView extends ConsumerWidget {
  const FimView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(salaSessionProvider);
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: constraints.maxHeight * (400 / 812) - 28,
            child: Center(
              child: AnimatedOpacity(
                opacity: session.fimClosed ? 0.85 : 0,
                duration: const Duration(milliseconds: 1200),
                curve: Curves.easeInOut,
                child: SvgPicture.asset(
                  'assets/icon-telha.svg',
                  width: 56,
                  height: 56,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
