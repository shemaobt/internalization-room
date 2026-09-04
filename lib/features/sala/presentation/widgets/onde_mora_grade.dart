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

/// The one thing to do about a stretch that came out short: record it again and tell it
/// again over the new recording, in that order.
///
/// The long way and not the short one. What is missing was most likely left out of the
/// recording itself, not only out of the telling laid over it, so redoing the telling
/// alone would explain an audio that still does not carry the part.
///
/// It names no language. "Recontar só em português" named the bridge — false in a session
/// held in another one — and its "only" existed by contrast with a column that is not
/// here.
const refazerParteLabel = 'Regravar esta parte e contá-la de novo';

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
/// row it is not part of — on the blue one too, where the slot is always empty.
///
/// That reserved slot sits on the left edge of a column and nowhere else, and counting it
/// as width while it stands empty is what tilted the whole block: the two players, which
/// are the only thing the eye reads as the question, sat right of the middle of the space
/// the block was centred in. So the block mirrors the same reserve on its right edge. The
/// mirror holds nothing and never will; it is there so the reserved emptiness is spent
/// evenly on both sides and the question meets the team on the axis of the screen, which
/// is what lets it read as a question between two voices of equal weight rather than one
/// already leaning towards an answer.
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

  final bool offline;

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
    this.offline = false,
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
            micInerte: offline,
            estacoesPenduradas: 0,
          ),
          const SizedBox(width: _tesouraSlot + _tesouraFolga),
        ],
      ),
    );
  }
}

/// What the room offers when the stretch is short rather than wrong.
///
/// The two players stay: hearing is free, it settles nothing, and without hearing their
/// own voice back the team has no way to know what was left out. What goes is the
/// *choice* between the two — the pair of microphones that asked which voice to correct —
/// and in its place stands the single act that answers an absence: telling that stretch
/// again, whole, with what was missing in it.
///
/// Its own composition rather than the grid with a column hidden, so that "the question
/// is not put here" is a thing the screen cannot drift back out of.
class RefazerAParte extends StatelessWidget {
  final VoidCallback onOuvirMaterna;
  final VoidCallback onOuvirRetro;
  final VoidCallback onRefazerAParte;

  final bool tocandoMaterna;
  final bool tocandoRetro;

  /// Whether this tablet holds the telling at all, as on the grid: a session picked back
  /// up carries the room's stretches and none of its files.
  final bool podeOuvirRetro;

  const RefazerAParte({
    super.key,
    required this.onOuvirMaterna,
    required this.onOuvirRetro,
    required this.onRefazerAParte,
    this.tocandoMaterna = false,
    this.tocandoRetro = false,
    this.podeOuvirRetro = true,
  });

  bool get _algoTocando => tocandoMaterna || tocandoRetro;

  @override
  Widget build(BuildContext context) {
    final colors = SalaColors.of(context);
    return FadeUp(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Player(
                colors: colors,
                gradiente: BeadStyles.wood,
                label: ouvirMaternaLabel,
                onTap: _algoTocando && !tocandoMaterna ? null : onOuvirMaterna,
                tocando: tocandoMaterna,
              ),
              const SizedBox(width: 56),
              _Player(
                colors: colors,
                gradiente: BeadStyles.azul,
                label: ouvirRetroLabel,
                onTap: !podeOuvirRetro || (_algoTocando && !tocandoRetro)
                    ? null
                    : onOuvirRetro,
                tocando: tocandoRetro,
              ),
            ],
          ),
          _Corda(colors: colors, altura: 14),
          _Alvo(
            size: 60,
            gradiente: BeadStyles.azul,
            label: refazerParteLabel,
            onTap: _algoTocando ? null : onRefazerAParte,
            child: const Icon(LucideIcons.mic, size: 22, color: ShemaBrand.branco),
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

  /// Whether this column's own microphone is off, on top of [inerte]. Offline is the one
  /// caller of this: it still lets the team hear what is there, but nothing they say can
  /// be sent, so the mic that would open a recording nobody can receive stays dark
  /// instead of swallowing the tap in silence.
  final bool micInerte;

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
    this.micInerte = false,
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
            onTap: inerte || micInerte ? null : onFalar,
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
          child: Icon(
            tocando ? LucideIcons.pause : LucideIcons.play,
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
