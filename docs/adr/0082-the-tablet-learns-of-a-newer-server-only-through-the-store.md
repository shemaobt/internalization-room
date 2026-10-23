---
status: accepted, amended by 0124
date: 2026-10-13
---

# The tablet learns of a newer server only through the store

## Context

A tablet runs the build installed from the store, and the server is deployed on its own
schedule. Nothing on the tablet asks the server which build it accepts, so an older tablet
meeting a newer server learns of it only when something fails. Two questions followed: does
the tablet get a compatibility check, and what keeps a deploy from landing in the middle of
a **Session**.

## Decision

The tablet relies on store updates alone. It carries no compatibility check against the
server and none is built now.

A deploy of the server waits while a team **Session** is open, as the server's CI notes have
said since ENG-1463: a **Session** in progress on a passage, not on the **Panorama**, whose
**Team** did something in the last hour. A manual run marked urgent skips the wait, and after five hours
of waiting the deploy fails and nothing ships. The staging deploy never waits. This decision
changes none of that.

The vendored doctrine, section 5.4, says: "During pilot session hours the deployment is
frozen; fixes land between sessions." The hold is narrower than that frozen window: an urgent
run skips it, a **Session** on the **Panorama** never holds, and a **Team** idle for an hour
stops holding. This ADR accepts that, by Henok's decision to rely on the store and the
Definer's ruling that the hold is not widened.

An older tablet against a newer server is a risk accepted until the later check exists. The
server's CI notes also say the corollary: a server change the installed build cannot speak
ships only once the store build that speaks it is on the tablets.

## Considered Options

A check of the tablet's build against the oldest build the server accepts, refusing the
older ones with a prompt to update. Not built now: the tablets are frozen on 2 November, the
deploy hold already keeps a deploy out of an open **Session**, and Henok chose to rely on
the store.

## Consequences

The compatibility check is its own ticket, to be opened when Henok brings it.

The hold leaves a gap: a **Session** whose **Team** has been idle for more than an hour does
not hold a deploy, and a **Session** on the **Panorama** never does. A tablet in either state can
meet a newer server mid-**Session** and may fail there. A **Team** can also turn active
after the hold clears and before the migration and the deploy finish.

Whoever deploys a server change that older tablets cannot speak must wait for the store
build; nothing automatic enforces it.

ENG-1377 (ADR 0124) builds the minimum-build check this ADR deferred; it is the one exception, raised by hand at a release.
