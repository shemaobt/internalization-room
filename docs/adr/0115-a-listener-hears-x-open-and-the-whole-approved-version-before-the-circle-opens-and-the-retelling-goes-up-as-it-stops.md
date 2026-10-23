---
status: accepted
date: 2026-10-23
---

# A listener hears X-open and the whole approved Version before the circle opens, and the retelling goes up as it stops

Her app at Tripod-Internalization 18fa7c4 is the bar (`ExternalCheck.tsx`, `strings.ts`). The
Station is ADR 0114; the listener rules are ADR 0111; the server half is shema-api ADR 0083,
whose doors number a listener under an attempt the tablet mints and keep every listener
recording as it arrives.

## Context

On the Checagem externa «Novo ouvinte» was drawn and did nothing. A stranger to the
translation has to hear the consent and the whole approved passage before anything of theirs is
recorded, and nothing of theirs may stay on the tablet.

## Considered Options

- **The listener's recording through the Outbox.** Rejected: the Outbox keeps and resends the
  team's own takes, and her rule keeps nothing of a listener on the device; a send that fails is
  recorded again.
- **The parts the team holds now instead of the check's takes.** Rejected: the listener hears
  the approved Version, even after a part was recorded again; the take door serves any take of
  the session.
- **The listener's Step in the Station value.** Rejected: a Step is not a Station transition
  (ADR 0046); it sits beside the Station as the scene rehearsal's screen does.
- **The conversation's microphone with a flag.** Rejected: the listener is a Microphone owner
  of its own, so every failure rule already silent off the session screen holds for it.
- **A part that never reports its end stalls the passage.** Rejected: the runner's ceiling
  ends such a part as an end, the house rule; only a failure stalls.
- **Sending the tablet's measured length and fingerprint.** Rejected: the room measures and
  fingerprints the bytes, and refuses a sent length that disagrees.

## Decision

- «Novo ouvinte» mints an attempt at the tap and keeps it with the session and the Version
  until an answer lands, across a way back and a way in, so a re-tap after a lost answer is
  the same listener. A failure shows «não deu para abrir a checagem
  externa — tentem de novo», never the person sign.
- Then X-open, in the Session language (ADR 0084), whose second sentence is the consent; then
  the check's takes, fetched by take id, play back to back as one stream; only the end of the
  last part says X-retell and opens the circle. The circle answers nothing while a line speaks,
  while the passage plays before the retelling, or while a recording is sent.
- A part that fails to fetch or to play, or a call for a person that takes the stream, stops it
  and offers «ouvir de novo», which plays the passage again from its start with no line. There
  is no skip. The circle opens only once X-retell was said; a call for a person that cuts it
  has it said again when the room is back.
- The retelling goes up as `retell` the moment it stops; a file under 800 bytes is dropped in
  silence; the file is deleted after the send whatever the answer; a failed send shows «não deu
  para guardar essa gravação — gravem de novo» and opens the circle again. Leaving the Station
  discards an open microphone.
- The two listener doors keep their refusals by decision, as the open does (ADR 0114): a lost
  network is told to the failure policy and the screen shows her words; a session gone goes
  where every session-naming door goes.
- Once the retelling lands the circle opens again; the end of a listener is ENG-1435's, the
  whole-passage comment and the frases ENG-1431's.

## Consequences

Listener audio leaves the tablet once and is deleted. An X-open that cannot sound still lets
the passage play, as hers does; two lines of hers in a row that cannot sound still call a
person, the house rule. Cites ADR 0014, 0046, 0084, 0086, 0111, 0114.
