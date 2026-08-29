import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import 'bead_styles.dart';
import 'motion.dart';

const ouvirMaternaLabel = 'Ouvir a voz de vocês, na língua materna';
const ouvirRetroLabel = 'Ouvir o contar em português';
const micMaternaLabel = 'Regravar a voz na língua materna — refaz também o contar';
const micRetroLabel = 'Recontar só em português';

/// Where the error lives: the team says it, the room does not guess.
///
/// Column is the voice — wood is the team's own tongue, blue is the telling in Portuguese
/// — and row is the verb: listen on top, speak below. Which voice needs to speak again is
/// the whole question, and it used to be answered by the kind of finding the classifier
/// returned, with the team never asked.
///
/// The path hanging under each microphone is the cost, shown before the gesture rather
/// than after it: the wood column carries two stations, the blue one carries one.
class OndeMoraGrade extends StatelessWidget {
  final VoidCallback onOuvirMaterna;
  final VoidCallback onOuvirRetro;
  final VoidCallback onRegravarMaterna;
  final VoidCallback onRecontar;

  /// Which voice is sounding right now, if any. Listening is free — it decides nothing —
  /// but the other targets go inert while it runs, so a tap meant for the sound cannot
  /// land on a choice.
  final bool tocandoMaterna;
  final bool tocandoRetro;

  const OndeMoraGrade({
    super.key,
    required this.onOuvirMaterna,
    required this.onOuvirRetro,
    required this.onRegravarMaterna,
    required this.onRecontar,
    this.tocandoMaterna = false,
    this.tocandoRetro = false,
  });

  bool get _algoTocando => tocandoMaterna || tocandoRetro;

  @override
  Widget build(BuildContext context) {
    final colors = SalaColors.of(context);
    return FadeUp(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Coluna(
            colors: colors,
            gradiente: BeadStyles.wood,
            ouvirLabel: ouvirMaternaLabel,
            micLabel: micMaternaLabel,
            onOuvir: onOuvirMaterna,
            onFalar: onRegravarMaterna,
            tocando: tocandoMaterna,
            inerte: _algoTocando,
            estacoesPenduradas: 1,
          ),
          const SizedBox(width: 56),
          _Coluna(
            colors: colors,
            gradiente: BeadStyles.azul,
            ouvirLabel: ouvirRetroLabel,
            micLabel: micRetroLabel,
            onOuvir: onOuvirRetro,
            onFalar: onRecontar,
            tocando: tocandoRetro,
            inerte: _algoTocando,
            estacoesPenduradas: 0,
          ),
        ],
      ),
    );
  }
}

class _Coluna extends StatelessWidget {
  final SalaColors colors;
  final Gradient gradiente;
  final String ouvirLabel;
  final String micLabel;
  final VoidCallback onOuvir;
  final VoidCallback onFalar;
  final bool tocando;
  final bool inerte;

  /// How many stations hang under this microphone beyond the one it opens. The wood voice
  /// costs a second one — telling the stretch back over the new recording — and that is
  /// the difference the team is being asked to weigh.
  final int estacoesPenduradas;

  const _Coluna({
    required this.colors,
    required this.gradiente,
    required this.ouvirLabel,
    required this.micLabel,
    required this.onOuvir,
    required this.onFalar,
    required this.tocando,
    required this.inerte,
    required this.estacoesPenduradas,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Player(
          colors: colors,
          gradiente: gradiente,
          label: ouvirLabel,
          onTap: inerte && !tocando ? null : onOuvir,
          tocando: tocando,
        ),
        _Corda(colors: colors, altura: 14),
        _Alvo(
          size: 60,
          gradiente: gradiente,
          label: micLabel,
          onTap: inerte ? null : onFalar,
          child: const Icon(LucideIcons.mic, size: 22, color: ShemaBrand.branco),
        ),
        if (estacoesPenduradas > 0) ...[
          _Corda(colors: colors, altura: 12),
          Opacity(
            opacity: 0.6,
            child: Container(
              width: 26,
              height: 26,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: BeadStyles.azul,
              ),
              child: const Icon(
                LucideIcons.mic,
                size: 12,
                color: ShemaBrand.branco,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Corda extends StatelessWidget {
  final SalaColors colors;
  final double altura;

  const _Corda({required this.colors, required this.altura});

  @override
  Widget build(BuildContext context) => Container(
        width: 2,
        height: altura,
        color: colors.cord,
      );
}

class _Player extends StatelessWidget {
  final SalaColors colors;
  final Gradient gradiente;
  final String label;
  final VoidCallback? onTap;
  final bool tocando;

  const _Player({
    required this.colors,
    required this.gradiente,
    required this.label,
    required this.onTap,
    required this.tocando,
  });

  @override
  Widget build(BuildContext context) {
    return Loop(
      period: const Duration(milliseconds: 1200),
      animate: tocando,
      builder: (context, t) => Transform.scale(
        scale: tocando ? 1 + 0.1 * t : 1,
        child: _Alvo(
          size: 96,
          gradiente: gradiente,
          label: label,
          onTap: onTap,
          halo: tocando ? colors.halo : null,
          child: const Icon(
            LucideIcons.play,
            size: 26,
            color: ShemaBrand.branco,
          ),
        ),
      ),
    );
  }
}

class _Alvo extends StatelessWidget {
  final double size;
  final Gradient gradiente;
  final String label;
  final VoidCallback? onTap;
  final Widget child;
  final Color? halo;

  const _Alvo({
    required this.size,
    required this.gradiente,
    required this.label,
    required this.onTap,
    required this.child,
    this.halo,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedOpacity(
          opacity: onTap == null ? 0.35 : 1,
          duration: const Duration(milliseconds: 300),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: gradiente,
              boxShadow: [
                ...BeadStyles.matte,
                if (halo != null) BoxShadow(color: halo!, spreadRadius: 6),
              ],
            ),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}
