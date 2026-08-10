# TODO

The build roadmap. Design docs live in `docs/`; this tracks what gets built.

## Next

- [ ] **Blocks and procedures** — `{ ... }` blocks and the `proc` dispatch
      (`name :: proc() { }`). The `proc` keyword, the `Block`/`Proc` AST
      shapes, and the two disabled proc tests already exist; `parse_block` and
      `parse_args` are `todo` stubs and `parse_decl` panics on `proc`.
- [ ] **`defer`** — block-scoped, LIFO, cleanup on every exit path. This is the
      machinery `scoped` rides on, and the most important piece of the
      language.
- [ ] **`scoped` resources** — the reason gauge exists (see
      `docs/scoping.md`): declarative, block-scoped resource pairs, with the
      failure gate and value-producing destructors. Built on top of `defer`.

## Done

- [x] Lexer (`lexer/`) — cursor-based, byte offsets, newline tokens,
      `//` comments, escape-aware strings, `(u8, bool)` peek/advance.
- [x] Package split (`lexer/`, `parser/`) with table-driven lexer tests.
- [x] Design docs — `docs/design.md` (north star + principles),
      `docs/scoping.md` (the scoped model, RAII comparison, risks),
      `docs/scoping_examples.md` (Dear ImGui + Clay walk-throughs).
- [x] **Basic parser (consts, types, expressions)** — recursive descent for
      declarations, Pratt for expressions, producing the AST in `parser/`.
      Inferred and typed consts, the type grammar (`^int`, `^^int`), binary
      `+ - * /`, unary `-` (floor 25), and grouping all land with specs.
      Blocks, proc dispatch, calls, and assignment are the next slices.
- [x] **AST memory model** — the arena wins: every parse function and
      constructor threads the allocator explicitly (a dropped allocator is a
      compile error), tests allocate per-test dynamic arenas, and an
      allocator-discipline test guards the threading. See `spec/language.md`
      §11.12–11.13.

## Later (deferred by design)

- Calls and assignment, `()` unit, variables (`:=`), slices, tuples, unions,
  generic types, multi-char operators, `if`/`while`/`return` as expressions,
  typed params, structs/unions/enums, discard sugar, metaprogramming/comptime
  decisions, C codegen.
