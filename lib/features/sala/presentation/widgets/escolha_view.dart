import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import '../../domain/book_names.dart';
import '../../domain/facilitator_script.dart';
import '../../domain/passagem.dart';
import '../../domain/session_state.dart';
import 'facilitator_circle.dart';
import 'shema_mark.dart';

const _rem = 16.0;

class EscolhaView extends ConsumerWidget {
  const EscolhaView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(salaSessionProvider);
    final language = ref.watch(roomLanguageProvider);
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
              escolhaLabelFor('choosePassage', language),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 1.5 * _rem,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.01 * 1.5 * _rem,
                color: colors.momentoInk,
              ),
            ),
            if (session.entriesOpen)
              _Books(session: session, language: language)
            else
              _Circle(session: session, language: language),
          ],
        ),
      ),
    );
  }
}

class _Circle extends ConsumerWidget {
  final SalaSessionState session;
  final String language;

  const _Circle({required this.session, required this.language});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(salaSessionProvider.notifier);
    return FacilitatorCircle(
      size: facilitatorCircleSize,
      halt: session.halt,
      voice: session.voice,
      reach: session.reach,
      semanticLabel: escolhaLabelFor(
        session.livroInteiroFeito || session.wheelHalted
            ? 'allDone'
            : 'readTheWheel',
        language,
      ),
      onTap: notifier.escolhaTap,
      onLongPress: session.canResolveWithPerson
          ? notifier.resolveWithPerson
          : null,
    );
  }
}

class _Books extends StatelessWidget {
  final SalaSessionState session;
  final String language;

  const _Books({required this.session, required this.language});

  bool _isTheEntryLeft(Passagem entry) =>
      session.isTheEntryLeft(entry, language: language);

  @override
  Widget build(BuildContext context) {
    final books = <String, List<Passagem>>{};
    for (final entry in session.naRoda!) {
      books.putIfAbsent(entry.book, () => []).add(entry);
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 540),
      child: Column(
        spacing: 1.4 * _rem,
        children: [
          for (final MapEntry(key: named, value: inBook) in books.entries)
            _Book(
              name: bookNameFor(named, language),
              panoramas: [
                for (final entry in inBook)
                  if (entry.isPanorama)
                    _Pill(
                      entry: entry,
                      words: escolhaLabelFor('bookPanorama', language),
                      tinted: _isTheEntryLeft(entry),
                      language: language,
                    ),
              ],
              passages: [
                for (final entry in inBook)
                  if (!entry.isPanorama)
                    _Pill(
                      entry: entry,
                      words: referenceFor(entry.reference, language),
                      tinted: _isTheEntryLeft(entry),
                      language: language,
                    ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Book extends StatelessWidget {
  final String name;
  final List<Widget> panoramas;
  final List<Widget> passages;

  const _Book({
    required this.name,
    required this.panoramas,
    required this.passages,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      spacing: 0.7 * _rem,
      children: [
        Semantics(
          label: name,
          header: true,
          child: ExcludeSemantics(
            child: Text(
              name.toUpperCase(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 0.72 * _rem,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.18 * 0.72 * _rem,
                color: SalaColors.of(context).claquete,
              ),
            ),
          ),
        ),
        Column(
          spacing: 0.55 * _rem,
          children: [
            for (final panorama in panoramas)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: SizedBox(width: double.infinity, child: panorama),
              ),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 0.55 * _rem,
              runSpacing: 0.55 * _rem,
              children: passages,
            ),
          ],
        ),
      ],
    );
  }
}

class _Pill extends ConsumerWidget {
  final Passagem entry;
  final String words;
  final bool tinted;
  final String language;

  const _Pill({
    required this.entry,
    required this.words,
    required this.tinted,
    required this.language,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = SalaColors.of(context);
    final panorama = entry.isPanorama;
    const size = 0.95 * _rem;
    const dot = 0.66 * size;
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () =>
              ref.read(salaSessionProvider.notifier).openTheEntry(entry),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                width: 1.5,
                color: switch (entry) {
                  _ when panorama || tinted => ShemaBrand.azul,
                  Passagem(approved: true) => colors.claquete,
                  _ => ShemaBrand.areia,
                },
              ),
              color: switch (panorama) {
                _ when tinted => ShemaBrand.azul.withValues(alpha: 0.18),
                true => ShemaBrand.azul.withValues(alpha: 0.10),
                false => null,
              },
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: 0.6 * _rem,
                horizontal: 1.05 * _rem,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      panorama ? '◈ $words' : words,
                      semanticsLabel: words,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: size,
                        fontWeight: panorama ? FontWeight.w600 : null,
                        letterSpacing: panorama ? 0.02 * size : null,
                        color: colors.momentoInk,
                      ),
                    ),
                  ),
                  if (entry.approved && !panorama)
                    Padding(
                      padding: const EdgeInsets.only(left: 0.45 * dot),
                      child: Semantics(
                        label: escolhaLabelFor('approved', language),
                        child: ExcludeSemantics(
                          child: Text(
                            '●',
                            style: TextStyle(
                              fontSize: dot,
                              color: colors.telha,
                            ),
                          ),
                        ),
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
