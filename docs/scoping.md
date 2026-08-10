# Scoping: `scoped` resources and `defer`

How resource lifetimes work in gauge — and why they're worth building right. The
syntax here is the proposal; the model is the point. Nothing here is implemented
yet.

This document is a revision. The original design derived the failure gate from
the constructor's signature. Two things changed it: we tested Odin's
`deferred_*` attributes empirically (see [Odin already has the
pairing](#odin-already-has-the-pairing-deferred_)) and learned the pairing
mechanism is *not* novel — Odin ships it — and we decided the gate should be the
**caller's choice**, not a property of the resource declaration.

## Blocks are scopes, so defer composes

A block is both a **value** and a **scope**. That single fact makes resource
lifetimes straightforward:

- A `defer` registered inside a block runs when the block exits.
- A block's value (its last expression) is computed first; the deferred
  cleanups then run at exit.

So `{ ... }` is the unit of both composition and lifetime. This is the same
model that makes Rust's `Drop`, Odin's `defer`, and Zig's `defer`/`errdefer`
coherent.

**Caveat that follows from blocks-as-values:** a block's value must not alias a
resource it cleans up at exit — the cleanup runs after the value is computed, so
a value pointing at the cleaned-up thing would dangle. (The user's job for now;
a borrow/escape check is a later-phase concern.)

## The problem: the manual open/defer/close pattern

The idiomatic C/Odin way to manage a resource is hand-written and error-prone:

```odin
file: File
file_open(&file)
defer file_close(&file)
// ... use file ...
```

Three easy mistakes: forget the defer, forget the close, or get the pairing
wrong. The pairing is what a `scoped` resource makes impossible to get wrong.

## Proposal: `scoped` resources

Declare a resource with its constructor and destructor:

```odin
File :: scoped { file_open, file_close }
```

Convention: `file_open` fills a resource through a pointer — its first parameter
is `^T`, and `T` is inferred from it — and `file_close` takes the same `^T`.
So given `file_open :: proc(f: ^File, path: string) -> bool`, the resource type
is `File`, and the constructor may also return a `bool` (see the gate below).
Constructors that cannot fail return `void`.

Use it as a scoped block, with `it` bound to the resource and `ok` bound to the
constructor's `bool` (when it returns one). Any extra arguments are forwarded to
the constructor after the `&it` pointer, so it can take a path, an allocator, a
size — whatever the resource needs:

```odin
File("data.txt") {
	// ... code, with `it` as the file and `ok` as file_open's bool ...
}
```

This desugars to:

```odin
{
	it: File
	ok := file_open(&it, "data.txt")
	defer file_close(&it)
	// ... the code ...
}
```

`it` is a stack-local; the constructor fills it in, and it may point into an
arena. The sugar never takes memory control away from you — you still hand the
constructor its allocator or arena, and nothing is hidden behind a runtime.

### The gated form: the caller chooses

If the constructor returns a `bool`, the caller decides how and when to use it as
a gate — it is **never** a gate automatically. The plain form above always runs
the body and always defers cleanup, with `ok` available inside the body for the
caller to use or ignore.

To use the `bool` as a gate, the caller writes the scoped block as an `if`
condition. **Gate false → the body is skipped and no cleanup runs:**

```odin
if File("data.txt") {
	// ... runs only when file_open returned true; nothing to close when it didn't ...
}
```

This desugars to:

```odin
{
	it: File
	if file_open(&it, "data.txt") {
		defer file_close(&it)
		// ... the code ...
	}
}
```

An `else` is allowed, for "what to do when the gate is closed":

```odin
if Window("Debug") {
	// draw the window's widgets
} else {
	// collapsed — skip; nothing to clean up
}
```

## How to know you're gating (the rule)

One rule, no guessing:

- `Name(args) { ... }` — **plain**. Begin runs, `end` is deferred, the body
  runs. `ok` (begin's `bool`, if any) is bound inside the body; the caller may
  branch on it or ignore it.
- `if Name(args) { ... }` — **gated**. Begin's `bool` is the condition. False →
  no body, no `end`. Requires the constructor to return a `bool` (a `void`
  constructor in gate position is a compile error).
- The gate is a **use-site** choice, spelled `if`. A resource whose constructor
  returns `bool` is not gated until the caller says so.

Disambiguation: `if Name(...) { ... }` is a gated scoped block exactly when
`Name` resolves to a `scoped` resource declaration; otherwise it's an ordinary
call in an ordinary `if`. Context-sensitive syntax exists in every language (C's
declaration-vs-call, C++/Java generics, Rust's `{}` block-vs-struct-literal);
this is no worse.

The payoff vs the ImGui idiom is that `end` needs no self-gating logic — ImGui's
`Begin` returning false means *don't call `End` at all*, and the gated form
enforces exactly that by construction. Compare the hand-written shape:

```odin
// Odin / C++ — end must remember to check the flag
begin_menu :: proc(name: string) -> (open: bool) { ... }
end_menu :: proc(open := true) {
	if !open do return
	...
}
if begin_menu("Hello") {
	defer end_menu()
	...
}
```

```odin
// gauge — the caller chooses the gate; end never sees a "closed" call
Menu :: scoped { begin_menu, end_menu }
if Menu("Hello") {
	// ... runs only while open; end_menu is guaranteed exactly once ...
}
```

## What flows where (three channels)

`scoped` has exactly three value-ish things, and keeping them separate is what
makes the rules sensible:

1. **The resource** — `it`, filled by the constructor through a pointer. Its
   memory is the caller's (a stack local); allocations are the constructor's,
   via whatever allocator it is handed. The sugar never allocates.
2. **The state** — `ok`, the constructor's `bool`. It's the caller's to use
   however it likes: branch on it inside the body, or gate the whole block with
   `if`. The resource declaration never decides this.
3. **The block's value** — what `Name(...) { ... }` evaluates to. One rule:
   **the destructor's return is the block's value when the destructor returns a
   non-unit type; otherwise the block's value is the body's last expression.**
   The trigger is visible in the resource declaration you read anyway.

```odin
File("data.txt") { parse_config() }            // file_close returns void → value = parse_config()
commands := ClayLayout { /* widgets */ }        // clay_end_layout returns Commands → value = commands
```

In the gated form the block is a statement; its value is not used. (An
`if`-expression that also gates is future work, listed below.)

## Semantics

- **`it` is the implicit binding.** The resource is constructed into `it`
  before the body runs and cleaned up after it exits. `it` is a stack-local; the
  constructor fills it in, and it may point into an arena.
- **`ok` is begin's `bool`.** Bound only when the constructor returns one. In
  the plain form, a fallible constructor's `false` is the caller's signal not to
  use `it` — the body runs regardless, and `it` may be zero. Gating with `if` is
  the way to make the whole body conditional on it.
- **Extra arguments go to the constructor.** `File("data.txt")` forwards
  `"data.txt"` to `file_open(&it, "data.txt")`. Convention: the constructor's
  first parameter is `^T`; the rest are supplied by the scoped block call.
- **Constructor runs first, then the defer is registered** — if the constructor
  fails or the body never runs, cleanup simply doesn't fire. See the gate above.
- **Multiple defers run LIFO** (reverse order of registration), matching Odin.
  Nesting scoped blocks therefore cleans up inner resources first, and scoped
  blocks mix freely with raw `defer`.
- **Unit resource type.** If the constructor takes no pointer parameter, the
  resource type is unit and there's no `it` binding — the block is just
  begin/body/end: `ClayLayout { ... }` calls `clay_begin_layout()` then
  `clay_end_layout()`.
- **Value-producing destructor.** If the destructor returns a non-unit type,
  that return is the scoped block's *value*, produced at scope exit after the
  body: `commands := ClayLayout { ... }` yields what `clay_end_layout` returns,
  so the frame's render commands escape exactly where the scope ends.
- **A scope-block is still a block**, so it has a value (see the channel rule
  above); the cleanup runs at exit, after that value is computed. See the caveat
  about not returning something that aliases `it`.

## Pass structure

The unit-end forms of `scoped` are pure sugar and fall out in passes:

1. **Parse** `Name { ... }` / `Name(...) { ... }` as a distinct *scoped block*
   node — an identifier followed by a block, with the `if` form as a distinct
   *gated scoped block*. (The parser need not yet know whether `Name` is a
   `scoped` resource; it just records the shape.)
2. **Resolve / desugar** — once `Name`'s definition is known, rewrite the node
   into `{ it: T; ok := begin(&it, args); defer end(&it); ... }`, or into the
   `if ok { ... }` shape for the gated form. `scoped` declarations are looked up
   in the registry of scoped resources.
3. **Lower defer** — a later pass inserts the deferred cleanup at the block's
   exit point in the IR/codegen, LIFO.

**The one non-sugar case is the value-producing destructor.** A plain `defer`
discards its call's return value — the defer runs after the block's value is
computed, so a naive desugar can't make `clay_end_layout()`'s return the block's
value. That form needs the scoped block lowered as a begin/body/end sandwich
whose **result slot is wired to the destructor's return**. It's a small,
localized cost, but it means the "pure sugar" claim in the risk section holds
only for destructors that return unit.

## Odin already has the pairing: `deferred_*`

Odin ships the pairing mechanism we're proposing, as procedure attributes:

```odin
@(deferred_out=end_menu)
menu :: proc(name: string, flags: Flags = nil) -> (open: bool) {
	return begin_menu(name, flags)
}

if menu("Hello") {
	// ...
}
```

Calling `menu(...)` auto-defers `end_menu(<the call's return>)` to the end of
the statement or block that directly contains the call. We verified this
empirically: a call in an `if` condition fires its deferred proc at the end of
the `if` statement (before sibling statements), and a bare call fires it at the
end of the enclosing block. That binding is exactly the block-shaped pairing we
want — Odin already does the sensible thing here.

That's worth stating plainly, because it reframes the claim. **The mechanism is
not novel, and gauge should not pretend otherwise.** Odin has the pairing, at
the statement level, for the exact immediate-mode case the design cares about.
So gauge's `scoped` earns its syntax not by inventing pairing but by the delta
over what Odin ships:

| | Odin `deferred_*` | gauge `scoped` |
|---|---|---|
| pairing | attribute on the begin proc | named resource declaration |
| gate | end self-gates (`open := true`); end *always runs* | caller-chosen `if`; gate false → no body, **no end** |
| begin's `bool` inside the body | not visible — routed only to end | `ok`, bound in the body |
| block value | none — a deferred call's return is discarded | yes — incl. value-producing destructor |
| cleanup visible at the call site? | no — implicit at statement end | yes — the block is the scope |

- **The gate is the real difference.** Odin's `end_menu(open := true)` runs
  even for a collapsed window and must remember to no-op itself. ImGui's actual
  contract is *don't call `End` when `Begin` returns `false`* — gauge enforces
  that by construction; Odin relies on `end`'s self-discipline. And the caller
  can always run the body regardless of the flag (`Menu("Hello") { if ok { ... } }`).
- **`ok` is visible in the body.** Odin routes begin's return only to end, never
  into the body. Gauge binds it as `ok`, so "run the body, branch on the flag"
  needs no gymnastics.
- **The block value is the one true capability Odin lacks.** Odin cannot make a
  deferred call's return the value of anything (it documents that `defer` can't
  even modify named return values). `commands := ClayLayout { ... }` is
  inexpressible there. This is also the one genuinely new capability in the
  whole design — and it's why the value-producing destructor is the most
  interesting part of it.

The rest of the differences — a named resource registry, mixing with raw `defer`
LIFO, multi-resource blocks — are conveniences on top of the same mechanism.

## Why it's worth doing

It fits the north star (see [design.md](design.md)):

- **One obvious way** to manage a resource — the pairing is guaranteed by
  construction.
- **The happy path is the short path** — the common `make`/`cleanup` pairing
  becomes a single declarative block instead of three hand-written lines.
- **Zero runtime cost** — it desugars to the same make/defer/cleanup you'd
  write by hand; there's no hidden machinery (the value-producing destructor
  aside, which is a small lowering cost).

But the honest framing matters: it is a **convenience**, not a differentiator.
The pairing exists in Odin; what gauge adds is caller-chosen gating, `ok` in the
body, and the block value. Build `defer` first, dogfood the explicit pattern,
and let `scoped` prove its delta in real code before trusting it.

## Why `scoped` is not RAII (and not destructors)

RAII (C++/Rust) and `scoped` both pair construction with cleanup, but they are
different mechanisms with different trade-offs:

| | RAII (destructors) | `scoped` |
|---|---|---|
| Who owns the cleanup | the **type** | the **block** |
| When it runs | whenever a value leaves *any* scope, automatically | at the end of the one explicit block |
| Visible at the use site? | no — implicit | yes — `File { ... }` is right there |
| Needs ownership/move machinery | yes — borrow checker, move rules, destructor ordering | no — pure sugar over make + defer |
| Can the resource escape the scope? | yes — moved, returned, stored | no — by construction |

Destructors are implicit magic driven by the type system: create a value and
cleanup happens invisibly later, governed by ownership rules. `scoped` is a
**scope guard**: one explicit entry, one explicit exit, cleanup visible in the
code, LIFO, and no type-system machinery underneath — it desugars to the exact
make/defer/cleanup you'd write by hand. That's a deliberate philosophy: cleanup
you can *see* beats cleanup that happens to you (the `defer`-over-destructors
position Odin and Jai take).

### Why the difference matters

- **Implementation cost.** RAII drags in the ownership apparatus — move
  semantics, destructor ordering, borrow checking, rule-of-five — because the
  type system must understand when and in what order values die. `scoped`
  needs almost nothing: for unit-returning destructors it's a rewrite, so the
  compiler stays small.
- **Predictability.** Block-scoped cleanup is fully deterministic and visible;
  you never wonder *when* a destructor fires or whether a move postponed it.
- **It fits the problem shape.** RAII's automaticism is exactly what
  immediate-mode UI doesn't want (below). `scoped` matches the *scope*-shaped
  problems, which is where resource pairing actually lives in systems code.

### Why this doesn't nudge toward OOP

This matters because RAII and OOP grew up together — destructors live on
classes, and the ownership model is object-shaped. `scoped` deliberately
imports none of that:

- **No classes, no methods, no objects.** `file_open`/`file_close` are plain
  procedures; `it` is plain data. There is no bundle of state-and-behavior, no
  `thing.begin()` / `thing.render()` — the block operates on `it` as data.
- **No lifetime beyond the block.** An RAII object can be stored, returned, or
  placed in a hierarchy — it has object identity and a lifecycle. A `scoped`
  thing exists only inside its block; it can't escape, so there's no ownership
  graph, no "is-a", no polymorphism to reason about.
- **It reinforces data + procedures, not encapsulation.** Everything is
  visible: the data, the two procs, the scope. That's the C/Odin/Wirth shape —
  explicit and unencapsulated — the opposite of OOP's sealed objects.
- **The choice is the point.** Picking block-scoped `scoped` over type-driven
  RAII is deliberately picking the non-OOP path: the resource pairing is kept,
  the object machinery is not.

## Is this new? (C++, C#, Python, Go, Zig, Odin)

**The mechanism is not new — the form is.** That's the whole claim, and it's
worth stating as plainly as possible.

The mechanism — a block-scoped cleanup guard — has existed for decades: C++
`lock_guard`/scope-guard idiom, C# `using` with `IDisposable`, Python's
`with`, Go's `defer`, Zig's `defer`, and Odin's `defer` + `deferred_*`. If
`scoped` were just another `using`, it would be solving a solved problem. It
isn't, and the difference is entirely in the *form* of the construct:

| | C++ RAII | C# `using` | Zig `defer` | Odin `deferred_*` | `scoped` |
|---|---|---|---|---|---|
| mechanism | destructor on a class | `IDisposable` interface | block defer | attribute on the begin proc | block defer (sugar) |
| scopes an arbitrary pair of free procs? | no — needs a class | no — needs an `IDisposable` type | yes, but hand-written | yes — attribute pairs them | yes, named and inferred |
| declarative resource definition? | no | no | no | partial — attribute, not a named resource | yes — `File :: scoped { ... }` |
| skip-the-body gate (caller-chosen `if`) | no | no | n/a | no — end self-gates, always runs | yes — skips body **and** cleanup |
| requires an object model | yes | yes | no | no | no |

- **No interface, no object model.** C# `using` demands the type implement
  `IDisposable`; C++ demands a class with a destructor. `scoped` pairs two
  free procedures — `file_open`/`file_close` need no interface, no class, no
  lifecycle the type system must understand. In C#, scoping an arbitrary
  open/close pair means writing a wrapper class; here the pair *is* the
  declaration.
- **Declarative and reusable.** `File :: scoped { file_open, file_close }`
  defines the resource once; `File(...) { ... }` uses it everywhere. C++'s
  scope-guard idiom and C#'s wrapper classes re-express the pairing per type.
  The boilerplate moves into the language.
- **It is literally defer.** The desugar is `file_open(&it); defer
  file_close(&it);` — the same mechanism you'd write by hand. So it stacks
  LIFO with ordinary defers and mixes with raw `defer` freely. C# `using` and
  C++ destructors are separate mechanisms; `scoped` is the language's existing
  resource tool, made declarative.
- **The gate is the delta over Odin.** Odin's `deferred_*` always runs `end`
  and relies on it to self-gate. `scoped` lets the *caller* choose, and a
  closed gate skips body and cleanup both — matching the ImGui contract
  ("don't call `End` when `Begin` returns `false`") by construction.
- **It is not an ownership system.** It never claims to manage object
  lifecycles, moves, or composition — it's a scope guard, nothing more. That
  isn't a limitation; it's what keeps it from dragging in RAII's machinery
  and OOP flavour.

So: **the mechanism is old; the form is the contribution.** The value isn't a
new way to clean up — it's the caller-chosen gate, `ok` in the body, and the
block value, in a declarative, interface-free, defer-based form that fits a
data-oriented, non-OOP language. See [scoping_examples.md](scoping_examples.md)
for a concrete walk-through of the immediate-mode case.

## The Clay problem, and immediate-mode UI

A scoped block is the language-level answer to what [Clay](https://github.com/nicbarker/clay)
(Nic Barker's C UI layout library) has to fake with a macro.

C cannot express "build a nested declarative tree", so Clay's `CLAY(id, { ... })`
macro wraps designated initializers and `{}` block nesting — the macro pushes a
layout context on entry and pops it on exit, while the element tree lives in a
contiguous arena (the stack-based tree). The macro exists only because C has no
real block-scoped construction.

In gauge that's just a scoped resource:

```odin
Layout :: scoped { layout_begin, layout_end }

Layout(id) {
	// child layouts, nested — each Layout { } is an element in the tree
}
```

No macro; blocks are real scopes; `layout_end` is the deferred cleanup.

The same applies to immediate-mode UIs (ImGui-style). Their #1 bug class is a
mismatched Begin/End — open a window and forget to close it. A scoped window
makes that impossible:

```odin
Window :: scoped { window_begin, window_end }

Window("Debug") {
	// widgets... — window_end is guaranteed on every exit
}
```

`window_begin`/`window_end` pair by construction, and because the frame is
rebuilt each pass, the same scoped blocks re-declare the UI every frame. You
still own the memory (arena/stack), but the pairing is guaranteed by syntax.

### Why RAII and destructors wouldn't fit here

Immediate-mode UI's unit of life is not a *value* with a lifetime — it's a
*scope*: enter, declare children, leave, every frame, in strict stack order.
Destructors are the wrong tool:

- **Destructors are tied to value lifetimes, not block nesting.** They fire
  when the *value* dies — including moves and container teardown — so you lose
  the "exactly this block, exactly this frame" guarantee.
- **The classic bug is a mismatched Begin/End, not leaked ownership.** RAII
  solves ownership; the UI problem is *pairing*. A block guarantees the
  pairing by construction; a destructor only guarantees cleanup.
- **Composition doesn't help.** RAII's strength is an ownership hierarchy of
  values (a struct owns its members). A UI tree is a *transient declaration
  hierarchy*, rebuilt each frame — there's no ownership graph for RAII to
  manage.

This is why `scoped` isn't a poor man's RAII — it's the tool for
scope-shaped problems, which is where real resource pairing lives.

## Escaping, the gate, and ImGui's Begin/End

### What can escape the scope

The resource (`it`) is block-local by construction — it can't be returned,
stored, or outlive the block. Two things can, and both are intended:

- **Data the block produces.** `scoped` only bounds the resource, not what the
  body does with it. A command list recorded inside `Renderer { ... }`
  survives the block; only the renderer is torn down.
- **The block's value can be the destructor's output.** When the destructor
  returns a value (e.g. `clay_end_layout` → the render commands), that value is
  the scoped block's value: `commands := ClayLayout { ... }`. The output
  escapes exactly where the scope ends.
- **In immediate mode, nothing else needs to.** The tree is rebuilt every
  frame, so no window or layout context ever needs to escape — you re-enter
  the same scopes each frame, and persistent state (an open flag, a size)
  lives in a plain variable.

### The gate: ImGui's `Begin` returns `false` when the window is collapsed

The canonical C++ pattern is:

```cpp
if (ImGui::Begin("Debug")) { ...; ImGui::End(); }
```

In gauge, the caller chooses the gate. The gated form — `if` prefix — skips the
body *and* the cleanup when `Begin` returns `false`, so no self-gating `end` is
needed:

```odin
if Window("Debug") {
	// only runs while the window is open — nothing to close
}
```

And when you need "what to do when it's closed", that's an `else`:

```odin
if Window("Debug") {
	// draw the window's widgets
} else {
	// collapsed — skip the widgets; window_end is not called
}
```

The ungated form still runs the body when `Begin` returns `false`, with `ok`
bound — for the cases where a collapsed window still wants its body to run
(e.g. resetting transient state) or where the `bool` is *not* a gate at all
but a plain result the body branches on:

```odin
Window("Debug") {
	if ok {
		// the window is open — draw the widgets
	} else {
		// collapsed — still run, but skip the widgets
	}
}
```

Clay's `layout_begin` returns `void`, so it can't be gated at all — the caller
has no `bool` to gate on. ImGui's `Begin` returns `bool`, so each call site
chooses: run the body unconditionally (branching on `ok` inside) or gate the
whole block with `if`. (A Zig-style `errdefer` variant, cleaning up on early
failure *inside* the body, is a separate later option.)

### Why ImGui didn't use RAII for Begin/End

- `Begin` returns a bool — a constructor can't "not create", so RAII would
  carry a validity flag and check it everywhere. The `if (Begin) { ... End }`
  shape handles the collapsed case naturally.
- Immediate mode is anti-hidden-state: bare `Begin()`/`End()` keep the frame
  structure visible.
- Game C++ is often built `-fno-exceptions`; destructor cleanup on exception
  unwind is exactly what you don't want mid-frame.
- The ecosystem bolted RAII wrappers (`ImScoped`, `ScopedWindow`) on anyway —
  proof the pairing guarantee is wanted. `scoped` provides it natively,
  block-shaped, with no object machinery.

## Risks and the devil's advocate

An honest accounting of what could be wrong with `scoped`, each with our answer.
This is written so the decision to build it (or not) is made with eyes open —
the feature is a proposal, not a commitment.

### R1 — It's sugar over defer, and sugar is the easy 10%

The construct makes the *happy path* nice: constructor → body → destructor. The
hard parts of resource management — partial construction, nested failures,
resources that outlive a block, cleanup-vs-value ordering — are still there,
just hidden behind a nicer spelling.

**Answer.** True, and it's exactly why `scoped` is deferred until `defer`
exists and is proven. It's a convenience built on a real mechanism, not a
substitute for one. Its value is modest but real — pairing by construction and
a shorter happy path — so it should be treated as a nice-to-have and dogfooded
before it's trusted.

### R2 — It's being designed before its foundations

`defer` (with full exit-path lowering), blocks-as-values, and control flow
don't exist yet. Designing the sugar before the base is premature.

**Answer.** True. That's why this is a *design document*, not an
implementation plan. `scoped` rides on `defer`; the plan is to build `defer`
first (it's wanted in its own right), then decide whether `scoped` earns its
syntax. One honest correction to the earlier draft: the unit-returning-destructor
forms *are* pure sugar, but the value-producing destructor needs a small
dedicated lowering (see [Pass structure](#pass-structure)). The mechanism cost
is near-zero, not literally zero.

### R3 — The value-producing destructor breaks the block-value rule

`commands := ClayLayout { draw() }` — a reader expects `commands` to be
`draw()`'s value; it's actually the destructor's return. Two value rules.

**Answer.** It's one rule with a visible trigger: a scoped block's value is the
destructor's return when the destructor returns a non-unit type, otherwise the
body's last expression — and the resource declaration tells you which case
you're in. It matches the immediate-mode mental model ("the frame produces the
render commands"). In statement position the value is discarded, and the
gated form is never used for a value. It's a subtlety worth naming, not a
reason to drop the feature. (Silver lining: the value is produced *after* the
resource is torn down, so a value-producing destructor's output can't alias the
resource it closes.)

### R4 — The grammar surface is real

`File("x") { }`, `Window as w { }`, `if Window("x") { }` — the parser must
distinguish scoped blocks (and gated scoped blocks) from calls and ordinary
`if`s.

**Answer.** Resolved by name resolution, not by guessing: `X(...) { }` is a
scoped block, and `if X(...) { }` a gated one, exactly when `X` resolves to a
`scoped` resource declaration. Context-sensitive syntax exists in every
language; this is no worse. And if someone dislikes the implicit `it`, a custom
binding is always available (`File as f { ... }`), so the construct never
forces magic on you.

### R5 — `it` (and `ok`) are implicit magic

Hidden variables are constructed, bound, and cleaned up around the body.

**Answer.** That's the construct's point — a resource is opened and closed
around the body — and it's visible in the declaration (`File :: scoped {
file_open, file_close }`). `it`/`ok` follow the `(T, bool)` idiom the language
already uses. Anyone who finds them surprising can name the resource explicitly
or just not use them. The trade is explicitness for conciseness, in the "happy
path is the short path" spirit.

### R6 — The failure gate used to be under-specified

An earlier draft left "constructor returns false" vague.

**Answer.** Resolved: the gate is the caller's choice, spelled `if` — see
[How to know you're gating](#how-to-know-youre-gating-the-rule). A `void`
constructor can't be gated; a `bool` constructor is gated only when the caller
says so; a closed gate skips body and cleanup. The gate is still deliberately
narrow (it covers "the constructor says don't run", the ImGui collapsed-window
case); full failure semantics (`errdefer`, partial-construction handling) is
future work, listed below.

### R7 — Why hasn't someone beaten us to it?

Python's `contextmanager`, D's `scope(exit)`, C++ `scope_guard` exist as
library patterns; Odin ships `deferred_*` as language features.

**Answer.** They did — Odin's `deferred_*` is exactly this pairing, at the
statement level. That's the strongest critique in this document and it's
addressed head-on in [Odin already has the
pairing](#odin-already-has-the-pairing-deferred_). The delta is the caller-chosen
gate, `ok` in the body, and the block value. If those don't earn their keep in
real use, the right call is to drop the keyword and write the pattern by hand.

### R8 — Metaprogramming could do this better (the `#code` argument)

Compile-time code generation (Jai-style `#code` blocks — code that produces
code) could build the scoped pattern as a *library*, no keyword needed. Clay's
macro is a text-level hack that metaprogramming replaces cleanly.

**Answer.** This is the strongest *remaining* critique. gauge has no
metaprogramming, and the honest options are: (a) build `scoped` as a keyword
now, accepting it may be superseded by a library later, or (b) build
metaprogramming first and make `scoped` a library. Metaprogramming is a far
bigger investment than `defer`, and gauge is nowhere near it. So the sequence
is: `defer` first, then decide whether `scoped` (keyword) or metaprogramming
(library) is the right vehicle — and dogfood the explicit pattern before either.
The keyword buys the pattern today, cheaply, and is a natural stepping stone —
not a trap.

### Verdict

`scoped` was billed as "the reason gauge exists." The honest revision is: the
*pairing* isn't — Odin ships it. What's left, and what earns the keyword if
anything does, is the **caller-chosen gate**, **`ok` in the body**, and the
**block value** — a small, concrete delta that matches the immediate-mode mental
model and the `(T, bool)` idiom. The risk section argues for building it *well*:
on top of a proven `defer`, with the escape hatches, honest failure semantics,
and dogfooded on real code — or not at all if the delta doesn't prove out.

## Open questions / future work

- **Multiple resources in one scope**:

  ```odin
  File,
  Window("Debug") as win,
  Lock as guard {
  	// `it` = the File, `win` = the Window, `guard` = the Lock
  }
  ```

  Desugars to makes + defers stacked **LIFO** — the last declared resource
  cleans up first (here: unlock the lock before closing the file). At most one
  resource may use the implicit `it`; the rest need `as name`. Gates compose:
  each resource's `ok` is available to the body, and a gated multi-resource
  block (all gates must pass? any?) is an open question. Not in the first cut —
  nested scoped blocks cover multiple resources today.
- **Custom binding name**: `(...)` is now constructor args, so a custom name
  would need a different spelling (e.g. `File as f { ... }`). A small
  parser extension, deferred.
- **`ok` naming**: bound as `ok` to match the `(T, bool)` idiom; a custom name
  via `as` is the escape hatch.
- **Explicit resource type** vs inference from `file_open`: inference is the
  proposed default; an explicit `type:` field is the fallback if inference gets
  awkward (e.g. overloaded or generic `file_open`).
- **Gated `if`-expression**: a gated scoped block that also produces a value
  (`x := if Window(...) { ... } else { ... }`) — the value rules above cover
  the plain form only.
- **Failure handling**: `errdefer`-style cleanup only on early exit.
- **Escape analysis**: rejecting a scoped block value that aliases `it`.
- **`defer` spelling**: `defer file_close(&it)` vs `defer(file_close(&it))` — to be
  settled with the rest of the expression grammar.
