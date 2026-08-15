# AGENTS.md

Guidance for AI agents and contributors working on gauge.

## Commands

All tools live in the project's devenv shell — there is nothing installed ad-hoc:

- Tests: `devenv shell --quiet odin test compiler/` — the whole compiler is one package, so one invocation runs every suite
- Run the demo: `devenv shell --quiet odin run .`
- Build: `devenv shell --quiet odin build .`
- Debug build: `devenv shell --quiet odin build . -debug`, then `devenv shell --quiet gf2 ./gauge`

## Workflow

- **Run the tests before every commit and push.** `devenv shell --quiet odin test compiler/` must pass; the suite lives in `compiler/` (`compiler/lexer_test.odin`, `compiler/parser_test.odin`, `compiler/integration_test.odin`, `compiler/codegen_test.odin`).
- **Scan for `@Note` before every commit.** Grep the code for `@Note` and review each one — confirm it's a deliberate design decision or flag it for action. Once a note is reviewed, mark it with a `// @Review:` resolution line so it's visibly settled; reviewed notes don't need re-reviewing on future commits.
- **Keep `spec/grammar.cf` and `spec/language.md` in sync before every commit.** Any change to lexer or parser behaviour — tokens, precedence, grammar, diagnostics, invariants — must be reflected in the spec, and the spec change lands in the same commit as the code it describes. An out-of-date spec is a broken signal, and the maintainer treats it as such.
  The two files have different jobs: `language.md` is the design and the
  destination — deferred features are described there ahead of the
  implementation; `grammar.cf` is the implementation snapshot, and its active
  rules must match the code exactly. When the two disagree, the code is the
  tiebreaker: fix `grammar.cf`, not `language.md`.
- When lexer behaviour changes, update the expected tokens in `compiler/lexer_test.odin` — offsets included.
- Keep the Sublime build systems (`gauge.sublime-project`) and `.project.gf` in sync with any command or debugger changes.
- Comments explain **why**, never restate the code.

## Voice

- The name **gauge** is a railway term, and the docs lean into it: steam-train puns are **welcome and encouraged** throughout the documentation.
- The maintainer is a member of the **Talyllyn Railway** (the world's first preserved narrow-gauge railway) — puns and references involving them are super, super welcome.
- Spellings are **UK English** throughout — in code and comments, in the docs and the spec, and in commit messages alike: *behaviour*, *colour*, *recognised*, *initialised*, *labelled*, *cancelled* — never their US spellings.

## Environment (the flake)

- All project tooling is declared in the devenv flake: `devenv.nix` (packages/tools) and `devenv.yaml` (inputs).
- **Any environment change must be reflected in the flake.** Adding a tool? Add it to `packages` in `devenv.nix`. Adding an input? Add it to `devenv.yaml` and run `devenv update`.
- Never install project tools ad-hoc (no `nix profile install`, no global packages).
- Odin comes from the `odin-nightly-flake` input (master build) via `languages.odin.package` — not the nixpkgs `odin`.

## Design notes

- Code semantics — panic-vs-error (compiler bugs vs source bugs), `(T, bool)` + `or_return` propagation, stub/`todo` conventions, `@Note`/`@Review` lifecycle — live in `docs/style_guide.md`. Significant semantic decisions are recorded as ARBs in `docs/arb/` (see its README).
- `Token` is `{ offset: int, value: ValueToken }`. Positions are **byte offsets**, never line/col.
- Newlines are explicit `NewLine` tokens; the parser decides if one ends a statement — `zoning_pre_parse` drops NewLines inside paren zones before the parser runs (§11.16).
- The lexer's `lex_peek`/`lex_advance` return `(u8, bool)` — `false` means EOF. Never use `0` as an EOF sentinel (NUL is a valid byte).
- `lex_identifier`/`lex_string`/`lex_number` return `(Token, bool)`; `lex` returns `(tokens, ok)` and stops on the first error.
- Line comments (`//`) are skipped by the lexer; `Slash` is only emitted when the `/` isn't followed by another `/`.
- String values are escape-aware (`\"`, `\\`) and are zero-copy slices of the source.
- The compiler is a single `compiler/` package — token types, lexer, parser, and codegen together; `main.odin` imports it by package path.

## Formatting (manual — there is no odinfmt)

Match the project's hand-aligned style:

- **Tabs** for indentation, one level per nest.
- `case` labels sit flush with their `switch`, never indented beneath it (the Odin stdlib convention).
- `::` for all declarations (constants, types, procedures).
- Align the **types** in successive field declarations and the `::` in successive type/constant declarations. Alignment applies only within a run of consecutive lines — a break (a blank line, a comment, or a scope end like `}`) ends the run, and what follows may use its own indentation:

  ```odin
  Identifier    :: distinct string
  Number        :: distinct string
  StringLiteral :: distinct string
  ```

  ```odin
  Lexer :: struct {
  	source:   string,
  	position: int,
  }
  ```

  ```odin
  Binary :: struct {
  	using node: Node,
  	lhs:        ^Expr,
  	rhs:        ^Expr,
  	operator:   BinaryOperator,
  }

  Node :: struct {
  	offset: int
  }
  ```

- Alignment is the editor's/agent's job: re-align affected blocks on every edit, even small or restricted ones.

- Align the `=` in multi-line struct/union literals.
- One space around binary operators; one space after commas.
- No space before `(` in calls or parameter lists: `proc(x: int)`, `fmt.println(x)`.
- `case X:` — no space before the colon.
- Keep lines under ~100 columns.
