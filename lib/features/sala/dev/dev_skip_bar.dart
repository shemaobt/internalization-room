import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../data/session_notifier.dart';
import '../domain/session_state.dart';

class DevSkipBar extends ConsumerWidget {
  final bool debug;

  const DevSkipBar({super.key, this.debug = kDebugMode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!debug) return const SizedBox.shrink();
    if (!Env.devPularFases) return const SizedBox.shrink();
    final session = ref.watch(salaSessionProvider);
    final notifier = ref.read(salaSessionProvider.notifier);
    const emCena = {SalaStage.conversa, SalaStage.ensaio, SalaStage.retro};

    final temSessao = session.sessionId != null;
    final temParte = session.partes.isNotEmpty;

    return Positioned(
      right: 14,
      bottom: 104 + MediaQuery.viewPaddingOf(context).bottom,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        spacing: 6,
        children: [
          const _DevTag(),
          if (emCena.contains(session.stage)) ...[
            _DevButton(
              label: 'ensaio',
              hint: temSessao ? null : 'esperando a sessão nascer',
              onTap: temSessao && session.stage == SalaStage.conversa
                  ? notifier.goEnsaio
                  : null,
            ),
            _DevButton(
              label: 'retro',
              hint: temParte ? null : 'grave 1 parte no ensaio antes',
              onTap: temParte && session.stage != SalaStage.retro
                  ? notifier.startRetro
                  : null,
            ),
            _DevButton(
              label: 'recomeçar',
              hint: null,
              onTap: temSessao || session.stage != SalaStage.conversa
                  ? notifier.devRecomecarPassagem
                  : null,
            ),
          ],
        ],
      ),
    );
  }
}

class _DevTag extends StatelessWidget {
  const _DevTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFB4552D),
        borderRadius: BorderRadius.circular(9),
      ),
      child: const Text(
        'DEV',
        style: TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _DevButton extends StatelessWidget {
  final String label;
  final String? hint;
  final VoidCallback? onTap;

  const _DevButton({required this.label, required this.hint, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final habilitado = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: habilitado ? const Color(0xE6332B24) : const Color(0x80332B24),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: habilitado ? const Color(0xFFB4552D) : const Color(0x40B4552D),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'pular → $label',
              style: TextStyle(
                color: habilitado ? Colors.white : const Color(0x88FFFFFF),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (hint != null)
              Text(
                hint!,
                style: const TextStyle(color: Color(0x88FFFFFF), fontSize: 9),
              ),
          ],
        ),
      ),
    );
  }
}
