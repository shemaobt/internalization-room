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

Amended by ENG-1817 and ENG-1819 (2026-10-27): the claquete shows on her canvas: the
conversation and the Panorama, and nowhere else. In her app the slate and the Shema mark
live inside `.canvas`, which the Panorama shares with a passage's conversation
(`app/page.tsx:120`, `:998-1004`; `app/globals.css:67-73`), so the Panorama reads «OV-Ruth ·
2026-09-30 14:14 · fia-fixt» as a passage reads «P05 · …». The check screen and the
rehearsals draw neither the claquete nor the mark; the Choice draws the mark alone, nothing
to tap, as hers does (`app/page.tsx:972`). Its twenty seconds are armed on the
session of the Station, as hers are on opening or resuming a session (`app/page.tsx:211`,
`:261-265`), so a session resumed onto another stage spends them unseen, as in hers.

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

Amended by ENG-1382 (2026-10-22, ADR 0117): the orange dot opens her Ensaio Final plan
(`widgets/ensaio_final_plan_view.dart`): «pensando…» while the room is read, then «Ensaio
Final», «Estes são os ensaios das cenas que vocês me enviaram.» and «Gravar cena por cena».
It is the tenth named exception, under the moment label's reason, her words the team reads.

Amended by ENG-1408 (2026-10-22, ADR 0123): the Back-translation of a joined recording reads
«Ensaio Final», and during the First listen «Primeiro, só ouvir: a passagem inteira, do
começo ao fim.» and the position line «ouvindo a gravação de vocês… — parte 2 · 0:41 /
1:10». `widgets/retro_view.dart` is already a named exception, so there is no new one.

Amended by ENG-1259 (2026-10-22, ADR 0112): an approval ends on her Saved screen
(`widgets/saved_screen.dart`): «Ensaio salvo», her approved sentence with its version, and
«Pronto». It is the eleventh named exception, under the moment label's reason, her words the team
reads. The check mark is decorative and VoiceOver skips it; «Pronto» is read by its word.

Amended by ENG-1774 (2026-10-22, ADR 0131): the scene rehearsal's record step writes the
take's state in her words: «gravando», «enviando…», her not-kept, too-large and
not-accepted lines with «falhou — toque para tentar de novo», «falhou» alone for a take
whose recording is gone, and «parar». The recording home's Scene rows, with a numbered row
for each unsent part beyond the last scene, show the same words, «✓ salvo», and «falhou —
grave de novo» for a part whose recording is gone. It is the twelfth named exception,
under the moment label's reason, her words the team reads. VoiceOver reads the same words,
but for «parar», which it reads as her «Parar o envio (a gravação fica neste computador)».

Amended by ENG-1260 (2026-10-22, ADR 0113): the Back-translation of an approved draft shows
«checagem externa: {n} ouvintes» (or «checagem externa: 1 ouvinte») when the version has
listeners, and the «Checagem externa» button; an armed control over an approved draft reads
«toquem de novo: isto abre de novo o rascunho aprovado», and a tap the room cannot answer reads
her two texts. The Back-translation and its frase list are already named exceptions, her words
the team reads, so no new exception is named.

Amended by ENG-1421 (2026-10-23, ADR 0114): her Checagem externa screen is a named exception,
her words the team reads: the title «Checagem externa», the idle sub-line «Quem não ajudou a
traduzir ouve a passagem e diz o que entendeu.» and «Novo ouvinte». Its back control is an icon
VoiceOver reads by her name, «Voltar para a gravação».

Amended by ENG-1766 (2026-10-23, ADR 0134): her grain choice
(`widgets/grain_choice_view.dart`): «Gravem o ensaio de vocês», «Como vocês querem gravar?»,
«A passagem inteira» «uma gravação» and «Cena por cena» «{N} partes», and the recording
home's and the plan's grain controls, «gravar a passagem inteira de uma vez», «Gravar a
passagem inteira», «Gravar cena por cena» and «Ensaio Final: juntar os ensaios das cenas», with
their armed texts. It is the thirteenth named exception, under the moment label's reason, her
words the team reads.

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

Amended by ENG-1377 (2026-10-22, ADR 0124): the Update screen writes its line and its button
(`widgets/update_view.dart`): «Há uma versão nova do aplicativo. Toquem para atualizar.» and
«Atualizar». It is a named exception under its own reason, the words that send the team to the
store: a build kept out of the room has no stage to speak through. VoiceOver reads the line and
the button.

Amended by ENG-1711 (2026-10-28): «Ouvir tudo» on her recording home opens a listen-only
screen (`widgets/ouvir_tudo_view.dart`) that writes her title, «A gravação de vocês inteira,
parte por parte.», and ends with «fim da gravação», as hers does. It is an exception under
the existing reason, her words the team reads; the button on the home is already inside her
recording home's exception.

Amended by ENG-1839 (2026-11-02): the parity sweep of 26–30 October wrote words on five
screens, and each sweep PR left this record untouched so that none collided on it; this
block collects them, with her lines at 18fa7c4 (`app/lib/strings.ts`, pt then en, unless
another file is named). None is new to `facilitator_script.dart`: every one was already
among her labels, spoken by VoiceOver, and is now written where hers writes it.

The conversation and the Panorama: while the team holds the microphone the mic clock writes
«m:ss» above the circle (`widgets/mic_clock.dart`, ENG-1821), telha from four minutes, as
her `fmtClock` does (`app/page.tsx:38`, `:1006`; `app/globals.css:78-81`); it is digits and
not a word, a named exception under the numerals' reason. While the voice thinks,
«pensando…» / «thinking…» (`:391` / `:256`; `app/page.tsx:1005`, `app/globals.css:217`) is
written under the circle (`widgets/thinking_note.dart`, ENG-1925), a named exception under
the moment label's reason, her words the team reads. ADR 0043's «the room has no text on
screen» (ENG-1141, after ENG-1078) is read with them: the circle itself still writes
nothing, and the canvas around it writes these two.

The check screen (`widgets/retro_view.dart`, already named; `widgets/part_strips.dart`,
`widgets/status_lines.dart`, `widgets/pause_adjust_row.dart` and
`widgets/approve_button.dart` join it): beside each part's strip «parte N» / «part N»
(`:292` / `:157`) or «A passagem inteira» / «The whole passage» (`:268` / `:133`; her
`app/components/Drafting.tsx:2316`, ENG-1882), with « ·» after the label of a part the room
still counts unheard or whose take has not reached it, in telha, a glyph and not a word
(`app/globals.css:436`, ENG-2040); beside play, her listening lines (ENG-1832; hers
`Drafting.tsx:2367-2369`): «ouvindo a gravação de vocês…» / «listening to your recording…»
(`:287` / `:152`), «pausado — toque no círculo para marcar onde a frase acaba» / «paused —
tap the circle to mark where the sentence ends» (`:287` / `:152`), «a pausa ficou aqui —
ouçam, ajustem se precisar e toquem no círculo para traduzir» / «the pause is here — listen,
move it if you need to, then tap the circle to translate» (`:346` / `:211`), «a pausa ficou
no toque — toquem no círculo para traduzir» / «the pause is at your tap — tap the circle to
translate» (`:347` / `:212`), «fim da gravação» / «end of the recording» (`:291` / `:156`),
and the place «parte N · m:ss / m:ss», or the clock alone after a retell (ENG-2062); under
«terminei» the lines «ainda falta ouvir um trecho da gravação» / «there is still a part of
the recording to listen to» (`:285` / `:150`) and «falta traduzir um trecho — ouçam e
traduzam, depois toquem em 'terminei'» / «one stretch has no translation — listen,
translate, then tap 'done'» (`:377` / `:242`; hers `Drafting.tsx:2467`, ENG-1888); the pause
controls «um pouco antes», «ouvir a pausa», «um pouco depois» / «a little earlier», «hear
the pause», «a little later» (`:345` / `:210`; hers `Drafting.tsx:2399`, ENG-1881); her
approve button «Aprovar como rascunho final» / «Approve as the final draft» (`:301` /
`:166`; hers `Drafting.tsx:2468`, ENG-1838), written where it was spoken only; and on the
check of a joined recording «gravar a passagem inteira de uma vez» / «record the whole
passage in one go» (`:382` / `:247`; hers `Drafting.tsx:2242`) with its armed «toquem de
novo: as cenas e as traduções ficam guardadas» / «tap again: the scenes and the translations
are kept» (`:382` / `:247`) and «toquem de novo: isto abre de novo o rascunho aprovado» /
«tap again: this re-opens the approved draft» (`:383` / `:248`, ENG-1876). Words that left
the check: «parte N» on the frase rows of a whole-passage recording (ENG-1877), «✓ traduzida
e conferida» (ENG-1885), and the listeners' count with the «Checagem externa» button
(ENG-2052), which stay on the home as hers draws them (`Drafting.tsx:2552-2553`), so the
ENG-1260 amendment above is read for the home.

The recording home (`widgets/ensaio_view.dart`, already named; `widgets/listeners_line.dart`
and `widgets/external_check_button.dart` join it): «✓ traduzida e conferida» / «✓ translated
and checked» (`:285` / `:150`; hers `Drafting.tsx:2543`), and on its rows «regravada —
traduzam de novo» / «re-recorded — translate again» (`:292` / `:157`) and «regravada —
traduzam esta frase» / «re-recorded — translate this sentence» (`:388` / `:253`; hers
`Drafting.tsx:2497`, ENG-1824); «checagem externa: 1 ouvinte» / «external check: 1 listener»
and «checagem externa: {n} ouvintes» / «external check: {n} listeners» (`:329` / `:194`;
hers `Drafting.tsx:2552`, ENG-1833) with the «Checagem externa» / «External check» button
(`:326` / `:191`; `:2553`); «Aprovar como rascunho final» (ENG-1838; hers
`Drafting.tsx:2547`); under its title, while a re-recorded sentence is owed, «não deu para
guardar a frase — tentar de novo» / «the sentence could not be saved — try again» (`:389` /
`:254`; hers `Drafting.tsx:2135`, ENG-2061); and on a scene row whose bring-back the room
refused, «este ensaio não pode entrar — ensaiem esta cena de novo» / «this rehearsal cannot
be used — rehearse this scene again» (`:375` / `:240`; hers `Drafting.tsx:2037`, ENG-1916).
So «the rest of that screen stays wordless» (ENG-1406, above) is no longer read alone: the
home writes these too.

The Ensaio Final plan and the grain choice (`widgets/ensaio_final_plan_view.dart` and
`widgets/grain_choice_view.dart`, already named; `widgets/unsent_notice.dart` joins them): a
take still on the tablet is offered under her notice, «Uma gravação ainda está neste
computador e não foi enviada.» / «A recording is still on this computer and has not been
sent.» (`:319` / `:184`; hers `Drafting.tsx:2207`), «Cena N · m:ss — enviar agora» / «Scene
N · m:ss — send it now» (`:269`, `:319` / `:134`, `:184`; `:2210`, ENG-1861) or «A passagem
inteira · m:ss — enviar agora» (`:268`, `:319` / `:133`, `:184`, ENG-2078), with the
button's spoken name «Enviar a gravação» / «Send the recording» (`:319` / `:184`). They were
the home's words already (ENG-1774, above).

The scene rehearsal (`widgets/scene_translate_step.dart`, already named;
`widgets/stage_heading.dart` and `widgets/scene_take_state.dart` join it): on every step the
title «Ensaio da cena» / «Scene rehearsal» (`:352` / `:217`; her
`app/components/Rehearsal.tsx:813`) and this session's list, «ensaios da cena desta sessão»
/ «scene rehearsals of this session» (`:357` / `:222`; `:789`) with, per rehearsal, its
number, «cena N» / «scene N» (`:367` / `:232`; `:794`), its clock HH:MM, «{k} · frases
traduzidas» and «enviado» / «não enviado» — «sent» / «not sent» (`:360` / `:225`; `:803`,
ENG-1825). On the record step (ENG-1834, ADR 0155): «Toquem no círculo para gravar o ensaio
da cena; toquem de novo para parar.» / «Tap the circle to record the scene rehearsal; tap
again to stop.» (`:358` / `:223`; `:846`), «gravem o ensaio da cena na língua materna;
toquem para parar» / «record the scene rehearsal in your own language; tap to stop» (`:353`
/ `:218`; `:841`), «gravando · m:ss» / «recording · m:ss» (`:317` / `:182`) and «guardando o
ensaio da cena…» / «keeping the scene rehearsal…» (`:362` / `:227`). On the translate step
(ENG-1823): «frases traduzidas» / «translated sentences» (`:292` / `:157`; `:912`) over the
frase rows, drawn in capitals as hers (`app/globals.css:440`); «recomeçar a tradução» /
«start the translation over» and its armed «toque de novo para apagar as {n} frases
traduzidas» / «tap again to discard the {n} translated sentences» (`:349` / `:214`; `:926`);
the restart's answers «tradução recomeçada — o ensaio da cena ficou» / «translation started
over — the scene rehearsal stays» (`:364` / `:229`; `:733`) and «não deu para recomeçar
agora — tentem de novo» / «couldn't start over right now — try again» (`:351` / `:216`;
`:736`), and the disk word of ADR 0129; the pause lines carry « — m:ss / m:ss» (ENG-1981).
On places unknown: «as frases já traduzidas não estão neste computador — toquem em terminei
para enviar, ou recomecem a tradução» / «the phrases already translated are not on this
computer — tap done to send them, or start the translation over» (`:394` / `:259`; `:910`),
her instruction «Ouçam o ensaio da cena; toquem no círculo para pausar onde a frase acaba, e
de novo para traduzir só aquela frase.» / «Listen to the scene rehearsal; tap the circle to
pause where the phrase ends, and again to translate only that phrase.» (`:359` / `:224`;
`:879`, ENG-1840), «terminei» / «done» (`:355` / `:220`; `:929`), «enviando a tradução do
ensaio da cena para a voz…» / «sending the translation of the scene rehearsal to the voice…»
(`:356` / `:221`; `:929`, also beside play, ENG-2083) and «gravar o ensaio da cena de novo»
/ «record the scene rehearsal again» (`:354` / `:219`; `:930`). On the sent step (ENG-1825):
her line «A tradução deste ensaio da cena já foi para a voz. Toquem numa frase para ouvir o
ensaio naquela parte, e no alto-falante para ouvir a tradução de vocês.» / «This scene
rehearsal's translation already went to the voice. Tap a phrase to hear the rehearsal there,
and the speaker to hear your translation of it.» (`:366` / `:231`; `:879`), «ouvindo o
ensaio da cena… — m:ss / m:ss» / «listening to the scene rehearsal… — m:ss / m:ss» (`:363` /
`:228`; `:870`), «frases traduzidas», each frase's number and «frase N» / «phrase N» (`:360`
/ `:225`; `:915`), «gravar o ensaio da cena de novo», and in listen mode also «pausado —
toque no círculo para marcar onde a frase acaba» and «fim do ensaio da cena» / «end of the
scene rehearsal» (`:363` / `:228`; `:872`, ENG-1922). So «The rest of that screen stays
wordless» (ENG-1344, above) is no longer read: every step writes. «The strip beside them
stays wordless» (ENG-1348, above) still holds of the strip, which draws no word
(`widgets/scene_strip.dart`); the translate step's words are the ones here, not only the
four ENG-1348 named.

Not written, only spoken by VoiceOver, so no exception is named: the hand's and the reply's
names in English and the circle at rest, «Toque para falar» (`:266`, ENG-1950); «Voltar para
a gravação» / «Back to recording» (`:274` / `:139`) on every Back-translation screen
(ENG-1835); «Hear that again» (`:131`, ENG-1948); and the person sign's label, which leaves
(ENG-1894).
