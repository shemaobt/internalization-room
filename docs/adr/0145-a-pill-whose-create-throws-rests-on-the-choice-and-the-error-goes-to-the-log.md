---
status: accepted
date: 2026-10-28
amends: 0137 (in part: a thrown error before the session is held is an open that brought no session), 0125 (in part: an `Error` under a pill's open, before its session, raises no sign)
---

# A pill whose create throws rests on the Choice, and the error goes to the log

This amends ADR 0137 and ADR 0125 without editing their decisions: it adds "amended by 0145"
to their status lines. Her app is the bar: the open's request and its reading are wrapped in
`.catch(() => null)` (`app/page.tsx:778-779`), so anything thrown is an open that answered no
session (`:786`), and the Panorama goes through the same open (`:980-981`).

## Decision

- **An `Error` thrown by a pill's open before its session opens is an open that brought no
  session.** The passage pill and the Panorama pill both rest on the Choice as ADR 0137
  decided for every other failure: the entries live, nothing said, no sign, and the next tap
  on the same pill asks again. With a passage left waiting under the Choice, it is laid back
  as ADR 0143 decided, asking the room for nothing more.
- **It still reaches the operator's log, once.** The team sees and hears nothing of it; the
  error and its stack are written as ADR 0125's report writes them.
- **Once the session is held, an `Error` raises the sign as before.** ADR 0137's «a thrown
  error still raises the sign» now holds only after the session opens.
- **Unchanged.** Every way into a passage that is not a pill (the way back, the left entry's
  own pill, a tap on a Canvas or Panorama with no session, the sign cleared, the launch) keeps
  ADR 0125's sign for an `Error`, and an `Exception` keeps the failure policy's own path.
