# Design

The north star for gauge, and the principles that keep it coherent.

## North star

> A consistent syntax that just does what people want it to do.

A language you can hold in your head: one way to say each thing, no surprises, and the common thing you want to write is the short thing to write. Wirth's philosophy, applied to a systems language.

## Why gauge exists

A language with only nicer syntax isn't a reason to exist. gauge's reason
to exist is the **declarative, scope-based resource model** — anything with a
begin/end lifecycle (a file, a window, a layout element, a frame) is a
first-class scoped block, and the same scope model powers immediate-mode UI
ergonomics. It is the feature the language is built around; everything else
serves it.

This is what separates it from:

- **Odin / C / Zig / Go** — `defer` is manual and general; the open/close
  *pairing* is not a language feature. (Odin's `deferred_*` attributes come
  closest — see [scoping.md](scoping.md); gauge's `scoped` is the block-shaped,
  caller-gated, value-bearing refinement of that.)
- **C++ / Rust** — RAII and ownership are type-driven and automatic; gauge's
  is block-driven and explicit.
- **C# `using` / Python `with`** — library patterns tied to an interface
  (`IDisposable`) or a decorator; gauge's is a named, interface-free
  language construct.

Without the scoped model, gauge is Odin with different punctuation. With
it, resource management and immediate-mode UIs become native grammar instead of
hand-rolled `defer` pairs and macros. The honest caveat, from [scoping.md](scoping.md):
Odin already ships the *pairing* (`deferred_*`); gauge's contribution is the
caller-chosen failure gate, `ok` visible in the body, and the value-producing
destructor — and that delta has to earn its syntax in real use, dogfooded on top
of a proven `defer`.

## Principles

1. **Least surprise beats cleverness.** If `=`, `+`, `()`, `{}` already mean something in C/Odin/Rust, keep those meanings. Familiarity is a feature — it's how people *guess* your syntax correctly on the first try.
2. **One obvious way.** Each concept gets exactly one spelling. The moment there are two ways to say the same thing, people argue about which is "right".
3. **No context-dependent surprises.** A token may carry different meanings in unambiguous contexts (e.g. `()` as unit, empty params, or empty call args), but never in a way that isn't obvious from its surroundings.
4. **The happy path is the short path.** The thing people do most often should be the smallest thing to type.
5. **Do work only where the information lives.** Each pass does what it has the information to do, no earlier: the lexer/parser build *structure*, not *values*. Raw text is kept until a type is known — e.g. `Number.value` stays a string, and numeric conversion happens in the constant-folding pass where the target type exists. Deferring work to the right pass avoids premature decisions, precision loss, and rework.

## The consistency / familiarity tension

Consistency and familiarity sometimes pull against each other. Pure consistency invents syntax nobody has seen; pure familiarity produces a C clone. The sweet spot: **consistent inside the language, familiar where people already have expectations.** Borrowing `::` from Odin is exactly that.

## Decisions that serve the north star

- **Everything is an expression** — no statements. What you'd call a statement is an expression returning unit. One grammar concept.
- **`::` name-first declarations** — the Wirth/Odin way: `x :: 5`, `main :: proc() {}`.
- **Keywords are hard, by default.** `proc` is a `Keyword` union member (not an identifier), and every future keyword (`scoped`, `defer`) is added the same way: reserved where it lexes rather than context-dependent. Revisit only if it causes pain — making a word non-reserved is a breaking change to any program that used it as a name, so the default is the safe one.
- **Constants may reference forward.** `GiB :: 1024 * TiB` is legal with `TiB` declared later — no forward declaration, no ordering ceremony. This is free: the parser never resolves names (an `Ident` is order-agnostic), so the rule only constrains the constant-folding pass to not assume source order. The one cost: a cyclic chain (`A :: B; B :: A`) is a source error diagnosed at fold time, never a hang or a panic.
- **Newline = pure separator.** Newlines separate expressions and carry no value semantics. A block's value is its last expression; to "return nothing", end with a unit expression.
- **Blocks are values and scopes.** `{ ... }` composes like any expression and is a scope; scoped defers will ride on blocks.
- **`scoped` resources are core.** The declarative, block-scoped resource model — `File :: scoped { file_open, file_close }`, `File("data.txt") { ... }` — is the language's reason to exist, not a convenience. See [scoping.md](scoping.md). (The *pairing* itself isn't novel — Odin's `deferred_*` ship it; what gauge adds is the caller-chosen gate, `ok` in the body, and the block value.)
- **`()` is unit.**
- **Byte offsets everywhere.** Positions are byte offsets, never line/col — one position model through the whole toolchain.
- **No preprocessor.** `when`/constants take its place, the way the Pascal/Modula/Oberon line (and Odin) avoid one.

## Deferred / open

- **Discard sugar** — how to explicitly drop a value; decision pending (Rust uses `;`, we may want a different spelling).
- **Comptime.** Odin has no general comptime (`#run` does not exist); it offers `when`, `#assert`, and constant evaluation. For gauge, compile-time-ish work happens via a *pre-compile program* — an external tool importing the exported `lexer`/`parser` packages. A real comptime system would mean writing an interpreter for the language, which is a later-phase decision.
- Types (`x: int`), multi-char operators, `if`/`while`/`return` as expressions, typed params, structs/unions/enums, `^` pointer syntax, and multi-line expressions.

## Lineage

Odin describes itself as more derived from Pascal than from C, and the same lineage informs gauge:

- **From the Wirth school** (Pascal → Modula-2 → Oberon): name-first declarations, strong distinct typing, no preprocessor, package-as-module, explicitness and simplicity.
- **From C**: operators (`=`, `==`, `&`, `*`), braces, pointers, manual memory, low-level control, C ABI interop.

Pascal gives the grammar; C gives the metal.

## Resources

### The Wirth school

- [Niklaus Wirth's homepage](https://people.inf.ethz.ch/wirth/) — Oberon reports and his publications
- *Programming in Modula-2* (Wirth)
- *Programming in Oberon* / The Oberon Report
- *Good Ideas, Through the Looking Glass* (Wirth)

### gingerBill / Odin

- [gingerbill.org](https://www.gingerbill.org/) — blog
  - [On the Aesthetics of the Syntax of Declarations](https://www.gingerbill.org/article/2018/03/12/on-the-aesthetics-of-the-syntax-of-declarations/) — the `::` / Pascal declaration design
  - [Does Syntax Matter?](https://www.gingerbill.org/article/2026/02/21/does-syntax-matter/)
  - [The Metaprogramming Dilemma](https://www.gingerbill.org/article/2016/12/01/the-metaprogramming-dilemma/) — why Odin has no general comptime
- [Odin documentation](https://odin-lang.org/docs/overview/)

### Clay — Nic Barker

[Clay](https://github.com/nicbarker/clay) is a high-performance UI layout library in C by **Nic Barker** ([nicbarker.com](https://www.nicbarker.com), [@nicbarkeragain](https://twitter.com/nicbarkeragain)).

Clay's `CLAY(...)` macro is the relevant design note: C cannot express a nested, declarative element tree directly, so the macro wraps designated initializers plus block nesting to give you one — "this macro isn't magic, all it's doing is wrapping the standard designated initializer syntax." Nic has talked about wanting to see that element tree from the stack (the layout tree living in a contiguous arena), and how the macro is the only way C lets you build it — a good case study for why a language with a real expression/block grammar beats macro hacks.
