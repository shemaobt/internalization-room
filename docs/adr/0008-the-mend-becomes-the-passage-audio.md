# The mend becomes the passage audio

## Context

After a **Mend**, the room could either keep playing the right **Take** per **Stretch** or
hand back a rebuilt recording of the whole part. The product owner asked repeatedly for the
second: what the team hears afterwards should be the story, not a seam.

## Considered Options

Per-stretch playback alone. Rejected on product authority rather than on a technical
argument — it is wrong for the person listening.

## Decision

On a replacement the server composes a new **Composed passage**: the original with the
wrong **Stretch** cut out and the mended one in its place, with every segment of that take
re-addressed to recomputed starts and ends. The tablet installs it under the part's own
scope, so the part becomes the passage it rebuilt, and from there the mended stretch is a
slice of its part exactly as its neighbours always were.

## Consequences

Composition never blocks: when it fails, the room degrades to playing the right take per
**Stretch**, which is the behaviour this decision replaced. A cold resume maps the composed
take back to its part by the number the tablet sent that part up with, and without that
listing it swaps nothing. The composition itself is an audio re-encode measured at eight
seconds, and a **Stretch** whose place is known but whose file never arrives counts as told
rather than stopping the team.
