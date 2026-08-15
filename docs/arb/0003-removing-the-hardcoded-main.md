# ARB 0003 — Removing the hardcoded main: FFI, proc emission, and the parser decisions

**Status:** Accepted
**Date:** 2026-08-15

## Context

The demo's C output is finished by hand in `main.odin`: the generated C
carries only consts, and a hardcoded C `main` wraps them, printing the
`Print` const with `printf`. Gauge source cannot say what a program *is* —
there is no way to declare `main`, no typed parameters, no calls. The next
vertical slice is the one that lets gauge programs stand on their own: the
hardcoded `main` comes out of `main.odin`, and the gauge source declares
it. The path, in order:

1. **Typed parameters** — `parse_params` grows the `name : type` list.
2. **Calls (positional)** — the `(` infix arm and `parse_args`.
3. **FFI + procedure emission** — procs emit as C functions; every call
   is a C function call; the hardcoded `main` is deleted; the demo
   becomes a gauge `main :: proc()` that calls `printf`.

## Decision

1. **`void main`.** Gauge procs have no return type (returns are deferred
   wholesale), so the emitted C `main` is `void main(void)` — the *same*
   shape as every other emitted proc (`void name(params) { ... }`). No
   special rule for `main`. Revisited when the multiple-return-values
   card lands `-> int`.
2. **Trailing commas are rejected** — `proc(x : int,)` and `f(a,)` are
   parse errors. Multi-line lists stay legal: the comma before the line
   break, and the parens are zones (§11.16). The LBNF `[Param]`/`[Arg]`
   lists are this by construction.
3. **The proc's own type slot stays discarded.** `main : int :: proc()`
   parses (the type slot is consumed, as today) but is dropped from the
   AST; result types land with the multiple-return-values card.
4. **FFI: every call is a C function call.** Until name resolution lands,
   `Call` emits straight to C — `printf(...)` compiles through, and gauge
   procs cannot call each other. `#include <stdio.h>` stays hardcoded in
   `main.odin` for this slice.

## Why now

The hardcoded `main` is the last handwritten piece of the demo — gauge
source decides nothing about the shape of its own program. Parameters and
calls are the parser prerequisites, and each is a small, self-contained
slice that lands green with its spec. The FFI is the cheapest interop that
makes the demo real: no header parsing, no name resolution, no foreign
declarations.

## Alternatives rejected

- **`int main` with an injected `return 0`.** The C standard mandates
  `int main`, and gcc/clang warn on `void main` (MSVC accepts it
  silently). Conformance was the only argument, and it costs exactly the
  special rule being avoided: codegen would have to recognise `main` and
  emit a return it never read. Gauge has no returns yet — `void` is the
  *only* rule, not a concession. The warning is benign; the e2e tests
  assert exit code and stdout, not warnings.
- **Real FFI (parsed headers, foreign declarations)** — deferred until the
  semantic checker's name resolution; "all calls are C" is the seam in
  between.
- **A keyword-free `main` (`main :: () { }`)** — already refused by the
  `proc` keyword decision (language.md §11.1): `x :: (4 + 2) * 3`
  (grouping) and `main :: (x) { }` (proc) are indistinguishable without
  the keyword.

## Consequences

- **A gauge file without `main` fails at the cc link step** with cc's own
  message — acceptable for now, flagged in the FFI commit.
- **Gauge procs cannot call each other** until resolution lands; codegen
  emits consts first (dependency order), then procs in declaration order,
  so proc bodies can reference emitted consts but not other procs.
- **The codegen grows a runtime emitter** distinct from the const-fold
  `resolve_expr`: proc bodies emit identifiers verbatim (they reference
  the emitted `static const`s), params ride a small type-name map
  (`int`→`int`, `f64`→`double`, unknown names verbatim, `^T`→`T *`), and
  strings pass through verbatim between quotes — gauge escapes coincide
  with C's and strings are line-constrained, so no raw newline leaks into
  the literal.
- **The two e2e tests' hand-rolled wrapper `main`s go away** — the
  generated C ships its own `main`; the tests' gauge source gains a
  `main :: proc()`.

## Open

- The multiple-return-values card reopens `main`'s shape (`-> int`?).
- Real FFI (declared foreign functions, headers) lands with the semantic
  checker.
