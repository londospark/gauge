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

## The problem: the manual make/defer/cleanup pattern

The idiomatic C/Odin way to manage a resource is hand-written and error-prone:

```odin
thing: Thing
make_thing(&thing)
defer cleanup(&thing)
// ... use thing ...
```

Three easy mistakes: forget the defer, forget the cleanup, or get the pairing
wrong. The pairing is what a `scope` resource makes impossible to get wrong.

## Proposal: `scope` resources

Declare a resource type with its constructor and destructor:

```odin
Thing :: scope { make_thing, cleanup }
```

Convention: `make_thing` and `cleanup` each take one pointer parameter,
`^T`, and `T` is inferred from `make_thing`'s first parameter. So given
`make_thing :: proc(t: ^Thing)`, the resource type is `Thing`.

Use it as a scoped block, with `it` bound to the resource. Any extra
arguments are forwarded to `make_thing` (after the `&it` pointer), so the
constructor can take an allocator, an arena, a size — whatever the resource
needs:

```odin
Thing { ... }                     // no extra args
Thing(context.allocator, 64) {    // forwarded to make_thing
	// ... code, with `it` as the thing ...
}
```

This desugars to:

```odin
{
	it: T                                      // T inferred from make_thing's ^T
	make_thing(&it, context.allocator, 64)
	defer cleanup(&it)
	// ... the code ...
}
```

`it` is a stack-local; `make_thing` fills it in, and it may point into an arena.
The sugar never takes memory control away from you — you still hand the
constructor its allocator or arena, and nothing is hidden behind a runtime.

## Semantics

- **`it` is the implicit binding.** The resource is constructed into `it`
  before the body runs and cleaned up after it exits.
- **Extra arguments go to the constructor.** `Thing(args...)` forwards `args...`
  to `make_thing(&it, args...)`. Convention: `make_thing`'s first parameter is
  `^T`; the rest are supplied by the scoped block call.
- **Constructor runs first, then the defer is registered** — if `make_thing`
  fails or the body never runs, cleanup simply doesn't fire. (A
  failure-tracking variant, Zig-style `errdefer`, is a later option, not in the
  first cut.)
- **Multiple defers run LIFO** (reverse order of registration), matching Odin.
  Nesting scope-blocks therefore cleans up inner resources first.
- **A scope-block is still a block**, so it has a value (its last expression);
  the cleanup runs at exit, after that value is computed. See the caveat above
  about not returning something that aliases `it`.

## Pass structure

The proposal is pure sugar and falls out in passes, as you suggested:

1. **Parse** `Thing { ... }` as a distinct *scope application* node —
   an identifier immediately followed by a block. (The parser need not yet know
   whether `Thing` is a scope-resource; it just records the shape.)
2. **Resolve / desugar** — once `Thing`'s definition is known, rewrite the node
   into `{ it: T; make_thing(&it); defer cleanup(&it); ... }`. `scope`
   declarations are looked up in the scope registry.
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

It's also deliberately *not* full RAII or ownership: it's an explicit, local
lifetime — `Thing { ... }` — rather than a type-level destructor that runs
whenever a value goes out of scope. That keeps the semantics visible and the
implementation a rewrite, not a type-system feature.

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

## Open questions / future work

- **Multiple resources in one scope** (`Thing1, Thing2 { ... }`): natural
  extension — desugars to two makes and two defers (LIFO). Not in the first
  cut; nested scope-blocks cover it today.
- **Custom binding name**: `(...)` is now constructor args, so a custom name
  would need a different spelling (e.g. `Thing as handle { ... }`). A small
  parser extension, deferred.
- **Explicit resource type** vs inference from `make_thing`: inference is the
  proposed default; an explicit `type:` field is the fallback if inference gets
  awkward (e.g. overloaded or generic `make_thing`).
- **Failure handling**: `errdefer`-style cleanup only on early exit.
- **Escape analysis**: rejecting a scope-block value that aliases `it`.
- **`defer` spelling**: `defer cleanup(&it)` vs `defer(cleanup(&it))` — to be
  settled with the rest of the expression grammar.
