# Scoping: `scoped` resources and `defer`

How resource lifetimes work in londolang. This is a design document, not an
implementation — the syntax here is the proposal, not yet built.

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

Convention: `file_open` and `file_close` each take one pointer parameter,
`^T`, and `T` is inferred from `file_open`'s first parameter. So given
`file_open :: proc(f: ^File)`, the resource type is `File`.

Use it as a scoped block, with `it` bound to the resource. Any extra
arguments are forwarded to the constructor (after the `&it` pointer), so it
can take a path, an allocator, a size — whatever the resource needs:

```odin
File { ... }                 // no extra args
File("data.txt") {           // forwarded to file_open
	// ... code, with `it` as the file ...
}
```

This desugars to:

```odin
{
	it: File                                 // type inferred from file_open's ^File
	file_open(&it, "data.txt")
	defer file_close(&it)
	// ... the code ...
}
```

`it` is a stack-local; the constructor fills it in, and it may point into an
arena. The sugar never takes memory control away from you — you still hand the
constructor its allocator or arena, and nothing is hidden behind a runtime.

## Semantics

- **`it` is the implicit binding.** The resource is constructed into `it`
  before the body runs and cleaned up after it exits.
- **Extra arguments go to the constructor.** `File("data.txt")` forwards
  `"data.txt"` to `file_open(&it, "data.txt")`. Convention: the constructor's
  first parameter is `^T`; the rest are supplied by the scoped block call.
- **Constructor runs first, then the defer is registered** — if the constructor
  fails or the body never runs, cleanup simply doesn't fire. See the failure
  gate below. (A failure-tracking variant, Zig-style `errdefer`, is a later
  option, not in the first cut.)
- **Multiple defers run LIFO** (reverse order of registration), matching Odin.
  Nesting scoped blocks therefore cleans up inner resources first.
- **Unit resource type.** If the constructor takes no pointer parameter, the
  resource type is unit and there's no `it` binding — the block is just
  begin/body/end: `ClayLayout { ... }` calls `clay_begin_layout()` then
  `clay_end_layout()`.
- **Value-producing destructor.** If the destructor returns a non-unit type,
  that return is the scoped block's *value*, produced at scope exit after the
  body: `commands := ClayLayout { ... }` yields what `clay_end_layout`
  returns, so the frame's render commands escape exactly where the scope ends.
  If the destructor returns unit, the block's value is its last expression.
- **A scope-block is still a block**, so it has a value (its last expression,
  or the destructor's return per the rule above); the cleanup runs at exit,
  after that value is computed. See the caveat above about not returning
  something that aliases `it`.

## Pass structure

The proposal is pure sugar and falls out in passes, as you suggested:

1. **Parse** `File { ... }` as a distinct *scoped block* node — an identifier
   immediately followed by a block. (The parser need not yet know whether
   `File` is a `scoped` resource; it just records the shape.)
2. **Resolve / desugar** — once `File`'s definition is known, rewrite the node
   into `{ it: File; file_open(&it); defer file_close(&it); ... }`. `scoped`
   declarations are looked up in the registry of scoped resources.
3. **Lower defer** — a later pass inserts the deferred cleanup at the block's
   exit point in the IR/codegen, LIFO.

This keeps the parser simple (it never needs a symbol table for this) and
mirrors how the compiler already layers passes.

## Why it's worth doing

It fits the north star (see [design.md](design.md)):

- **One obvious way** to manage a resource — the pairing is guaranteed by
  construction.
- **The happy path is the short path** — the common `make`/`cleanup` pairing
  becomes a single declarative block instead of three hand-written lines.
- **Zero runtime cost** — it desugars to the same make/defer/cleanup you'd
  write by hand; there's no hidden machinery.

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
  needs nothing: it's a rewrite, so the compiler stays small.
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

## Is this new? (C++, C#, Python, Go, Zig)

**The mechanism is not new — the form is.** That's the whole claim, and it's
worth stating as plainly as possible.

The mechanism — a block-scoped cleanup guard — has existed for decades: C++
`lock_guard`/scope-guard idiom, C# `using` with `IDisposable`, Python's
`with`, Go's `defer`, Zig's `defer`. If `scoped` were just another `using`,
it would be solving a solved problem. It isn't, and the difference is entirely
in the *form* of the construct:

| | C++ RAII | C# `using` | Zig `defer` | `scoped` |
|---|---|---|---|---|
| mechanism | destructor on a class | `IDisposable` interface | block defer | block defer (sugar) |
| scopes an arbitrary pair of free procs? | no — needs a class | no — needs an `IDisposable` type | yes, but hand-written | yes, named and inferred |
| declarative resource definition? | no | no | no | yes — `File :: scoped { ... }` |
| failure gate (constructor says "skip the body") | no | no | n/a | yes |
| requires an object model | yes | yes | no | no |

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
- **The failure gate** (constructor returns `false` → skip the body) doesn't
  exist in `using` or destructors — you'd hand-roll the `if (Begin()) { ...
  End(); }` shape.
- **It is not an ownership system.** It never claims to manage object
  lifecycles, moves, or composition — it's a scope guard, nothing more. That
  isn't a limitation; it's what keeps it from dragging in RAII's machinery
  and OOP flavour.

So: **the mechanism is old; the form is the contribution.** The value isn't a
new way to clean up — it's the pairing guarantee at zero machinery, in a
declarative, interface-free, defer-based, gate-capable form that fits a
data-oriented, non-OOP language. That's what `scoped` adds over `using`, RAII,
and `defer`. See [scoping_examples.md](scoping_examples.md) for a concrete
walk-through of exactly this: macroless C → Clay's macro → `scoped`.

## The Clay problem, and immediate-mode UI

A scoped block is the language-level answer to what [Clay](https://github.com/nicbarker/clay)
(Nic Barker's C UI layout library) has to fake with a macro.

C cannot express "build a nested declarative tree", so Clay's `CLAY(id, { ... })`
macro wraps designated initializers and `{}` block nesting — the macro pushes a
layout context on entry and pops it on exit, while the element tree lives in a
contiguous arena (the stack-based tree). The macro exists only because C has no
real block-scoped construction.

In londolang that's just a scoped resource:

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

## Escaping, the failure gate, and ImGui's Begin/End

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

### The failure gate: when the constructor returns `false`

ImGui's `Begin(name)` returns `false` when the window is collapsed, and the
canonical C++ pattern is:

```cpp
if (ImGui::Begin("Debug")) { ...; ImGui::End(); }
```

A scoped block needs a rule for "the constructor says don't run": **if the
constructor returns `false`, the body is skipped and no cleanup runs.** Then
the ImGui pattern needs no `if`:

```odin
Window("Debug") {
	// only runs while the window is open — nothing to close
}
```

Clay's `layout_begin` always succeeds, so it never needs the gate; ImGui's
does. (A Zig-style `errdefer` variant, cleaning up on early failure *inside*
the body, is a separate later option.)

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
  resource may use the implicit `it`; the rest need `as name` (order-based
  implicit names would be unergonomic). An option worth discussing: ban the
  implicit `it` in the multi case and force a name on every resource. Not in
  the first cut — nested scoped blocks cover multiple resources today.
- **Custom binding name**: `(...)` is now constructor args, so a custom name
  would need a different spelling (e.g. `File as f { ... }`). A small
  parser extension, deferred.
- **Explicit resource type** vs inference from `file_open`: inference is the
  proposed default; an explicit `type:` field is the fallback if inference gets
  awkward (e.g. overloaded or generic `file_open`).
- **Failure handling**: `errdefer`-style cleanup only on early exit.
- **Escape analysis**: rejecting a scoped block value that aliases `it`.
- **`defer` spelling**: `defer file_close(&it)` vs `defer(file_close(&it))` — to be
  settled with the rest of the expression grammar.
