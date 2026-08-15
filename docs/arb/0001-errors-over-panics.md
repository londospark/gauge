# ARB 0001 — Unimplemented parser paths return errors, not panics

**Status:** Accepted
**Date:** 2026-08-14

## Context

The re-enabled slice tests (`test_parse_empty_proc`, `test_parse_proc_body`,
`test_parse_multiline_group_inside_block`, `test_parse_multiline_args`) pin
the target parse shapes for the blocks/procs/calls cards. Under the old
doctrine (style guide §1), an unimplemented path reached with valid input
panicked — so each test that parsed `main :: proc() { }` died in
`parse_decl` with `panic("todo: Procedures not implemented yet")`.

The Odin test runner cannot survive that. A single panicking test is
recovered and reported; a run containing **two or more** panicking tests
hangs (1 thread) or crashes (2+ threads, NTSTATUS `0xC000009D`). Reproduced
on the local `dev-2026-07` nightly and the latest prebuilt nightly
(`dev-2026-08`) as of 2026-08-14, with a minimal two-test repro that does
not involve this codebase. There is no per-test filter to dodge the
panicking tests and no recover for a test to absorb a panic, so a suite
containing them cannot complete: no report, no JUnit, a CI timeout.

## Decision

In the front end, an unimplemented feature path returns `(nil, false)` with
an honest message on `Parser.err` — "X is not implemented yet (byte N)" —
instead of panicking. Panics remain for true compiler bugs: violated
invariants and out of memory.

Sites converted:

- `parse_decl` proc dispatch — "Procedure declarations are not implemented
  yet"
- `parse_block` — "Blocks are not implemented yet"
- `parse_args` — "Call arguments are not implemented yet"
- `parse_infix` — new error arms for the deferred `.Equals` and `.LParen`
  rows ("Assignment …" / "Call expressions …"), replacing the trip through
  `to_binary_operator`'s invariant panic

`to_binary_operator` and `to_unary_operator` keep their invariant panics;
they are unreachable for the deferred operators because `parse_infix`
rejects those rows first. §11.14's property — "a future `x = 5` fails
loudly instead of silently parsing as `x + 5`" — is preserved; it fails
politely rather than loudly.

## Why this is safe

The old doctrine's guard was "a panic cannot pass tests". The new guard is
the re-enabled tests themselves: they assert the *target* shape (parse
succeeds, a specific AST), so a stub that ships by accident fails them
loudly. A "not implemented yet" error value cannot pass a test that demands
the implemented parse.

The roadmap mechanism moves with it: `rg "not implemented yet" compiler/`
replaces `panic("todo` as the list of unfinished work. A parser is done
when that search is empty. TODO.md remains the status board.

## Consequences

- `docs/style_guide.md` §1–§3 and `spec/language.md` §8 are updated to the
  new doctrine; §11.14's resolution text names the new mechanism.
- The re-enabled tests fail as ordinary test failures — the point of this
  record — and turn green as their slices land. `test_parse_empty_proc` and
  `test_parse_multiline_group_inside_block` went green with the blocks/procs
  slice; `test_parse_proc_body` and `test_parse_multiline_args` re-enable
  with the calls/assignment card (Equals arm, call infix arm).
- A "not implemented yet" message could be mistaken for a real diagnostic
  if the tests were ever disabled again — the exact hazard the old doctrine
  existed to prevent. Mitigation: the tests stay enabled, and the message
  text is honest about being transitional.

## Alternatives considered

- **Keep panics, keep the tests disabled** until each slice lands — loses
  the live RED documentation the tests provide while a slice is being
  built.
- **Keep panics, re-enable the tests anyway** — breaks the runner; rejected
  on the evidence above.
- **Fix `core:testing`** — out of scope for this repo, but worth reporting
  upstream: the runner should recover per-test panics. Not something the
  schedule can wait on.
- **Implement the features now** — that is the slices' job, not this
  decision's; this record only makes the failure mode reportable.
