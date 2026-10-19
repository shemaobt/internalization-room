---
status: accepted
date: 2026-10-19
amends: 0064 (in part: a held session of another book)
---

# The tablet reads its books from the room, and each book's Panorama is opened by its own id

This amends ADR 0064 without editing its decision; it adds "amended by 0091" to its status
line. Settled on the ticket (ENG-1248), 19 October.

## Context

The tablet named one book, Ruth, in one string, on the theory that another book would be a
config change. It read that book's list, opened the Panorama by the alias `OV`, which the
server resolves to Ruth's, and keyed every Resume point and the Current session by that
string. The room now serves three books (Esther, Jonah and Ruth), lists them at `GET /books`
in its own order, and names each book's Panorama `OV-<Book>`.

## Decision

- **The served books are the room's.** The Wheel is every served book's list, concatenated
  in the order `GET /books` gives. One failed read, of the books or of any one list, is one
  failed Wheel: no partial menu is shown.
- **The tablet never names a book.** A passage's book is its Wheel entry's, or on a relaunch
  the held record's; the Resume points and the Current session are keyed by it, so Ruth's
  keys do not move. A held session is landed whatever its book: the room's answer decides
  whether it still exists.
- **A Panorama is opened by its entry's id,** never by the alias. The machine's choosing
  event and the Panorama Station carry that id. A Panorama session is reused only for the
  same Panorama in the same language, and a passage opened after a Panorama names it as the
  session before only when it is the Panorama of the passage's own book.
- **Under a halt the Choice opens nothing:** opening the room asks the room nothing while the
  team needs a person.

## Considered Options

**Fall back to Ruth's list when the room answers `GET /books` with a 404.** Rejected: the
deploy order covers it (the server ships the route first), and a fallback would hide a
server without the route behind a tablet that looks like it works.

**Keep one Panorama session per book.** Rejected for now: the server reads only the
Panorama session immediately before a passage, so a slot per book would hold sessions
nothing asks for.

## Consequences

- The `OV` alias and the tablet's book setting leave the tablet. The server keeps `OV` as
  Ruth's for tablets not yet updated.
- A Resume point, being keyed by a book the room names, follows the room if it ever renames a
  book.
