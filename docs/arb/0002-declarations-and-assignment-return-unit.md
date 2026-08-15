# ARB 0002 — Declarations and assignment return unit

**Status:** Accepted
**Date:** 2026-08-15

## Context

The everything-is-an-expression doctrine (docs/design.md, spec/language.md)
says nothingness is expressed as unit, but the value of *binding a name* and
of *assigning* was never pinned — it stayed an implication. A comparative
pass over the alternatives made the options concrete:

- **C** — assignment is an expression returning the assigned value
  (`y = x = 5` chains); declarations are a separate category.
- **C++** — assignment is an *lvalue* expression (it denotes the assigned
  object: `(x = 5) = 6` and `&(x = 5)` are legal); declarations are
  declaration-statements with no value at all — not even unit.
- **Pascal** — `:=` is the archetypal value-less statement; functions and
  procedures are two kinds of callable, encoding value/no-value in the
  grammar.
- **ML/OCaml** — `let x = 5 in e` is a value-threading expression (its value
  is `e`'s) with explicit one-expression scope; `r := 5` mutates a ref and
  returns unit.

## Decision

1. **Declarations are expressions returning unit `()`.** const
   `name :: expr`, variable `name := expr`, typed variable
   `name : Type = expr` — the binding is the effect; the expression's own
   value is `()`. A block's value is its last expression, so a block ending
   in a declaration is unit — a documented subtlety, not an accident.
2. **Assignment returns `()`** — the deferred `=` arm will not chain:
   `a = b = c` is dead. C's value-returning and C++'s lvalue-returning
   assignment are rejected: chaining is the idiom that drags in the
   value-category machinery the design refuses.
3. **No `void`, no function/procedure split.** Nothingness is the unit
   value; a procedure is just an expression of type `()`. (The `()` literal
   itself is still deferred — the `Unit` node exists and `()` is a source
   error today — the doctrine concerns the values of constructs, not the
   literal.)
4. **No value-category taxonomy.** There are no lvalues: names bind
   declaratively and effects return unit, so the C++ lvalue/rvalue
   machinery — built to serve mutation, references, copy/move, and
   overloading — has nothing to grip.

## Why blocks, not `let … in` (scope is ambient, deliberately)

Flat block scope with implicit continuation was chosen over OCaml's
`let … in` (explicit one-expression scope, value-threading). The trade:
readability — bindings laid top-to-bottom, no `let`-pyramid, no `;` — at
the cost of explicitness: a binding's reach is the rest of the block, so
shadowing and order-sensitivity rules carry the burden (docs/scoping.md).
The scoped/defer model also *needs* blocks as scopes; `let … in` scoping
does not compose with a block-scoped cleanup construct.

## Consequences

- **Discard is implicit and cheap.** A bare call's value evaporates at the
  newline; there is no value-discarding production to define and no `;`
  to remember. The counterweight: the value of a fallible call is silently
  droppable, which collides with the `(T, bool)` gate idiom. The discard
  vocabulary and the fallibility shape are OPEN — see below.
- **Block value subtlety.** A block ending in a declaration or assignment is
  unit; the block-value rule must document this.

## Open — fallibility shape and the discard policy

Is `(T, bool)` the right gate, or should a begin procedure communicate
fallibility through a specific return type? The discard policy rides on the
answer. Session convened 2026-08-15; the shape under discussion so far:

- `_` is the universal discard — a black hole that binds nothing. Any
  number may appear in one binding (`_, _ = f()` is legal), and it can
  never be referenced: there is nothing to bind, so using `_` where a
  value is expected is an error by construction, not by rule.
- `_<name>` is a discard *with context*: it binds, fires no unused warning,
  and the name tells the reader what is being thrown away (`_ok`, `_err`).
  **A use is any mention**: any occurrence of the name in the scope after
  its binding — a read, an argument, a reassignment (`_count = 3`) — draws
  a warning that it is not discarded. The prefix is a truthfulness signal
  ("don't build on this"), so the fix is to rename it to `<name>` and let
  the code show, at a glance, that the value is relied on.
- **`:=` is not a token** — it is `:` `=` with an empty type slot:
  `x := expr` reads `x : = expr`, the inferred declaration, the variable
  analogue of const `x :: expr`. It declares a fresh name only; a
  pre-declared name is a redeclaration error, with one exception: `_`
  binds nothing and may be redeclared freely — `:=` can only "assign to"
  the discard. `=` assigns to any pre-declared name and is the initialiser
  in the typed form `x : Type = expr`. The `_` slot works with both forms
  (`_, _ = f()` and `_, ok := f()`).
- **The discard never needs declaring.** `_` slots bind nothing in any
  form — declaration or assignment, single or multi-binding
  (`_, y = f()` assigns the second return to a pre-declared `y`) — so
  there is nothing to declare, as it is never used.
- **Shadowing.** Names are block-scoped. Same-scope redeclaration is an
  error; an inner scope may shadow an outer name, but the shadow draws a
  warning. The opt-out tag is deferred with the language's whole tag
  system — no tag decisions are made in this session.

## Alternatives considered

- **C value-returning assignment** — rejected: chaining; no
  value-category-free formulation.
- **C++ lvalue-returning assignment** — rejected: requires the taxonomy.
- **Pascal value-less assignment as a separate category** — rejected: a
  second grammar category is the doctrine's whole point to avoid.
- **OCaml `let … in` scoping** — rejected (see "Why blocks"); ML's unit for
  `:=` mutation adopted in spirit — unit for effects — while gauge's `:=`
  binds rather than mutates.
