import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import 'bead_styles.dart';
import 'motion.dart';

const ouvirMaternaLabel = 'Ouvir a voz de vocês, na língua materna';
const ouvirRetroLabel = 'Ouvir o contar em português';
const micMaternaLabel = 'Regravar a voz na língua materna — refaz também o contar';
const micRetroLabel = 'Recontar só em português';
const cortarTrechoLabel = 'Cortar este trecho em dois, aqui';

/// Where the error lives: the team says it, the room does not guess.
///
/// Column is the voice — wood is the team's own tongue, blue is the telling in Portuguese
/// — and row is the verb: listen on top, speak below. Which voice needs to speak again is
/// the whole question, and it used to be answered by the kind of finding the classifier
/// returned, with the team never asked.
///
/// The path hanging under each microphone is the cost, shown before the gesture rather
/// than after it: the wood column carries two stations, the blue one carries one. What
/// hangs under a player hangs under *that* player: the scissors' slot widens the row the
/// player is in, so everything below it carries the same slot rather than centring on a
/// row it is not part of, which pulled the cord and the microphone 27px off their own
/// column — on the blue one too, where the slot is always empty.
///
/// The scissors sits beside the wood player and only while that voice is sounding, which
/// is what keeps the question at two answers. Listening decides nothing and puts both
/// microphones out — so a target that exists only while a voice plays never shares the
/// screen with the two exits, and the team is never looking at three. It is not on the
/// cord below the player: that vertical means the cost of a path, and a cut is not a step
/// towards choosing one. Its slot is held open whether or not it is filled, so nothing
/// moves under a finger when the sound starts.
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

  /// Whether this tablet holds the telling at all. A session picked back up carries the
  /// room's stretches and none of its files, and a lit player that answers with silence
  /// has no way to explain itself in a room with no written word.
  final bool podeOuvirRetro;

  /// Cut the stretch in two where the mother tongue is sounding, or null where there is
  /// nothing to cut.
  final VoidCallback? onCortar;

  const OndeMoraGrade({
    super.key,
    required this.onOuvirMaterna,
    required this.onOuvirRetro,
    required this.onRegravarMaterna,
    required this.onRecontar,
    this.tocandoMaterna = false,
    this.tocandoRetro = false,
    this.podeOuvirRetro = true,
    this.onCortar,
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
            onCortar: onCortar,
          ),
          const SizedBox(width: 56),
          _Coluna(
            colors: colors,
            gradiente: BeadStyles.azul,
            ouvirLabel: ouvirRetroLabel,
            micLabel: micRetroLabel,
            onOuvir: podeOuvirRetro ? onOuvirRetro : null,
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
  /// Null when there is nothing to hear on this voice.
  final VoidCallback? onOuvir;
  final VoidCallback onFalar;
  final bool tocando;
  final bool inerte;

  /// Cut what is sounding, on the voice that has a slice to cut. Null on the voice that
  /// does not, and null while nothing is in the air.
  final VoidCallback? onCortar;

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
    this.onCortar,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: _tesouraSlot,
              child: onCortar == null
                  ? null
                  : _Alvo(
                      size: _tesouraSlot,
                      gradiente: gradiente,
                      label: cortarTrechoLabel,
                      onTap: onCortar,
                      child: const Icon(
                        LucideIcons.scissors,
                        size: 18,
                        color: ShemaBrand.branco,
                      ),
                    ),
            ),
            const SizedBox(width: _tesouraFolga),
            _Player(
              colors: colors,
              gradiente: gradiente,
              label: ouvirLabel,
              onTap: inerte && !tocando ? null : onOuvir,
              tocando: tocando,
            ),
          ],
        ),
        _SobOTocador(child: _Corda(colors: colors, altura: 14)),
        _SobOTocador(
          child: _Alvo(
            size: 60,
            gradiente: gradiente,
            label: micLabel,
            onTap: inerte ? null : onFalar,
            child:
                const Icon(LucideIcons.mic, size: 22, color: ShemaBrand.branco),
          ),
        ),
        if (estacoesPenduradas > 0) ...[
          _SobOTocador(child: _Corda(colors: colors, altura: 12)),
          _SobOTocador(
            child: Opacity(
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
          ),
        ],
      ],
    );
  }
}

const _tesouraSlot = 44.0;
const _tesouraFolga = 10.0;

/// Carries the same leading slot the player's row carries, so what hangs below a player
/// stays under it instead of centring on a wider row it is not part of.
class _SobOTocador extends StatelessWidget {
  final Widget child;

  const _SobOTocador({required this.child});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: _tesouraSlot + _tesouraFolga),
          child,
        ],
      );
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
