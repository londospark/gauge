# TODO

The build roadmap, kept as a kanban board: every item has a position, and
nothing sits in two places. Design docs live in `docs/`, the design itself
lives in `spec/` — this file tracks *status* only.

**How the board moves**

- An item enters **In progress** the moment its first edit lands.
- An item reaches **Done** when the vertical slice ships: tests green,
  spec synced (AGENTS.md), committed, pushed.
- **Backlog** holds everything unstarted; **Next up** is the ordered queue.
- Status lives in the column heading, never in checkboxes.
- The board is tracking, not specification — when it disagrees with a
  spec, the spec wins.

## Backlog

Deferred language features mirror `spec/language.md` §10; recorded design
decisions live in §11.

- **Calls and assignment** — `f(x)` and `x = expr` have binding-power rows
  but no `parse_infix` arms; `parse_args` is a `todo` stub. Multi-line
  argument lists depend on the §11.16 answer.
- **`()` unit value** — the `Unit` node exists in the AST; `()` is
  currently a source error.
- **Variables** — `x := expr` and `x : Type = expr`; same optional type
  slot as consts, different binder.
- **Slices** — `[]T`; carries the string-type fork. §11.17 settles the
  representation (pointer + length); whether strings are a distinct
  builtin or `[]u8` is decided here.
- **Tuples, unions, generic types** — composite types for the type
  grammar.
- **Multi-char operators** — `->`, `:=`, `==` and friends; lexer, token
  table, and precedence rows together.
- **`if` / `while` / `return` as expressions** — everything-is-an-expression
  stays true.
- **Typed parameters** — `proc(x: int) -> int`; grows the deferred proc
  forms of §5.3.
- **Structs / unions / enums** — user-defined types.
- **Discard sugar** — `_`-binding and friends.
- **Metaprogramming / comptime** — a decision point, not yet an
  implementation.
- **C codegen** — compile to C. Strings ship as pointer + length, never C
  strings (§11.17).

## Next up

- **Blocks and procedures** — `{ ... }` blocks and the `proc` dispatch
  (`name :: proc() { }`). The `proc` keyword, the `Block`/`Proc` AST
  shapes, and the two disabled proc tests already exist; `parse_block` and
  `parse_args` are `todo` stubs and `parse_decl` panics on `proc`.
- **Error recovery and multi-diagnostic reporting** *(starts after
  blocks + procedures)* — `lex` and `parse` fail fast today: the first
  error is the only error, so one bad declaration hides the rest of the
  file. Style guide §2 always scheduled this ("recovery is a later
  feature"). First slice: panic-mode recovery resyncing at the
  declaration boundary — on error, discard tokens until the next
  declaration start (the two-token `Ident` + `:` lookahead), absorbing
  any stray closers along the way, so N bad declarations yield N errors
  and the good ones still parse. Newlines are *not* the sync point:
  they are skipped noise at declaration level and meaningless inside
  groups/blocks, and `x :: 5 y :: 6` on one line is already legal, so
  a newline-based resync would skip real declarations. One error per
  declaration (cascade suppression) so recovery never becomes spew.
  `Parser.err` grows into a diagnostics slice (`{offset, message}`,
  byte-sorted) and `parse` returns them all. The demo stops discarding
  the parse result (a failed parse nil-derefs `program.decls` today)
  and prints every diagnostic. Open decisions at implementation time:
  lexer recovery (skip unrecognised chars; unterminated strings run to
  the newline — correct there because strings, unlike declarations,
  are line-constrained), statement-level sync inside blocks, and
  expression-level resync on `)`/`,`. language.md §8 lands in the same
  commit.
- **`defer`** — block-scoped, LIFO, cleanup on every exit path. This is the
  machinery `scoped` rides on, and the most important piece of the
  language.
- **`scoped` resources** — the reason gauge exists (see
  `docs/scoping.md`): declarative, block-scoped resource pairs, with the
  failure gate and value-producing destructors. Built on top of `defer`.

## In progress

*Empty — last through the points: unary plus (`b0da8d8`); the §11.16
multi-line decision lands with the paren-zone pre-pass in this commit.*

## Done

- Lexer (`lexer/`) — cursor-based, byte offsets, newline tokens,
  `//` comments, escape-aware strings, `(u8, bool)` peek/advance.
- Package split (`lexer/`, `parser/`) with table-driven lexer tests.
- Design docs — `docs/design.md` (north star + principles),
  `docs/scoping.md` (the scoped model, RAII comparison, risks),
  `docs/scoping_examples.md` (Dear ImGui + Clay walk-throughs).
- **Basic parser (consts, types, expressions)** — recursive descent for
  declarations, Pratt for expressions, producing the AST in `parser/`.
  Inferred and typed consts, the type grammar (`^int`, `^^int`), binary
  `+ - * /`, unary `-` (floor 25), and grouping all land with specs.
  Blocks, proc dispatch, calls, and assignment are the next slices.
- **AST memory model** — the arena wins: every parse function and
  constructor threads the allocator explicitly (a dropped allocator is a
  compile error), tests allocate per-test dynamic arenas, and an
  allocator-discipline test guards the threading. See `spec/language.md`
  §11.12–11.13.
- **Unary plus** — `+` joins `-` as a prefix operator. One shared
  `unary_binding_power` floor owns the value (style guide §7: magic
  numbers have one home); `to_unary_operator` mirrors
  `to_binary_operator`; four forcing tests pin the shapes. Committed
  `b0da8d8`.
- **Multi-line expressions settled (§11.16)** — paren-zone continuation
  adopted and implemented as `zoning_pre_parse`, a token-filtering pre-pass
  at the head of `parse`: NewLines inside parens are dropped before the
  parser runs, the depth clamps at 0 (a stray `)` poisons nothing), braces
  are never zones, and the lexer and parser are untouched. The deciding
  question — is `x :: 4 + 2` newline `+ 3` legal without parens? — answers
  no. The OCaml-ward future path (trailing-operator continuation only, a
  meaning-preserving relaxation) and the lesson are recorded in §11.16, and
  the end-to-end `integration/` suite pins the pipeline.
