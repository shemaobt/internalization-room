# The room stays wordless, and CI enforces it

Amended by ENG-1250 (her moment label): the conversation screen writes the moment the voice
named — «Familiarização · a passagem inteira», «Internalização · cena 2 de 4» — as Marcia ruled
it on 2026-09-24 («A palavra está sempre escrita», D8 (a)). It is the second named exception,
and the only one the **Team** sees; its words are hers, and it reads the same through
VoiceOver.

Amended by ENG-1535 (Henok, 2026-10-09): the moment chip leaves the screen until her own
moment label arrives with ENG-1434; the exception above no longer stands.

Amended by ENG-1434 (2026-10-12): her moment label arrives on the session screen
(`widgets/moment_label.dart`), in her words, her colours and her hiding rules, and the
exception stands again under its own reason, her words the team reads.

Amended by ENG-1379 (2026-10-19): once every part of a passage has a kept retelling, the
session screen shows her small numbered buttons (`widgets/kept_retelling_buttons.dart`), one
numeral per part, as in her app (`app/page.tsx:1053`). The numeral names the part and is not a
word; it is the fourth named exception, under its own reason, the numerals the parts are
called by, and VoiceOver reads each button as «Hear how you told part N».

Amended by ENG-1310 (2026-10-14): each session shows her claquete in the bottom row for
twenty seconds after it opens or resumes, and again on a tap of the Shema mark
(`widgets/claquete.dart`): «P05 · 2026-09-30 14:14 · fia-fixt». It is the third named
exception, under its own reason, words only the camera reads, so that the field video can be
matched to the session. It is also on the Team's screen, so «the only one the Team sees»
above is not read alone; it is not a control and VoiceOver skips it.

Amended by ENG-1296 (2026-10-15): the Choice shows «PT» and «EN» at its top right, and the
team taps one to choose the Room language (`widgets/language_and_look.dart`). It is the fourth
named exception, under its own reason, the words the team picks its language by: the codes
are the language's own name, and the team sees them on the Choice only. They are controls,
so VoiceOver reads each one's word and says which is selected. The sun and the moon beside
them are icons, labelled in the Room language.

Amended by ENG-1344 (2026-10-16, ADR 0088): the scene rehearsal's record step writes the
scene question, its buttons and the chip above the circle (`widgets/scene_question.dart`):
«Qual cena vocês vão ensaiar?», «cena 2 Primeiro apelo e recusa», «cena 2 · Primeiro apelo e
recusa». It is the fifth named exception, under the moment label's reason, her words the team
reads; VoiceOver reads each one's written words, and the chip's name adds the question it goes
back to. The rest of that screen stays wordless.

Amended by ENG-1297 (2026-10-16, ADR 0090): the Choice shows her passage menu
(`widgets/escolha_view.dart`): «Escolha a passagem», each book's name, «◈ Panorama do
Livro», each passage's reference and «●». It is the sixth named exception, under the moment
label's reason, her words the team reads. Her own stylesheet calls the menu "the one place
text is allowed (setup, often the facilitator)". VoiceOver reads each pill's words, and «●»
as «tem um ensaio salvo».

Amended by ENG-1205 (2026-10-19): the check screen shows her words
(`widgets/retro_view.dart` and its list, `widgets/frase_list.dart`): her heading «Traduzir a
gravação», the sub-line that says what to do, and «frases traduzidas» with each translated
frase numbered as the voice numbers it and labelled with its «parte». It is the seventh named
exception, under the moment label's reason, her words the team reads: her 1 October rule
makes her frozen screen the bar, and on hers «na frase 3» points at a «3» on the screen.

Amended by ENG-1348 (2026-10-19, ADR 0099): the scene rehearsal's translate step shows her
words (`widgets/scene_translate_step.dart`): her instruction «Ouçam o ensaio da cena; toquem no
círculo para pausar onde a frase acaba, e de novo para traduzir só aquela frase.», her hint with
its clock, «traduzir o ensaio da cena» and each «frase N». It is the eighth named exception,
under the moment label's reason, her words the team reads: her frozen screen is the bar, as for
the check screen. VoiceOver reads each one's written words; the strip beside them stays wordless.

Amended by ENG-1406 (2026-10-20, ADR 0102): the Rehearsal is her recording home
(`widgets/ensaio_view.dart`): «Gravem o ensaio de vocês», or «Ensaio Final» once a part
was joined, her sub-line, «Cena N» with each scene's title, and «gravem todas as partes
primeiro». It is the ninth named exception, under the moment label's reason, her words
the team reads. Her record, listen, record-again and stop controls are icons VoiceOver reads
by her names; the rest of that screen stays wordless.

Amended by ENG-1774 (2026-10-22, ADR 0112): the scene rehearsal's record step writes the
take's state in her words: «gravando», «enviando…», her not-kept, too-large and
not-accepted lines with «falhou — toque para tentar de novo», and «parar». The recording
home's Scene rows show the same words and «✓ salvo». It is the tenth named exception, under
the moment label's reason, her words the team reads. VoiceOver reads the same words, but
for «parar», which it reads as her «Parar o envio (a gravação fica neste computador)».

## Context

The **Team** cannot read. Every screen is spoken, and a written word on a team screen is a
regression that looks fine on a developer's laptop and is invisible to the people who
actually use the room — so review will not catch it.

## Considered Options

Keeping the exception out of reach, in a directory the check never walks. Rejected: an
exception nobody reviewing a diff can see is worse than one named in the rule.

## Decision

CI fails the build if a text widget appears anywhere in the room's presentation layer. The
**Claim code** screen is the single exception, and it is named inside the check rather than
moved outside it.

## Consequences

The rule is mechanical and cannot be argued with in review, which is the point. The
exception is honest: a **Facilitator** reads that one screen once, at installation, and the
**Team** never sees it again.
