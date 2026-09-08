# The room stays wordless, and CI enforces it

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
