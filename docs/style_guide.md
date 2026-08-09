# londolang style guide — semantics

This is the *semantic* style guide: rules about what the code means, how
failure is represented, and how design intent is signalled. It is not the
formatting guide — alignment, spacing, and `::` conventions live in
`AGENTS.md`.

Everything below hangs off one idea:

> **Every failure mode has exactly one home.**

## 1. Panics are compiler bugs; errors are source bugs

- `panic` means the **compiler** is wrong:
  - an unimplemented path reached with valid input — `panic("todo: …")`,
  - a violated invariant,
  - out of memory.
- `ok = false` (with a message on the receiver) means the **source program**
  is wrong.
- A valid program that reaches an unfinished path is a compiler bug, so it
  panics. An invalid program that reaches a finished path is a source bug, so
  it returns an error.
- **Never report "not implemented" as an error value.** A message like
  "procedures not implemented yet" looks like a real diagnostic, can ship by
  accident, and passes tests. A panic cannot.
- The panic sites are the roadmap: searching the codebase for
  `panic("todo` lists every piece of unfinished work. A parser is done
  exactly when that search is empty.
- A panic that is not a `todo` is a bug report against the compiler — never
  against the user's program.

## 2. Error representation and propagation

- Parse functions return `(value: T, ok: bool)` with **named returns**, so
  `or_return` can propagate a failure in one line.
- The error message lives on the receiver (`Parser.err`); only the public
  entry point (`parse`) surfaces it as a third return.
- A syntax error that is *reportable* is a value even if the current pass
  cannot recover from it. Recovery is a later feature; representable errors
  are a property of the interface, not of the implementation.
- Retrofitting failure handling is the most expensive thing to add later, so
  the `(T, bool)` shape is used by every parse function from day one — the
  one place we build ahead of the slice.

## 3. Structure first; stubs are the roadmap

- Write callers before callees. The dispatch and the contracts are the
  skeleton; the leaf machinery fills in behind them ("wishful thinking").
- A stub is `panic("todo: parse_proc")` — naming the proc it belongs to, so
  the search from section 1 is self-documenting.
- Do not smooth over a stub with a plausible error message. That borrows
  against a diagnostic that does not exist yet — and borrows it wrong.

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
