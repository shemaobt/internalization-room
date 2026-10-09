# The room stays wordless, and CI enforces it

Amended by ENG-1250 (her moment label): the conversation screen writes the moment the voice
named — «Familiarização · a passagem inteira», «Internalização · cena 2 de 4» — as Marcia ruled
it on 2026-09-24 («A palavra está sempre escrita», D8 (a)). It is the second named exception,
and the only one the **Team** sees; its words are hers, and it reads the same through
VoiceOver.

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
