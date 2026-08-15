# gauge style guide — semantics

This is the *semantic* style guide: rules about what the code means, how
failure is represented, and how design intent is signalled. It is not the
formatting guide — alignment, spacing, and `::` conventions live in
`AGENTS.md`.

Everything below hangs off one idea:

> **Every failure mode has exactly one home.**

## 1. Panics are compiler bugs; errors are source bugs

- `panic` means the **compiler** is wrong:
  - a violated invariant,
  - out of memory.
- `ok = false` (with a message on the receiver) means the **source program**
  is wrong — or the compiler has not implemented the feature yet. An
  unimplemented path reached with valid input returns an error that says so
  plainly: "Procedure declarations are not implemented yet (byte 8)".
- A valid program that reaches an unfinished path reports that as an error,
  not a panic (ARB 0001): the Odin test runner cannot survive a test that
  panics, and the re-enabled slice tests assert the target shape, so a
  "not implemented yet" error cannot ship past them.
- **Never panic for "not implemented".** A message like the one above looks
  like a real diagnostic; the slice tests are what stop it shipping — they
  fail until the feature exists.
- The "not implemented yet" returns are the roadmap: searching the codebase
  for `not implemented yet` lists every piece of unfinished work. A parser
  is done exactly when that search is empty.
- A panic is a bug report against the compiler — never against the user's
  program.

## 2. Error representation and propagation

- Parse functions return `(value: T, ok: bool)` with **named returns**, so
  `or_return` can propagate a failure in one line.
- The error message lives on the receiver (`Parser.err`); only the public
  entry point (`parse`) surfaces it as a third return.
- A syntax error that is *reportable* is a value even if the current pass
  cannot recover from it. Recovery is a later feature; representable errors
  are a property of the interface, not of the implementation.
- Diagnostics are grammatical sentences: capitalised, positions reported as
  bytes. The house template is `Expected X at byte N, got Y` — e.g.
  `Expected an expression at byte 12, got Star`. The one deliberate
  exception is a not-implemented error: "X is not implemented yet (byte N)"
  — the source is valid, so "Expected" would blame the program for the
  compiler's gap.
- Retrofitting failure handling is the most expensive thing to add later, so
  the `(T, bool)` shape is used by every parse function from day one — the
  one place we build ahead of the slice.

## 3. Structure first; stubs are the roadmap

- Write callers before callees. The dispatch and the contracts are the
  skeleton; the leaf machinery fills in behind them ("wishful thinking").
- A stub returns an error naming the feature it belongs to — e.g.
  `p.err = "Call arguments are not implemented yet (byte …)"` — so the
  search from section 1 is self-documenting.
- A stub error is honest about the source being valid: never phrase it as
  "Expected … got …", which would blame the program for the compiler's gap.
  The re-enabled slice tests pin the target shape, so a stub cannot pass
  tests silently.

## 4. Comments say why, never what

- Restating the code is noise that rots on the next edit. The *constraint*
  the code obeys — the invariant, the trade-off, the deliberate choice — is
  the only thing worth writing down.

## 5. Design notes: `@Note` and `@Review`

- `@Note` flags an open question or a deliberate decision at the site that
  matters. An open note is either "this is deliberate, here's why" or "this
  is pending, here's what" — never both silently.
- Resolving a note adds a `// @Review:` line recording the decision. A
  reviewed note needs no further attention on later commits.

## 6. No speculative machinery

- Build the grammar and the code in vertical slices: the shape of the next
  feature is decided when it is implemented, not when it is imagined.
  `arg-list` and `-> ReturnType` are future slices; they get no structure
  today.
- The one exception is the error interface from section 2, because failure
  handling is the one thing that is genuinely expensive to retrofit.

## 7. Magic numbers have one home

The opening principle generalises: failure modes have one home, and so do
numbers.

- A magic number may stay a number — some values are judgements, not
  constants from nature. The unary floor 25 is headroom, not a law of
  physics; what matters is that it lives in exactly one place.
- Every magic number is owned by exactly one named lookup or constant:
  `unary_binding_power` owns the unary floor, `binding_power` owns the binary
  pairs. Callers consult the owner; they never re-type the value.
- The owner is the authority. Changing the value is a one-line edit at the
  home, and every caller follows it without a second review.
- A literal that appears once is not a problem. A second occurrence is the
  beginning of drift: the two copies will disagree the first time the value
  changes. When you find a duplicate, fold both call sites behind the lookup
  before a third appears.
