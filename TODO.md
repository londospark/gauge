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
  but `parse_infix` rejects them with "not implemented yet" errors
  (ARB 0001); the call-side `parse_args` lands with this slice (the
  signature parens are consumed by `parse_params`). Re-enables
  `test_parse_multiline_args` and `test_parse_proc_body` (Equals arm);
  multi-line argument lists are pinned by the former (§11.16).
- **`()` unit value** — the `Unit` node exists in the AST; `()` is
  currently a source error.
- **Variables** — `x := expr` and `x : Type = expr`; same optional type
  slot as consts, different binder. Plus the ZII default-init form
  `x : Type` (§11.19) — zero-initialised, no explicit initialiser.
- **Slices** — `[]T`; carries the string-type fork. §11.17 settles the
  representation (pointer + length); whether strings are a distinct
  builtin or `[]u8` is decided here.
- **Discriminated unions** — first-class DUs with exhaustive `switch`;
  syntax explored in `docs/type_system.md` §6. (Tuples are refused —
  see §4 of the same doc.)
- **Generic types** — parametric polymorphism; the HM generalisation in
  `docs/type_system.md` §3 is the foundation.
- **Multi-char operators** — `->`, `:=`, `==` and friends; lexer, token
  table, and precedence rows together.
- **`if` / `while` / `return` as expressions** — everything-is-an-expression
  stays true.
- **`switch`** — exhaustive matching for DUs; pulled in by the DU slice
  (`docs/type_system.md` §6).
- **Typed parameters** — `proc(x: int) -> int`; the syntax is recorded in
  §5.3, and `parse_params` grows the `name : type` list when this lands.
- **Multiple return values** — `-> (int, string)` return lists,
  `a, b := f()` multi-binding; no tuple type. See `docs/type_system.md`
  §4.
- **Structs / enums** — user-defined types. (Unions are DUs — see
  `docs/type_system.md` §6.)
- **Discard sugar** — `_`-binding and friends.
- **Metaprogramming / comptime** — a decision point, not yet an
  implementation.
- **Semantic checker** — the pass after the parser: name resolution, HM
  typing, and constant folding. Designed in `docs/type_system.md`; build
  order in its §10. Lands as a pass inside the single `compiler/`
  package, not a new package boundary.

## Next up

- **Error recovery and multi-diagnostic reporting** — `lex` and `parse`
  fail fast today: the first
  error is the only error, so one bad declaration hides the rest of the
  file. Style guide §2 always scheduled this ("recovery is a later
  feature"). First slice: panic-mode recovery resyncing at the
  declaration boundary — on error, discard tokens until the next
  declaration start (the two-token `Ident` + `:` lookahead), absorbing
  any stray closers along the way, so N bad declarations yield N errors
  and the good ones still parse. Newlines are *not* the sync point:
  inside an unclosed zone the pre-pass has already dropped them, so a
  newline-based resync would miss the true declaration start; the resync
  set stays token-based (`Ident` `:` lookahead). Declarations are
  line-bounded (§11.16) — one per line — but that only makes a newline a
  boundary at depth 0, which is precisely where recovery cannot rely on
  it. One error per
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

- Lexer — cursor-based, byte offsets, newline tokens,
  `//` comments, escape-aware strings, `(u8, bool)` peek/advance.
- Package split with table-driven lexer tests — later consolidated into
  the single `compiler/` package.
- Design docs — `docs/design.md` (north star + principles),
  `docs/scoping.md` (the scoped model, RAII comparison, risks),
  `docs/scoping_examples.md` (Dear ImGui + Clay walk-throughs),
  `docs/type_system.md` (semantic checking: HM + value restriction,
  multi-return, distinct types, DUs, casts).
- **Basic parser (consts, types, expressions)** — recursive descent for
  declarations, Pratt for expressions, producing the AST in `compiler/`.
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
  no, and a declaration occupies its line — value (if any) on the same
  line as the binding marker, one declaration per line.
  The OCaml-ward future path (trailing-operator continuation only, a
  meaning-preserving relaxation) and the lesson are recorded in §11.16, and
  the end-to-end tests pin the pipeline.
- **C codegen (first slice: consts + expressions)** — the first backend
  emits C from the AST, no IR; `cc` is the runtime. The walker covers
  Number (int/double split by the trailing dot), Identifier references,
  Unary and Binary with bracket-everything (the `--` hazard), and consts
  emit in dependency order via a work-list over `is_ready` — cycles and
  undefined references fall out of the same stall→fallback mechanism, and
  cc reports them (§11.20). The demo goes gauge source → C → `cc` → a
  running binary (prints `result = 1073741824`), proven by two e2e tests
  (`cc -c` accepts the output; the KiB chain compiles and runs). Refinements
  for when the scale bites: an emitted-membership map
  (`map[IdentifierToken]bool`) and Kahn's/DFS with cycle-path diagnostics.
  Strings emit as the §11.17 pointer + length pair later; the backend grows
  with the blocks, procs, calls, and assignment slices.
- **Blocks and procedures** — `{ ... }` blocks with the §11.16 statement
  loop (a statement occupies its line, ending at a newline or `}`) and the
  `proc` dispatch (`name :: proc() { }`), including the typed-slot form.
  The block statement tests are green; `test_parse_proc_body` and
  `test_parse_multiline_args` re-enable with the calls/assignment card.
  Unimplemented parser paths return errors, not panics (ARB 0001);
  `parse_params` consumes the signature parens until typed parameters land
  (§5.3).
