# TODO

The build roadmap. Design docs live in `docs/`; this tracks what gets built.

## Next

- [ ] **Basic parser** — recursive descent for declarations/blocks, Pratt for
      expressions, producing the AST in `parser/`. Something we can work with
      before the harder features.
- [ ] **AST memory model** — allocation and cleanup of the parsed tree.
      Leaning toward an arena (allocate everything from one arena, free it in
      one shot) rather than a walk-and-free; revisit once the parser produces
      real trees. Tests currently use `context.temp_allocator` to sidestep it.
- [ ] **`defer`** — block-scoped, LIFO, cleanup on every exit path. This is the
      machinery `scoped` rides on, and the most important piece of the
      language.
- [ ] **`scoped` resources** — the reason londolang exists (see
      `docs/scoping.md`): declarative, block-scoped resource pairs, with the
      failure gate and value-producing destructors. Built on top of `defer`.

## Done

- [x] Lexer (`lexer/`) — cursor-based, byte offsets, newline tokens,
      `//` comments, escape-aware strings, `(u8, bool)` peek/advance.
- [x] Package split (`lexer/`, `parser/`) with table-driven lexer tests.
- [x] Design docs — `docs/design.md` (north star + principles),
      `docs/scoping.md` (the scoped model, RAII comparison, risks),
      `docs/scoping_examples.md` (Dear ImGui + Clay walk-throughs).

## Later (deferred by design)

- Types (`x: int`), multi-char operators, `if`/`while`/`return` as
  expressions, typed params, structs/unions/enums, `^` pointer syntax,
  discard sugar, metaprogramming/comptime decisions, C codegen.
