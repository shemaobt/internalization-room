---
status: accepted
date: 2026-10-16
amends: 0014, 0061
---

# The Choice is her text menu, and the passage ruler and its spoken references leave

Amended by ENG-2034 (2026-10-29): the third bullet of the Decision. As in her app, the
entry left is tinted whichever language the list is shown in, the Panorama included: her
pill is current whenever it is the session's passage, and «PT» and «EN» only rename the
pills. The tint and the way back now agree in both languages. A tap on the tinted pill in
the other language still opens that passage in the Room language, as hers does; only the
way back returns to the session left, in the language it was opened in.

This amends ADRs 0014 and 0061 without editing their decisions; it adds a paragraph at the
top of 0014 and "amended by 0090" to 0061's status line. The Definer settled it on
16 October (ENG-1297).

## Context

Marcia's rule of 1 October is that her frozen app is the bar for what the team sees. Her
app puts the day's passage on screen through a short text menu, «Escolha a passagem». Ours
showed a wordless Choice: a circle, a wooden enter button and a ruler with one notch per
passage, where lifting the finger played the reference aloud. She approved those spoken
references on 21 September, but no ruling of hers says that the ruler replaces her menu
(the Definer, 16 October, reading the rulings through 8 October). The ticket's written rule
therefore decides: her menu ships. The teams learned the ruler, so this changes a habit.

## Decision

- **The Choice is her menu,** copied from her picker: the Shema mark, «Escolha a passagem»,
  then one block per book the room lists, in the room's order, headed by the book's name in
  the Room language. Each block starts with «◈ Panorama do Livro» when the room lists the
  book's Panorama, then one pill per passage. A pill shows only the passage's Reference.
  «●» follows the Reference of a passage whose final draft the room approved, and VoiceOver
  reads it «tem um ensaio salvo». The menu offers exactly what the room lists.
- **The Reference comes from the room,** as the Meaning Map's heading writes it. The tablet
  renames only the book, from her own table, in the Room language (ADR 0077). A book she
  never named keeps the room's name.
- **The entry left is tinted** when its Session language is the Room language, the Panorama
  included. Nothing else is tinted, so nothing on the menu marks a passage as started.
- **One tap opens an entry.** There is no confirmation step and no «opening» state on the
  pill: the tap leaves the Choice at once.
- **While no entry can be opened, the circle stands where the books were** and answers as it
  did (ADR 0019, no dead end): it reads the Wheel again, retries offline, and takes the call
  for a person.
- **The passage ruler, the wooden enter button and the spoken references leave the
  Choice.** Nothing on the tablet plays the references any more. The server still voices
  them, and the 21 September ruling stays recorded as history.
- **The menu is the sixth named exception of ADR 0014**, under the moment label's reason:
  her words, which the team reads. Her own stylesheet calls the menu "the one place text is
  allowed (setup, often the facilitator)".

## Considered Options

**Keep the ruler.** Rejected: that needs her written word, and none exists.

**Speak the references and show the menu as well.** Rejected: her app does not speak on
its picker, and the bar is her app.

## Consequences

- ADR 0061's bullet "A read of the finished passages waits for the write in flight" has
  nothing left to govern, because the tablet keeps no list of finished passages
  (ENG-1297, ADR 0065's amendment). Its Wheel is now written.
- The team guide's pages and screen captures on choosing a passage show her menu again.
- A tablet shows only the books the room lists for the book it asks for. More books appear
  when the tablet asks for them (ENG-1248).
