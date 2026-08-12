# Semantic checking: the type system for gauge

This is the design for what happens *after* the parser: the semantic
checker — name resolution, type inference and checking, and constant
folding. Nothing here is implemented yet; this is a design document, not
an implementation plan, and it lands ahead of its code the same way
[scoping.md](scoping.md) and §11.16 did. The build order is recorded in
§10; the spec changes land with the code, not with this doc.

> The parser lays the track; the checker sets the points. A train that
> clears the grammar still has to clear the signalbox before it runs.

The term "semantic checking" is gingerBill's — the Odin compiler has a
`checker/` package between `parser` and `codegen` that does exactly this
work: name resolution, type inference, type checking, and constant
evaluation. gauge mirrors that shape. The front end (lexer + parser)
builds *structure*; the checker builds *meaning*.

## 1. What semantic checking is, and where it sits

The pipeline:

```
lex → parse → resolve → type → fold → [codegen]
```

Each pass does only what the information it holds permits (design.md,
principle 5 — *do work only where the information lives*):

| pass      | has the information to…            | deliberately does not…                |
|-----------|-----------------------------------|---------------------------------------|
| lex       | split bytes into tokens           | know grammar or types                 |
| parse     | build AST structure               | resolve names or assign types         |
| **resolve** | bind `Ident` nodes to declarations | evaluate or type anything             |
| **type**  | infer and check types             | evaluate constants                    |
| **fold**  | evaluate constants                | restructure the program               |

The promise the parser already makes — that `Number.value` stays raw
text and "conversion to a typed value happens in the constant-folding
pass" (spec §3.3) — is cashed here. The literal `1` is text through
parse and resolve; it gets a type in the **type** pass and a value in
the **fold** pass. Forward const references (spec §5.2, §11.3) are the
same story: the parser never resolves names, so resolution must not
assume source order, and cycles are diagnosed at fold time, never as a
hang or a panic.

The checker is the first pass where "everything is an expression"
really earns its keep: blocks type as their last expression, `if`
branches unify, calls type against signatures. It is also the pass
where the `(T, bool)` idiom the scoping design leans on gets its
foundation — see §4.

## 2. Name resolution

Before any typing, names must resolve. The parser emits `Ident` nodes
that carry only a name; resolution binds each to the declaration it
refers to.

- **Scopes come from blocks.** A block is both a value and a scope
  ([scoping.md](scoping.md)); the resolver builds a scope tree from
  block nesting and looks up names up the chain. Proc parameters and
  the deferred `it`/`ok` bindings of `scoped` blocks are scope entries
  too.
- **Forward const references force two phases.** `GiB :: 1024 * TiB`
  is legal with `TiB` declared later (§5.2, §11.3), so resolution
  cannot be a single linear pass. It collects all declarations first,
  then resolves bodies — the same constraint the spec already places on
  the constant-folding pass ("must not assume source order"). A cyclic
  chain (`A :: B; B :: A`) is a source error diagnosed at fold time,
  never a hang or a panic.
- **Shadowing** — whether an inner binding may shadow an outer one, and
  how strictly, is left open for the implementation slice. The lean is
  to allow shadowing in nested scopes (the Wirth/Odin default) and
  refuse it only where it has bitten us.
- **`_` discard** — the discard binder (backlog) interacts here: `_`
  names no binding, so `_` in a multi-return position (§4) drops a
  value without entering the scope.

Resolution produces a resolved AST (or annotates the existing one —
§9). Unresolved names are source errors: `Name TiB is not declared at
byte N`.

## 3. The type system: Hindley–Milner with value restriction

**Decision.** gauge uses Hindley–Milner-style bidirectional type
inference with **let-polymorphism generalised only at immutable
constants**, restricted by the value restriction. Mutable variables are
monomorphic. Procedure signatures are explicitly typed.

**Why HM.** Unification-based inference gives the ergonomic win the
language wants — you write `MiB :: 1024 * KiB` and `scale :: 2.5`
without restating types — and it does so principled. HM also gives a
clean foundation for the deferred generic-proc feature: a polymorphic
proc is just a const generalised over its type variables.

**Why not full HM.** Full Damas–Milner generalises at every `let` and
is unsound in the presence of mutation — the *value restriction*
problem from ML. gauge plans both immutable consts (`x :: expr`) and
mutable vars (`x := expr`, `x : Type = expr`). The clean split:

- **Consts generalise.** `x :: expr` is an immutable binding to a
  value, so its type may be generalised over free type variables
  (subject to the value restriction — the RHS must be a
  non-expansive expression, not one that allocates mutable state).
  This is where polymorphic procs and, later, generic procs get
  their footing.
- **Vars never generalise.** A mutable binding's type is fixed at
  its initialiser and stays monomorphic. Generalising it would let
  two reads through the same variable observe different type
  instantiations — the classic unsoundness.
- **Proc signatures are explicitly typed.** Every systems language
  annotates procedure parameters and return types; unannotated
  recursive proc params are where HM inference goes undecidable-ish,
  and exported signatures are documentation. Inference stays local
  to bodies and const RHSs.

**No subtyping.** Types are nominal. `Celsius` and `Fahrenheit` are
distinct types even if both are `distinct f64` (§5); neither is a
subtype of the other, and neither is a subtype of `f64`. The one
flexibility is **literal typing** (below), which is unification, not
subtyping. No ad-hoc overloading either — consistent with *one obvious
way* (design.md) and with HM, which has no overloading by construction.

**The concrete first win: literal typing.** `Number.value` is raw text
(spec §3.3). A literal carries a type variable constrained by its
context and defaulted when left free:

```
x : f64 : 1        // 1 has no dot, but unifies against the declared f64 → f64
y :: 1024          // unconstrained → defaults to int
z :: 3.14          // has a dot → f64
MiB :: 1024 * KiB  // 1024 unifies with KiB's type (int)
```

This is exactly the case the parser deferred: the literal's type
*exists* only once the context is known, so the decision belongs to
the **type** pass, not the parser. HM unification is the natural
machinery for it.

**Bidirectional sketch.** The checker runs in two modes — *infer*
(produce a type from an expression) and *check* (verify an expression
against an expected type). Const RHSs with an explicit type slot
(`x : T : expr`) check against `T`; inferred consts (`x :: expr`)
infer. Binary operands infer then unify. A proc body checks against
the declared return list (§4). The mode flows down from annotations
and back up from literals.

## 4. Multiple return values, not tuples

**Decision.** Procedures return a *list* of values. There is no tuple
type.

```
lookup :: proc(key: string) -> (int, bool)
idx, ok := lookup("x")     // multi-binding: idx: int, ok: bool
_, ok := lookup("x")       // discard the first, keep the second
```

- **A return list is a production of the type grammar, not a `Type`.**
  spec §11.4 made the type slot a recursive grammar precisely so
  composites slot in as new productions; the return list is one. It
  appears only after `->` in a proc signature, never as the type of a
  binding. `x : (int, string)` is *not* legal — there is no tuple type
  to write.
- **Multi-binding assignment** consumes a return list positionally:
  `a, b := f()`, `x, ok := ...`. The `:=` and `->` tokens are
  multi-char operators on the backlog; this feature depends on both.
- **`(T, bool)` is this idiom's most common shape.** The scoping
  design's `(T, bool)` idiom — `ok` visible in the body, the
  constructor's `bool` as the gate — is *multi-return*, not a tuple.
  Reframing it this way grounds the idiom in a real mechanism instead
  of a convention. See [scoping.md](scoping.md).

**Why not tuples.** *One obvious way* (design.md): a tuple type would
compete with multi-return for "return two things" and with struct
literals for "group named fields". The Wirth school (Pascal, Modula-2,
Oberon) has no tuple type either; gauge follows that line. Multi-return
covers the real need — returning a value and a flag, or two halves of a
result — without introducing a first-class product type.

**Open.** Two rules to settle at implementation:

- **Multi-return values in single-expression positions.** Go forbids
  using a multi-return call as an operand (`f() + 1` where `f` returns
  two values is an error); gauge likely does the same, requiring the
  values to be bound first. The lean is to follow Go: a multi-return
  call is only legal in a multi-binding context or as the sole argument
  to another multi-return consumer.
- **Block multi-values.** A block's value is its last expression
  (scoping.md). The lean is that a block carries a *single* value;
  multi-return is a proc-call property, not a block property. So a
  block ending in a multi-return call still has one value (the call's),
  which is only usable in a multi-binding context — the same rule as
  above.

## 5. Distinct types

**Decision.** `Celsius :: distinct f64` declares a new nominal type,
distinct from `f64` and from every other `distinct f64`. There is no
implicit conversion to or from the base type; crossing the boundary
takes an explicit cast (§7).

```
Celsius  :: distinct f64
Fahrenheit :: distinct f64

c : Celsius = 100.0      // error — 100.0 is f64, not Celsius
c : Celsius = xx 100.0   // ok — auto-cast to the expected Celsius (see §7)
f : Fahrenheit = c       // error — distinct from each other
```

This is the Wirth school already cited in [design.md](design.md) —
"strong distinct typing" — so it is lineage-aligned, not a departure.
Pascal's "new types" are incompatible; Odin's `distinct` is the same
idea in gauge's spelling.

**Alias vs distinct.** The proposal:

- `Foo :: f64` is an **alias** — `Foo` and `f64` are the same type.
  Useful for documentation and to give a name to a complex type
  expression.
- `Bar :: distinct f64` is a **new nominal type** — incompatible with
  `f64` and with other distincts.

The `distinct` keyword is what draws the line; without it, `::` on a
type expression is a transparent alias.

**Open — operator inheritance.** Do `+ - * /` come with a distinct
type for same-type operands, or must every operator be redefined for
it? The lean, recorded for the implementation slice: **same-type
operands inherit** the base operators (`Celsius + Celsius` is fine and
yields `Celsius`), and **cross-type is refused** (`Celsius + f64` is an
error, even though both are `f64` underneath). This gives
unit-of-measure safety without forcing the user to redeclare arithmetic
for every distinct numeric type — the common case (a type that is "just
an `f64` with a name") stays ergonomic, and the unsafe case (mixing two
distincts, or a distinct and its base) is rejected.

## 6. Discriminated unions

**Decision.** Discriminated unions (DUs) are first-class. They are
needed for real data modelling — option types, AST nodes, result
variants, state machines — and the language already leans on the idea:
the parser's own `Expr` and the token `Value` are Odin tagged unions,
and §11.9 celebrates union-switch exhaustiveness as a feature. User
code gets the same tool.

**Syntax — explored, with a lean.** Two shapes are worked through
here; the implementation slice commits to one.

- **Odin tagged union (lean):**

  ```
  Shape :: union {
  	Circle:  Circle,
  	Square:  Square,
  }
  ```

  Matches the `::` declaration style, the brace body, and the house's
  existing love of tagged-union exhaustiveness (§11.9). A member is a
  tag plus a payload type.

- **ML-style sum:**

  ```
  Shape :: Circle(Circle) | Square(Square)
  ```

  Payload-carrying constructors, closer to the pure HM tradition, but
  it introduces `|` and `()`-as-constructor into the type grammar and
  reads against the brace-bodied declaration style the rest of the
  language uses.

The lean is the Odin form: it reuses the declaration shape gauge
already has, and exhaustive `switch` (below) is the natural consumer.

**The consumer: exhaustive `switch`.** A DU is read with a `switch`
that names every member; omitting one is a compile error unless the
switch is marked `#partial` (§11.9). Each arm narrows the scrutinee to
that member's payload:

```
area :: proc(s: Shape) -> f64 {
	switch s {
	case .Circle:  return pi * s.radius * s.radius   // s narrowed to Circle
	case .Square:  return s.side * s.side            // s narrowed to Square
	}
}
```

**`switch` is a roadmap prerequisite.** `switch` is not on the
backlog today (the control-flow bucket lists `if`/`while`/`return`).
DUs pull it in: a DU without exhaustive matching is half a feature.
Adding DUs means adding `switch` (or an equivalent `match`) to the
expression grammar in the same slice.

**DUs and HM.** Sum types are classical HM — the checker unifies the
scrutinee's type, then narrows it per arm. No subtyping is involved;
the narrowing refines the scrutinee's type within the arm's scope, not
a subtype relationship.

**DUs vs `(T, bool)` — orthogonal, both kept.** This was raised
deliberately: with DUs on the table, does a `Result :: union { T,
Error }` replace the `(T, bool)` idiom the scoping design is built on?
The answer is **no** — they do different jobs:

- **`(T, bool)` is multi-return** (§4) — error plumbing, a convention
  for "a value and a flag". It stays the house idiom; the scoping
  design's `ok` binding and the failure gate ride on it.
- **DUs are data types** — modelling a domain (an AST, an option, a
  state). A `Result :: union { T, Error }` is expressible and may
  suit some APIs, but it is not the default error shape; the language
  does not force every fallible proc into a union.

Both are wanted; neither displaces the other. The doc records this so
the two ideas do not drift into competing error conventions.

## 7. Casts

**Decision.** Two spellings, sharing no token:

- **`xx expr`** — a unary auto-cast: promote `expr` to the type the
  context expects. `xx` is a hard keyword (the §11.2 model — reserved
  where it lexes), and it rides the existing unary binding-power floor
  (style guide §7 — magic numbers have one home; `unary_binding_power`
  owns the floor, and `xx` joins `-`/`+` there rather than introducing
  a second copy).

  ```
  c : Celsius = xx 100.0      // 100.0 is f64; xx promotes to Celsius
  f : f64 = xx my_int         // int → f64, lossless
  ```

- **`cast(Type) expr`** — a manual cast to a specific type. `cast` is
  a hard keyword; the only thing that follows it is `(Type)`, so the
  `(` is unambiguous.

  ```
  n : int = cast(int) 3.14    // lossy narrowing — explicit
  ```

**Why two spellings.** The original idea was a single `xx` token
serving both: `xx expr` (auto) and `xx(Type) expr` (manual), borrowing
the `xx` spelling from Jai. The problem is that a `(` directly after
`xx` is ambiguous — `xx (4 + 2)` (auto-cast a group) and `xx(f64) x`
(manual cast) start the same way, and disambiguating needs either a
checkpoint-and-commit in `parse_prefix` (which §11.1 refused for proc
dispatch) or a position rule that refuses the grouped auto-cast. Two
spellings kill the ambiguity at the lexer: `xx` is *only* the unary
auto-cast (never a type form), `cast` is *only* the type form (never a
bare unary). Position decides role (§11.5) stays clean.

**Lineage, honestly.** The `xx` spelling is borrowed from Jai; the
semantics are gauge's own adaptation — gauge is not cloning Jai's cast
model wholesale. `cast(T)` is Odin's. The doc records the rejected
alternatives so the reasoning is visible:

- **`xx(Type) value`** — retired: the shared-token ambiguity above.
- **Postfix `x as T`** — rejected: it reads against the C lineage, and
  `as` is already informally claimed by `scoped` custom-binding
  (`File as f { ... }`, see [scoping.md](scoping.md) open questions),
  so the token is not free.
- **C-style `(T)x`** — unavailable: `(` is paren-zone grouping and
  `f(x)` is a call (§11.18), so a prefix `(T)` would need lookahead
  the Pratt parser refuses to do.

**Open — the scope of `xx`.** The lean: **`xx` performs only lossless
coercions** — widening numerics (`int` → `f64`), and crossing a
`distinct` boundary to the expected type (`f64` → `Celsius` when the
context asks for `Celsius`). **Lossy or bit-reinterpreting conversions
require `cast`** — narrowing (`f64` → `int`), and any reinterpretation.
A separate bit-reinterpretation operator (Odin's `transmute`, Jai's
bitcast) is deferred to the FFI slice; `cast` covers the checked
manual case until then.

## 8. Diagnostics

The checker's errors are **source errors** (style guide §2): `ok = false`
with a grammatical, capitalised message reporting a byte offset —
`Type mismatch at byte 42: expected f64, got string`. Panics are
compiler bugs (an unimplemented path reached with valid input, a
violated invariant). The house template and the panic-vs-error split
carry straight over from the parser.

**Multi-diagnostic depends on parser recovery.** The parser fails fast
today — the first error is the only error (TODO, "Error recovery and
multi-diagnostic reporting"). A checker built on a single-error parser
would hide half its own type errors behind the first one, so the
checker lands *after* parser error recovery in the roadmap (§10). The
checker itself reports N errors by construction: it walks the resolved
AST and emits one diagnostic per bad node, byte-sorted, the same shape
the parser's diagnostics slice will have.

## 9. Pass structure (implementation sketch)

A `checker/` package, in the parser's image: explicit allocator
threading (no defaults — §11.12), `(T, bool)` + `or_return` returns,
byte-offset diagnostics, a `checker_test.odin` next to it. The three
phases:

1. **resolve** — build the scope tree from blocks, bind `Ident` → decl
   (two-phase for forward refs), detect cycles.
2. **type** — bidirectional inference and checking over the resolved
   AST; generalise consts (value-restricted), keep vars monomorphic,
   unify literals, check proc bodies against return lists.
3. **fold** — evaluate constants whose types are known; convert
   `Number.value` text to a typed value (the §3.3 promise); diagnose
   cycles and non-constant RHSs.

**AST annotation — open.** The checker must record each node's type.
The choice is between annotating the AST in place (Odin's approach), a
side table keyed by node pointer, or a separate typed IR. The lean is
*in-place annotation or a side table* — a full typed IR is premature
(style guide §6, no speculative machinery); the C backend emits
straight from the AST with no IR (§11.20), so the typed-IR question
waits for a second backend. The decision lands with the first
implementation slice, not here.

## 10. Sequencing and roadmap

The checker depends on parser features that do not exist yet. The build
order, slotted into the existing TODO board:

1. **C codegen (first slice: consts + expressions)** — the board's head
   of queue (§11.20): the smallest complete running thing first. Not a
   checker dependency — the checker's slices follow it on the same
   board.
2. **Blocks and procedures** — gives scopes and proc types.
3. **Error recovery and multi-diagnostic reporting** — so the checker's
   diagnostics compose (§8).
4. **Variables, calls, assignment, typed parameters** — `:=` /
   `x : T = expr` / `f(x)` / `x = expr` / `proc(x: int) -> int`; the
   multi-char operators `:=` and `->` land here, which multi-return
   (§4) depends on.
5. **Name resolution** — the `resolve` phase, usable as soon as blocks
   and procs exist.
6. **Typing (the HM checker)** — the `type` phase; includes the DU
   syntax and `switch` from §6, once the expression grammar admits
   `switch`.
7. **Constant folding** — the `fold` phase; delivers the §3.3/§5.2
   promises.
8. *Then* `defer` → `scoped` (the reason gauge exists), now type-checked.

**Spec sync (AGENTS.md).** grammar.cf, language.md, and the lexer tests
land in the *same commit* as the code they describe. This doc is
`docs/` — a design document — so it lands ahead of its code without a
spec change; the spec updates come with the implementation slices
(new keyword tokens for `xx`/`cast`/`distinct`/`union`/`switch`, the
return-list production, the DU rules, the cast precedence rows, the
lexer-test expected tokens).

## Open questions

Consolidated — each is explored above with a lean, and each is settled
at its implementation slice, not here:

- **DU syntax** — Odin tagged union vs ML sum (lean: Odin).
- **Distinct operator inheritance** — same-type operands inherit,
  cross-type refused (lean).
- **Multi-return in single-expression positions** — follow Go: legal
  only in a multi-binding context (lean).
- **Block multi-values** — blocks carry a single value (lean).
- **Shadowing rules** — allow in nested scopes, refuse where it bites
  (lean).
- **`xx` scope** — lossless coercions only; lossy/reinterpreting needs
  `cast` (lean).
- **Bit-reinterpretation cast** — deferred to FFI.
- **AST annotation strategy** — in-place or side table, no full typed
  IR yet (lean).
- **`switch` spelling and exhaustiveness** — `#partial` opt-out, payload
  narrowing per arm (lean, after §11.9).