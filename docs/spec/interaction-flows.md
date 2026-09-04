<!--
`interaction-flows.html` is the canonical source — this file is a derived text
extraction, produced for grep-ability, not a replacement. It carries every
heading (with its § number) and every paragraph/list item from the HTML, in
document order, unreworded. The diagrams (SVG figures and their captions), the
role table in §10, and the verbatim prompt bodies (the `<pre>` blocks §10
carries per role) are content only the HTML has — this file names the section
they live under and stops there.
-->

shemaobt / Tripod-Internalization

# How the Digital Facilitator talks with the team

The interaction flows behind the internalization room — the live turn loop, the session arc to completion, and the three satellite loops (kept rehearsal, back-translation, raised hand) — extracted from the prompts, design docs, and turn code.

## §1 The cast: one voice, six prompts

Everything the team hears is one persona — o Facilitador Digital — but each prompt has exactly one job. Every voiced role passes through the same Validator before TTS; internal roles return JSON only.

## §2 The live turn loop

One exchange, tap to tap. The voice path is kept short and honest; the expensive classifier runs after the reply ships and the beads settle during the team's reflection pause.

## §3 The screen’s state machine

The team never reads these words — each phase is a color-and-motion state on the single canvas, readable from across the room.

How long does this loop spin? This is the innermost of three nested loops. The turn cycle above is one micro-exchange (seconds to a couple of minutes) and fires dozens of times per session — invite is not a new invitation each time, just the circle’s resting state, and many turns are spent with the team ignoring the screen and talking among themselves. The scene loop (section 4’s middle rows) consumes many turn cycles per scene — open, rehearse, retell, check, back to rehearse. The session arc runs once per pericope. The loop exits on “floor met” only when the app’s completion floor is satisfied: every concrete element of the map — each scene, being, place, object, time, significant absence, and preserved element — is engaged (worked with in the team’s own words; merely surfaced never counts), with only the four abstract Level-1 axes allowed to exit at surfaced. The Guide steers the loop from inside the prompt via the REMAINING list, and won’t invite the final rehearsal until it is empty — so the loop’s last lap is the final telling-backs and then the recording handoff — a readiness cue from the Guide, fixed directions from the app. Because the real classifier runs ~28 s off-path, done may land moments after the final turn, while the beads settle. And done is per pericope: the next passage starts a fresh session, a fresh map, a fresh loop — only the “story so far” digest carries forward.

## §4 The session arc — beginning to completion

The Guide drives the pedagogy (frame first, elicit second); the app owns completion. Coverage lives in application code and is injected back into the prompt each turn. Since 65ec920 the session runs on two languages: rehearsal happens in the mother tongue; every exchange with the Guide — including the telling-back of what was rehearsed — happens in the bridge language.

## §5 Kept Rehearsal (Ensaio Guardado)

When a retelling passes, that turn’s team audio becomes a memory aid — nothing is ever generated.

## §6 Back-translation (Retrotradução)

The epistemic law: the system never knows what the Terena recording says — only what the team told back in the bridge language (língua ponte / língua de grande recurso — Portuguese, in this pilot). Every verdict is phrased “no que você me contou de volta…”. What it checks is the first team rehearsal, whole or scene by scene, before it travels to OBT Refine — a light but mandatory gate: every current clip needs a told-back pass, but conferida is not required to hand off (open questions stay visible as “levar ao Refine com perguntas”).

Three verification layers, three different objects. Understanding ≠ recording: even a team that internalized everything can, at recording time, skip a detail or add one out of habit (“Rute, mulher de Malom” — true in tradition, deliberately untold in Ruth 1). That is an error in the audio artifact, which the system can never see directly — only reach through the telling-back. The layers stack, each checking what the previous one cannot:

So the §9 remainder sweep does not eliminate the back-translation — it makes it cheaper. Complete internalization reduces how many findings the check meets, but the verification role survives any amount of coverage (understanding is not performing), and the artifact the loop produces — time-aligned bridge-language chunks with pass-1/pass-2 labels, attempt history included — is the evidence packet that travels with the rehearsal into OBT Refine, where peers and community examine the work. The system’s recurring pattern, again: one half makes success likely (internalization), the other makes confidence verifiable (back-translation).

## §7 The Raised Hand (Mão Erguida)

Deliberately not an AI channel — “not a doorbell but a mailbox.” Human speech carried verbatim, both directions; the only model touch is STT for the inbox.

## §8 When things go wrong — the designed degradation

The fail-safe embodies the whole stance in miniature: when the system cannot be sure it is grounded, it says less, stays warm, and hands control back.

- Validator regenerates twice → stop; voice a pre-approved line, re-anchored to the current scene (“Vamos parar um instante aqui e olhar de novo o que está acontecendo nesta parte…”).
- Model error / timeout / unparseable draft → same safe line; the team never hears the mechanics (“the validator rejected my answer” — never).
- Inaudible audio → “Desculpa, não consegui ouvir direito — podem repetir?” with no model round-trip.
- Question outside the map → honest silence (“a passagem não conta isso”), or — if it matters — a warm handoff: “é exatamente o tipo de pergunta para levar ao facilitador.”
- Mother-tongue speech confidently detected on the conversation mic (category G, new at 65ec920) → affirm the practice, state the boundary, invite the report — “Que bom — vocês experimentaram na língua de vocês. Eu não consigo conferir essas palavras diretamente. Alguém pode me contar em português o que vocês disseram?” The uncertain transcript is never fed to the Guide as if it were bridge speech.
- 3+ consecutive failures → graceful pause, needsPerson, flagged for review (usually infrastructure, not content).
- Every firing is logged — and the out-of-map questions are treated as high-value signal for improving the maps themselves. “The failure path is not just a safety net — it’s an instrument.”

The miniature of the whole system: saying “let’s look again at this part of the passage” forever would be a poor tool, but never an unsafe one. The rest of the system exists to make the fail-safe rarely needed; the fail-safe exists to make its rare firings harmless.

## §9 Proposals — a developer’s observations

Starting from João’s observation: “it is impossible to make sure the Bible will never be queried, even if the LLM follows the Meaning Map strictly — or am I wrong?”

The observation is correct. The Bible — and Ruth in particular, one of the most retold texts in the training data — lives in the model’s weights. A prompt can suppress parametric knowledge; it cannot remove it. So “the model never consults the Bible” is unenforceable in principle: every token the Guide generates is produced by a network that knows the whole book, including everything the map withholds. The system’s own documents implicitly concede this — the Validator exists because “generation is fallible” — but the Validator carries the same weakness: it also knows the Bible, and is merely instructed not to use that knowledge. What the architecture actually guarantees is weaker, and honest about it: containment is enforced at the output boundary, probabilistically, in layers — never inside the model.

Proposals that follow from taking the observation seriously:

- Reframe the guarantee, then measure it. Stop treating containment as a property of the prompts and treat it as a metric of the output boundary. Build a permanent eval suite of canary claims — facts true in the Bible but deliberately absent from the map (the R10 pairing, divine causation in P01, grief language) — and run Guide + Validator against adversarial team utterances that bait them (“mas todo mundo sabe com quem Rute era casada…”). Gate every prompt change on the canary pass-rate, the way the repo already gates canon drift.
- Citation-required validation. Today the Validator answers “grounded?” — a judgment its own Bible knowledge can contaminate. Stronger: require it to quote the map span that supports each claim (claim → citation mapping). A claim with no citable span fails mechanically, whether or not it “feels true.” Plausibility bias has nowhere to hide when the standard is a quote, not a feeling.
- Disagreement widens the net. For the high-stakes turns (final-rehearsal verdicts, preserved elements, filled silences), run two validators with independently phrased instructions; any disagreement → fail-safe. The existing single-validator pass is tuned for cost on every turn — spend more only where an error becomes Scripture.
- Watch the rendering, not just the facts. Leak 3 is invisible to a fact checker: “levantou-se” vs “se levantou” is caught by the style rules, but an Almeida-flavored phrase can smuggle an interpretive choice the map leaves open. Add a small register check (or extend the Validator’s brief) for wording that matches known Portuguese translations more closely than the map’s own prose warrants.
- Log verdicts as a containment time-series. The repo already logs fail-safes and boundary questions. Add the Validator’s issues categories per turn as a metric: a rising rate of imported_knowledge is an early-warning signal that a prompt or model change weakened suppression — visible before a team ever hears a leak.
- Accept where the real guarantee lives. No architecture on top of a pretrained model proves non-consultation — constrained decoding and RAG-only setups still generate through the same weights. The system’s deepest answer is already in its design: the human facilitator and the consultant remain the final authority, and the tool’s honest claim is that it makes their job tractable, not that it replaces the need for them. Say that plainly in the docs; it is a stronger position than an unprovable purity claim.

Latency proposals that live in the prompts. The turn chain is strictly serial (STT → Guide → Validator → TTS), so every token the prompts carry is paid on the voice path, twice. These three changes are to the prompt architecture and content only:

- Cache-first prompt ordering. Both the Guide’s and the Validator’s prompts are dominated by content that is identical every turn — the system prompt, the Meaning Map, the story-so-far digests. Restructure each prompt into a stable prefix (everything static, ending with a cache_control breakpoint) followed by the per-turn material (coverage status, the kept-rehearsal line, history, the drafted response). The map is then processed once per session instead of on every call — the single largest cut available to the guide+validator stage, and the prompt files already gesture at it (the kept-rehearsal line “sits after the cache break”). The discipline it imposes is purely architectural: nothing dynamic may ever be interleaved into the static blocks.
- Scene-scoped {{MEANING_MAP}} injection. Already designed as a toggle in build_spec §6, never exercised: inject the Level-1 whole-passage prose always, plus only the current scene’s prose and the not-yet-engaged elements — instead of the full map. A smaller Guide prompt is a faster Guide call on every turn, and the pedagogy is unaffected because the session moves scene by scene anyway. (It composes with caching: the prefix becomes per-scene, which still amortizes across the many turns each scene takes.)
- Validator material diet as the default, not the fallback. Build_spec §6 says to prefer FOR_MODEL + the high_risk_register_audit entries over the prose “if length forces a choice.” Make that the standard content of the Validator’s {{MEANING_MAP}} slot: the structured spine is what makes claims checkable, the audit carries the hard constraints, and dropping the prose shrinks the second serial model call on every single turn — with the prose available as an opt-in for pericopes where a grounding dispute actually needs it.

A coverage proposal, from asking where an uncovered element is actually solved. Today it is discovered in app code (the tracker + classifier), communicated through the prompt (the REMAINING list), and solved only at the Guide’s discretion — the instruction is to “naturally raise” what remains. The backstops (the final-rehearsal gate, the completion floor) can block a session from completing, but nothing drives the leftovers to resolution.

- An explicit remainder sweep before the final rehearsal. Is this not what beat 5 (“raise the quiet things”) already does? Same goal, different enforcement layer: beat 5 is an instruction to the model — discretionary (“as they fit, at the right moments”), scoped to the quiet things, and unchecked. The sweep is to beat 5 what the Validator is to the Guide’s containment instruction — the system’s own principle of “enforced by architecture, not by hope,” applied to coverage. When the scene loop finishes but REMAINING is non-empty, have the app — not the Guide’s judgment — switch the coverage-status injection into a closing-sweep mode: only the leftover elements, one per turn, each with its map prose attached and an explicit instruction to open it and hand it to the team now. The team never sees a checklist (the doctrine holds — no lists announced); what changes is that the sweep becomes a deterministic stage of the session instead of a hope distributed across turns. Pair it with two small mechanisms: a re-surface counter — an element surfaced twice without the team engaging makes the status line tell the Guide to change strategy (stop mentioning it, invite a rehearsal of that element directly); and stall telemetry — log which elements chronically finish last or stall across sessions, per pericope. That log is map-improvement signal of the same kind the fail-safe firings already provide: an element teams never engage on their own is an element whose prose, position, or teaching cue in the map needs work.

An app-side proposal for choosing the passage — the counterpart of the Mesa’s “convene” proposal (see the Mesa artifact §6). When the facilitator prepares more than one passage, the team still needs a way to choose — wordless, and nearly weightless.

- As contas preparadas — a spoken choice among the facilitator’s pre-selection. The Mesa prepares up to four passages; each appears as a bead on a short cord. The recommended one (the facilitator’s ordering) breathes gently — a team that simply taps the breathing bead and then the entry bead has made zero decisions and done exactly two taps, the same two the whole app already taught. Tapping any other bead has the voice name it aloud before entering, so identification never requires a single written word. With one passage prepared this screen never appears (it degenerates into the Mesa-convenes flow), and with none the app falls back to canonical order — the choice screen exists only when a real choice exists, which is the deepest way to keep cognitive load down.

An interaction proposal, from watching the state machine: a turn costs two taps, and they are not equally justified.

- One-tap turns — tap to address, assisted stop with a tap escape hatch. The first tap (invite → listening) is an addressing gesture and should stay: in a room where most speech is deliberately not for the machine — the team rehearsing among themselves is the most protected activity in the design — the system must never guess the addressee from an open mic. The second tap (listening → thinking) only says “I’m finished,” and finishing is something audio can often detect. Proposal: keep tap-to-address; while listening, run silence detection with a generous threshold (5–8 s, not a voice assistant’s 700 ms), tuned to the failure asymmetry — waiting a few extra seconds costs nothing, but cutting off a team member mid-retelling breaks the Guide’s spoken promise (“Eu escuto até o fim”) and produces a truncated telling the Guide will then wrongly “correct.” The tap remains as a force-stop accelerator, so nothing new is taught and the current behavior stays available. Make the threshold context-aware — short for the retro’s scripted “falar” answers and confirmations, long when the Guide just invited a retelling (the app knows which kind of turn it asked for) — and ship it as an assist to tune with a real team: if field testing shows the auto-stop firing inside oral-culture thinking pauses, raise the threshold or drop the feature, and nothing was lost because the tap never left. (The precedent is already in the design: the back-translation flow’s clip auto-resume removes an interaction exactly where context makes the addressee certain.)

## §10 The prompts, verbatim

The eight files in prompts/ at branch codex/fix-internalization-reliability, commit 65ec920 (PR #9) — the latest pushed version. For each model role the block below carries the exact system-prompt text the system injects (the engineering notes around the markers are summarized in the table); the fail-safe file is application strings, included whole. The {{PLACEHOLDERS}} are the runtime injection slots described in section 2.
