# A refused approval takes the team to the hole it names

## Context

The **Approval** had one outcome the room knew how to draw. The server answered a refusal
with a 409 carrying one sentence, the client threw a refusal of its own before reading
anything, and the room called a person — whatever the hole was, including holes the team
was standing in front of and could have filled in a minute.

Henok lived it: he finished a passage, the check came out clean, he pressed approve, and
the room asked for the facilitator. Nothing on the tablet or in its logs said which hole it
was, because nothing had been read.

The check and the approval do not ask the same questions. Both ask about an **Untold
stretch**, an **Untold part**, an **Unheard part** and the check itself; only the approval
asks about the conversation's coverage and comprehension, the rehearsal's audio, a panorama
session, a passage with no telling-back at all and a session with no project. So a passage
the voice called *conferida* can be refused for a reason the room never mentioned.

The back-translation already had doors for three of those holes, built for the verdict's
own refusals, and *terminei* is a button the room can simply hand back.

## Considered Options

**Taking the first code the gate names.** Rejected, and measured: the gate lists
`telling_back_not_checked` before the holes that have ground to stand on, and a part
recorded again resets the check, so the live refusal is `["telling_back_not_checked",
"untold_part"]`. Following the gate's order there hands the team back the very button that
was refused, over a part nobody has told back — refused again, with nothing changed.

**Keeping the 409 as the refusal.** Rejected. The client threw before reading, so the
payload could not be reached, and the version race answers the same status: a retry read as
a refusal sends the team to a hole nobody named. The server reversed it too (shema-api ADR
0028): the team's route answers a refusal with a 200 naming its blockers, and the 409 is
left to mean what it means everywhere else.

**Marking the passage done on a refusal, or closing the cord over it.** Rejected: nothing
was minted, and a passage that leaves the **Wheel** without a **Release** is a passage
nobody can come back to.

**Making the check ask the approval's questions, so *conferida* means approvable.**
Rejected for this slice: it moves work into the check that the approval is entitled to ask
about later anyway, and it does not help the team standing in front of a refusal today.

## Decision

**A refused approval takes the team to the first hole it names that the room has a door
for, in the room's own order:** the untold stretch, the untold part, the unheard part, then
the check not done or never analysed. The order is the room's, not the order the gate
raised the codes in, and it is read off one list in one place.

**Before the untold-stretch door, the stretches are read back.** A passage that reached
*conferida* on a clean first verdict never had them named, so it holds the stretches this
tablet cut, and the name the refusal gives matches none of them.

**A person is called only when there is nothing the team can do from this screen:** a hole
with no door, a code this tablet does not know, a named hole whose ground never came, and
an answer that is neither a version nor a refusal. The phase stays at *conferida* there,
exactly as a refusal has always left it.

Only the four doors are named in the tablet, by the five codes that open them; every other
code falls to a person through the same default, so a blocker the gate learns to raise
tomorrow is a person's without anything here being touched. The six that fall there today
are `no_project`, `panorama_sessions_never_release`, `no_rehearsal_audio`, `no_telling_back`
and — until the way back to the conversation exists — `coverage_floor_not_met` and
`comprehension_needs_more_work`.

**The tablet decides by the field that is there, never by the one that is missing.** A
version says a release exists; blockers say which holes stand. Nothing is inferred from an
empty body.

**A read that did not happen is not a hole with no ground.** The untold-stretch door asks
the room for the stretches' names first, and that ask can fail like any other. It is left to
fall down the approval's own ladder — repeated, the button still alive at *conferida* —
rather than resolving the refusal's name against names that never arrived and halting the
room over a request the next press would repeat. The verdict's own use of the same read is
unchanged: it already has its answer, so it survives a read that failed.

**The version race is a retry, not a refusal.** The 409 falls down the ordinary ladder, is
repeated, and halts only on the third failure, as every other request does.

## Consequences

A refusal no longer ends the passage's life on the screen. Nothing is marked done, the
passage stays on the **Wheel**, the **Resume point** is untouched and the approved process
line is not spoken — the room simply moves to where the work is.

The doors are the ones the verdict already uses, unchanged. What is new is who calls them
and in which order, so a hole the team can fill lands the team in the same place whether
the check or the approval found it.

It does not sound the same, though. The verdict carries a line the server composed for the
hole, and the landing speaks it before the part or the stretch goes in the air; the refusal
carries no line and no address for one, so the approval's landing says nothing. The team
presses, the room goes quiet, and then either the part or the stretch starts playing on its
own — or, at the check's door, nothing plays at all and only *terminei* comes back lit.
That silence is the answer, decided on 2026-09-19: the room says nothing of its own at
the check's door. A line invented here would be the tablet speaking for a server that has
not spoken, and the room's own voice belongs to the verdict; the press, the quiet and the
sound that follows are what the team reads.

Two holes at once take the first door in the room's order, and the rest of the refusal is
not remembered: the team fills that hole, checks again, and presses approve again, which is
when the next hole is named — by a server that has just looked.

The tablet's build has to be on the devices before the server's own change reaches them.
A tablet without it reads a refusal as a release with no version; the room would speak the
approved line and close the cord over nothing.

Coverage and comprehension are a person's here only because the door does not exist yet.
When the room learns the way back to the conversation, they become two more doors in the
tablet's order, and nothing else about this decision changes.

2026-09-24: `coverage_floor_not_met` and `comprehension_needs_more_work` no longer arrive. The
server's ADR 0037 took both out of the gate — the team's approval asks only about the
telling-back — so the way back to the conversation this decision anticipated is not owed for
them. The four doors and the person's remainder are unchanged.
