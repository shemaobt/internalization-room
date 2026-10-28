import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/playback_repository.dart';
import '../../data/session_notifier.dart';
import '../../domain/channel.dart';
import '../../domain/facilitator_script.dart';
import '../../domain/pausa.dart';
import '../../domain/scene_rehearsal.dart';
import '../../domain/session_state.dart';
import 'bead_styles.dart';
import 'motion.dart';
import 'pause_adjust_row.dart';
import 'scene_strip.dart';

const _rem = 16.0;

/// The translate step, in her order: the instruction, the play control and the hint, the
/// strip, her adjust row under a pending pausa, «traduzir o ensaio da cena» until the
/// team listens, the circle, her message under it and «manter a tradução de antes» while
/// a frase is translated again, the frases told, «terminei», «recomeçar a tradução», and
/// «gravar o ensaio da cena de novo» under them.
class SceneTranslateStep extends ConsumerWidget {
  final SceneScreen scene;
  final Envelope? envelope;
  final Channel channel;
  final String language;
  final bool sending;
  final bool sendable;
  final bool unseen;
  final bool adjusts;
  final bool moving;
  final SceneLine? line;
  final bool restartShown;
  final BtRecomeco? restart;

  const SceneTranslateStep({
    super.key,
    required this.scene,
    required this.envelope,
    required this.channel,
    required this.language,
    required this.sending,
    required this.sendable,
    required this.unseen,
    required this.adjusts,
    required this.moving,
    required this.line,
    required this.restartShown,
    required this.restart,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(salaSessionProvider.notifier);
    final colors = SalaColors.of(context);
    String said(String control, [int? n]) =>
        sceneRehearsalLabelFor(control, language, n: n);
    final playing = channel is PartPlaying;
    final telling = channel is Microphone;
    final frases = scene.rehearsal?.currentFrases ?? const <SceneFrase>[];
    final idle = !sending && !scene.waiting && !telling;
    final words = TextStyle(color: colors.ink, fontSize: 16);
    final longest = frases.fold(
      1,
      (longest, frase) => max(longest, frase.spanIn(scene.length)),
    );
    final message = _messageOf(frases);

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Written(said('subTranslate'), style: words),
          const SizedBox(height: 12),
          _PlayRow(
            mood: idle && scene.listened ? ButtonMood.lit : ButtonMood.dimmed,
            playing: playing,
            label: said('playPause'),
            hint: (at) => _hintOf(playing: playing, at: at),
          ),
          const SizedBox(height: 12),
          SceneStrip(
            envelope: envelope,
            length: scene.length,
            frases: [
              for (final frase in frases)
                if (moving && frase.fraseId == scene.translatingAgain?.fraseId)
                  SceneFrase(
                    fraseId: frase.fraseId,
                    startsMs: frase.startsMs,
                    endsMs: scene.pausa?.inMilliseconds ?? frase.endsMs,
                  )
                else
                  frase,
            ],
            pausa: scene.pausa,
            playing: playing,
          ),
          if (adjusts) ...[
            const SizedBox(height: 12),
            PauseAdjustRow(
              lit: idle,
              language: language,
              onEarlier: notifier.pauseEarlier,
              onHear: notifier.hearThePause,
              onLater: notifier.pauseLater,
            ),
          ],
          if (!scene.listened) ...[
            const SizedBox(height: 12),
            _WrittenButton(
              said('translate'),
              live: idle,
              onTap: notifier.playTheSceneRehearsal,
            ),
          ],
          const SizedBox(height: 12),
          RoundActionButton(
            size: 180,
            mood: telling
                ? ButtonMood.beckoning
                : scene.waiting
                ? ButtonMood.waiting
                : sending || !scene.listened
                ? ButtonMood.dimmed
                : ButtonMood.lit,
            halo: colors.vermelhoMic,
            semanticLabel: said('tell'),
            onTap: notifier.tapTheTranslateCircle,
            background: colors.vermelhoMic.withValues(alpha: 0.10),
            border: Border.all(color: colors.vermelhoMic, width: 2),
            child: Icon(
              telling ? LucideIcons.square : LucideIcons.mic,
              size: 56,
              color: colors.vermelhoMic,
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: _Written(
                message,
                style: TextStyle(color: colors.mut, fontSize: 16),
              ),
            ),
          ],
          if (scene.translatingAgain != null && !unseen) ...[
            const SizedBox(height: 8),
            _WrittenButton(
              said('keepTheEarlier'),
              live: !scene.waiting && !telling,
              onTap: notifier.keepTheEarlierTranslation,
              bare: true,
            ),
          ],
          if (frases.isNotEmpty) ...[
            const SizedBox(height: 12),
            _Heading(said('frases')),
            const SizedBox(height: 8),
            for (final (i, frase) in frases.indexed)
              _FraseBar(
                n: i + 1,
                share: frase.spanIn(scene.length) / longest,
                words: said('frase', i + 1),
                name: said('retellFrase', i + 1),
                hearMine: said('hearMine', i + 1),
                live: idle,
                again: frase.fraseId == scene.translatingAgain?.fraseId,
                style: words,
                onTap: () => notifier.translateTheFraseAgain(frase.fraseId),
                onHear: () => notifier.hearTheFraseTranslation(frase.fraseId),
              ),
          ],
          if (!scene.wentToTheVoice) ...[
            const SizedBox(height: 16),
            _WrittenButton(
              said(sending ? 'sending' : 'send'),
              live: sendable && !sending,
              onTap: notifier.sendTheSceneRehearsal,
              large: true,
            ),
          ],
          if (restartShown || line != null) ...[
            const SizedBox(height: 12),
            SceneRestartControl(
              shown: restartShown,
              armed: restart,
              n: scene.rehearsal?.translatedFrases ?? 0,
              line: line,
              live: idle,
              language: language,
            ),
          ],
          const SizedBox(height: 8),
          _WrittenButton(
            said('again'),
            live: !sending && !scene.waiting,
            onTap: notifier.recordTheSceneAgain,
            bare: true,
          ),
        ],
      ),
    );
  }

  /// Her line under the circle: the send-off, a moved pause the room refused, a frase
  /// the room did not understand, or the frase being translated again: the last one
  /// whose pause may move, the last one on a take with no loudness to read, or an
  /// earlier one.
  String? _messageOf(List<SceneFrase> frases) {
    final again = frases.indexWhere(
      (frase) => frase.fraseId == scene.translatingAgain?.fraseId,
    );
    if (scene.wentToTheVoice) {
      return sceneRehearsalLabelFor('wentToTheVoice', language);
    }
    if (_refusalOf(line) case final refusal?) {
      return retroLabelFor(refusal, language);
    }
    if (scene.notUnderstood) return retroLabelFor('notUnderstood', language);
    if (again < 0) return null;
    final last = frases[again].fraseId == scene.rehearsal?.lastFrase?.fraseId;
    return sceneRehearsalLabelFor(
      moving
          ? 'retellingLast'
          : last
          ? 'retelling'
          : 'retellingOther',
      language,
      n: again + 1,
    );
  }

  static String? _refusalOf(SceneLine? line) => switch (line) {
    SceneLine.pauseOnlyOnTheLast => 'pauseOnlyOnTheLast',
    SceneLine.pausePastTheEnd => 'pausePastTheEnd',
    SceneLine.pauseCannotStandThere => 'pauseCannotStandThere',
    _ => null,
  };

  /// Her hint: the pausa waiting, the take playing with her clock, the end of the take,
  /// or the take paused; nothing before the team listens.
  String? _hintOf({required bool playing, required Duration at}) {
    final end = scene.takeEnd;
    final pausa = scene.pausa;
    if (!scene.listened) return null;
    if (pausa != null) {
      if (end != null && pausa >= end) {
        return sceneRehearsalLabelFor('ended', language);
      }
      return retroLabelFor(
        envelope == null ? 'pauseAtTheTap' : 'pauseHint',
        language,
      );
    }
    if (playing) return sceneListeningLineFor(at, scene.length, language);
    if (!scene.moreToTell) return sceneRehearsalLabelFor('ended', language);
    return sceneRehearsalLabelFor('paused', language);
  }
}

/// «recomeçar a tradução» while it applies, armed by its first tap with the count it
/// discards, and her line once the room answered it or failed to, written only where
/// the step may carry words.
class SceneRestartControl extends ConsumerWidget {
  final bool shown;
  final BtRecomeco? armed;
  final int n;
  final SceneLine? line;
  final bool live;
  final String language;

  const SceneRestartControl({
    super.key,
    required this.shown,
    required this.armed,
    required this.n,
    required this.line,
    required this.live,
    required this.language,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = SalaColors.of(context);
    final words = switch (line) {
      SceneLine.restarted => sceneRehearsalLabelFor('restarted', language),
      SceneLine.restartFailed => retroLabelFor('restartFailed', language),
      SceneLine.diskFailed => sceneRehearsalLabelFor('diskFailed', language),
      SceneLine.notSent => sceneRehearsalLabelFor('notSent', language),
      SceneLine.alreadySent => sceneRehearsalLabelFor('alreadySent', language),
      _ => null,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (shown)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _WrittenButton(
              armed == null
                  ? sceneRehearsalLabelFor('restart', language)
                  : retroLabelFor('restartArmed', language, n: n),
              live: live,
              onTap: ref
                  .read(salaSessionProvider.notifier)
                  .restartTheSceneTranslation,
            ),
          ),
        if (words != null) ...[
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: _Written(
              words,
              style: TextStyle(color: colors.mut, fontSize: 16),
            ),
          ),
        ],
      ],
    );
  }
}

class ScenePlacesUnknown extends ConsumerWidget {
  final SceneScreen scene;
  final String language;
  final bool sending;
  final bool sendable;
  final SceneLine? line;
  final bool restartShown;
  final BtRecomeco? restart;

  const ScenePlacesUnknown({
    super.key,
    required this.scene,
    required this.language,
    required this.sending,
    required this.sendable,
    required this.line,
    required this.restartShown,
    required this.restart,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(salaSessionProvider.notifier);
    final colors = SalaColors.of(context);
    String said(String control) => sceneRehearsalLabelFor(control, language);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _Written(
            said('placesUnknown'),
            style: TextStyle(color: colors.mut, fontSize: 16),
          ),
        ),
        if (restartShown || line != null) ...[
          const SizedBox(height: 16),
          SceneRestartControl(
            shown: restartShown,
            armed: restart,
            n: scene.rehearsal?.translatedFrases ?? 0,
            line: line,
            live: !sending && !scene.waiting,
            language: language,
          ),
        ],
        const SizedBox(height: 16),
        _WrittenButton(
          said(sending ? 'sending' : 'send'),
          live: sendable && !sending,
          onTap: notifier.sendTheSceneRehearsal,
          large: true,
        ),
        const SizedBox(height: 8),
        _WrittenButton(
          said('again'),
          live: !sending,
          onTap: notifier.recordTheSceneAgain,
          bare: true,
        ),
      ],
    );
  }
}

class SceneListenMode extends ConsumerWidget {
  final SceneScreen scene;
  final Envelope? envelope;
  final Channel channel;
  final String language;
  final bool sending;
  final SceneLine? line;

  const SceneListenMode({
    super.key,
    required this.scene,
    required this.envelope,
    required this.channel,
    required this.language,
    required this.sending,
    required this.line,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(salaSessionProvider.notifier);
    final colors = SalaColors.of(context);
    String said(String control, [int? n]) =>
        sceneRehearsalLabelFor(control, language, n: n);
    final playing = channel is PartPlaying;
    final frases = scene.rehearsal?.currentFrases ?? const <SceneFrase>[];
    int span(SceneFrase frase) => switch ((frase.startsMs, frase.endsMs)) {
      (final int starts, final int ends) => max(0, ends - starts),
      _ => 0,
    };
    final longest = frases.map(span).fold(1, max);
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _Written(
              said('listen'),
              heard: line == SceneLine.diskFailed
                  ? '${said('listen')} — ${said('diskFailed')}'
                  : null,
              style: TextStyle(color: colors.ink, fontSize: 16),
            ),
          ),
          const SizedBox(height: 12),
          _PlayRow(
            mood: sending || scene.waiting ? ButtonMood.dimmed : ButtonMood.lit,
            playing: playing,
            label: said('playPause'),
            hint: (at) => switch ((playing, scene.heard)) {
              (true, _) => sceneListeningLineFor(at, scene.length, language),
              (false, SceneHeard.partly) => said('paused'),
              (false, SceneHeard.toTheEnd) => said('ended'),
              (false, _) => null,
            },
          ),
          const SizedBox(height: 12),
          SceneStrip(
            envelope: envelope,
            length: scene.length,
            frases: frases,
            pausa: null,
            playing: playing,
          ),
          const SizedBox(height: 16),
          if (frases.isNotEmpty) ...[
            _Heading(said('frases')),
            const SizedBox(height: 8),
            for (final (i, frase) in frases.indexed)
              _FraseBar(
                n: i + 1,
                share: span(frase) / longest,
                words: said('frase', i + 1),
                name: said('frase', i + 1),
                hearMine: said('hearMine', i + 1),
                live: !scene.waiting,
                again: false,
                style: TextStyle(color: colors.ink, fontSize: 16),
                onTap: () => notifier.playTheFrase(frase.fraseId),
                onHear: () => notifier.hearTheFraseTranslation(frase.fraseId),
              ),
          ],
          const SizedBox(height: 16),
          _WrittenButton(
            said('again'),
            live: !sending,
            onTap: notifier.recordTheSceneAgain,
            bare: true,
          ),
        ],
      ),
    );
  }
}

class _PlayRow extends ConsumerWidget {
  final ButtonMood mood;
  final bool playing;
  final String label;
  final String? Function(Duration at) hint;

  const _PlayRow({
    required this.mood,
    required this.playing,
    required this.label,
    required this.hint,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.read(playbackRepositoryProvider);
    final colors = SalaColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 60),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RoundActionButton(
            size: 52,
            mood: mood,
            semanticLabel: label,
            onTap: ref.read(salaSessionProvider.notifier).playTheSceneRehearsal,
            border: Border.all(color: colors.vermelhoMic, width: 2),
            child: Icon(
              playing ? LucideIcons.pause : LucideIcons.play,
              size: 22,
              color: colors.vermelhoMic,
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Loop(
              period: const Duration(seconds: 1),
              animate: playing,
              reducible: false,
              builder: (context, _) => switch (hint(playback.position)) {
                final words? => _Written(
                  words,
                  style: TextStyle(color: colors.mut, fontSize: 16),
                ),
                null => const SizedBox.shrink(),
              },
            ),
          ),
        ],
      ),
    );
  }
}

class SceneRehearsalList extends ConsumerWidget {
  final List<SceneRehearsalRecord> rows;
  final String? onScreen;
  final bool still;
  final String language;

  const SceneRehearsalList({
    super.key,
    required this.rows,
    required this.onScreen,
    required this.still,
    required this.language,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(salaSessionProvider.notifier);
    String said(String control, [int? n]) =>
        sceneRehearsalLabelFor(control, language, n: n);
    return Semantics(
      label: said('list'),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 470,
          maxHeight: MediaQuery.sizeOf(context).height / 3,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(child: _Upper(said('list'))),
                const SizedBox(height: 8),
                for (final row in rows)
                  _ListedRow(
                    row: row,
                    onScreen: row.rehearsalId == onScreen,
                    still: still,
                    language: language,
                    onTap: () =>
                        notifier.openTheListedSceneRehearsal(row.rehearsalId),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ListedRow extends StatelessWidget {
  final SceneRehearsalRecord row;
  final bool onScreen;
  final bool still;
  final String language;
  final VoidCallback onTap;

  const _ListedRow({
    required this.row,
    required this.onScreen,
    required this.still,
    required this.language,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = SalaColors.of(context);
    String said(String control, [int? n]) =>
        sceneRehearsalLabelFor(control, language, n: n);
    final live = !onScreen && !still;
    final scene = row.sceneNumber;
    final at = row.recordedAt;
    final words = TextStyle(
      color: onScreen ? colors.ink : colors.mut,
      fontSize: 14,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Semantics(
        button: true,
        enabled: live,
        label: sceneRehearsalRowLabelFor(row, language, onScreen: onScreen),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: live ? onTap : null,
          child: ExcludeSemantics(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(
                  color: onScreen ? ShemaBrand.azul : colors.line,
                  width: 1.2,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Text('${row.n}', style: words),
                  if (scene != null) ...[
                    const SizedBox(width: 10),
                    Text(said('sceneN', scene), style: words),
                  ],
                  if (at != null) ...[
                    const SizedBox(width: 10),
                    Text(clockOf(at), style: words),
                  ],
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${row.translatedFrases} · ${said('frases')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: words,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    said(row.unsent ? 'listUnsent' : 'listSent'),
                    style: TextStyle(
                      color: row.unsent ? colors.telha : colors.mut,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Her words written on the screen, read by VoiceOver as written.
class _Written extends StatelessWidget {
  final String words;
  final String? heard;
  final TextStyle style;

  const _Written(this.words, {this.heard, required this.style});

  @override
  Widget build(BuildContext context) => Semantics(
    label: heard ?? words,
    child: ExcludeSemantics(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Text(words, style: style, textAlign: TextAlign.center),
      ),
    ),
  );
}

class _Heading extends StatelessWidget {
  final String words;

  const _Heading(this.words);

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    label: words,
    child: ExcludeSemantics(child: _Upper(words)),
  );
}

class _Upper extends StatelessWidget {
  final String words;

  const _Upper(this.words);

  @override
  Widget build(BuildContext context) => Text(
    words.toUpperCase(),
    textAlign: TextAlign.center,
    style: TextStyle(
      color: SalaColors.of(context).mut,
      fontSize: 14,
      fontWeight: FontWeight.w600,
      letterSpacing: 2.4,
    ),
  );
}

class _WrittenButton extends StatelessWidget {
  final String words;
  final bool live;
  final VoidCallback onTap;
  final bool large;
  final bool bare;

  const _WrittenButton(
    this.words, {
    required this.live,
    required this.onTap,
    this.large = false,
    this.bare = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = SalaColors.of(context);
    return Semantics(
      button: true,
      enabled: live,
      label: words,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: live ? onTap : null,
        child: ExcludeSemantics(
          child: Opacity(
            opacity: live ? 1 : 0.35,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: large ? 32 : 20,
                vertical: large ? 14 : 10,
              ),
              decoration: bare
                  ? null
                  : BoxDecoration(
                      color: large ? colors.vermelhoMic : null,
                      border: Border.all(color: colors.vermelhoMic, width: 1.5),
                      borderRadius: BorderRadius.circular(999),
                    ),
              child: Text(
                words,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: large ? colors.paper : colors.ink,
                  fontSize: large ? 18 : 14,
                  decoration: bare ? TextDecoration.underline : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One frase told, as on hers: its number, a bar as long as its stretch against the
/// longest that plays its stretch and translates it again, «frase N», and the speaker
/// that plays the team's translation of it.
class _FraseBar extends StatelessWidget {
  final int n;
  final double share;
  final String words;
  final String name;
  final String hearMine;
  final bool live;
  final bool again;
  final TextStyle style;
  final VoidCallback onTap;
  final VoidCallback onHear;

  const _FraseBar({
    required this.n,
    required this.share,
    required this.words,
    required this.name,
    required this.hearMine,
    required this.live,
    required this.again,
    required this.style,
    required this.onTap,
    required this.onHear,
  });

  @override
  Widget build(BuildContext context) {
    final colors = SalaColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 470),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                button: true,
                enabled: live,
                label: name,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: live ? onTap : null,
                  child: ExcludeSemantics(
                    child: Opacity(
                      opacity: live ? 1 : 0.35,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 0.6 * _rem,
                          vertical: 0.45 * _rem,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? const Color.fromRGBO(236, 234, 220, .05)
                              : const Color.fromRGBO(255, 255, 255, .4),
                          border: Border.all(
                            color: again ? colors.telha : colors.areia,
                            width: 1.2,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 0.05 * _rem),
                              child: SizedBox(
                                width: 26,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: _Disc(n: n, fill: colors.areia),
                                ),
                              ),
                            ),
                            const SizedBox(width: 0.55 * _rem),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 0.3 * _rem),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 10,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: const Color.fromRGBO(
                                          199,
                                          194,
                                          159,
                                          .28,
                                        ),
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: FractionallySizedBox(
                                          widthFactor: share > 0
                                              ? max(0.08, share)
                                              : 1,
                                          heightFactor: 1,
                                          child: DecoratedBox(
                                            decoration: BoxDecoration(
                                              color:
                                                  (again
                                                          ? colors.telha
                                                          : colors.claquete)
                                                      .withValues(alpha: .85),
                                              borderRadius:
                                                  BorderRadius.circular(5),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 0.15 * _rem),
                                  Text(words, style: style),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 0.4 * _rem),
            RoundActionButton(
              size: 40,
              mood: live ? ButtonMood.lit : ButtonMood.dimmed,
              semanticLabel: hearMine,
              onTap: onHear,
              child: Icon(
                LucideIcons.volume2,
                size: 18,
                color: colors.vermelhoMic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Disc extends StatelessWidget {
  final int n;
  final Color fill;

  const _Disc({required this.n, required this.fill});

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 22,
    child: DecoratedBox(
      decoration: BoxDecoration(shape: BoxShape.circle, color: fill),
      child: Center(
        child: Text(
          '$n',
          style: TextStyle(
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF1E1B15)
                : ShemaBrand.branco,
            fontSize: 0.74 * _rem,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
  );
}
