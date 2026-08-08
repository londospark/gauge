# AGENTS.md

Guidance for AI agents and contributors working on londolang.

## Commands

All tools live in the project's devenv shell — there is nothing installed ad-hoc:

- Tests: `devenv shell --quiet odin test lexer/ parser/`
- Run the demo: `devenv shell --quiet odin run .`
- Build: `devenv shell --quiet odin build .`
- Debug build: `devenv shell --quiet odin build . -debug`, then `devenv shell --quiet gf2 ./londolang`

## Workflow

- **Run the tests before every commit and push.** `devenv shell --quiet odin test lexer/ parser/` must pass; suites live next to their packages (`lexer/lexer_test.odin`, `parser/parser_test.odin`).
- **Scan for `@Note` before every commit.** Grep the code for `@Note` and review each one — confirm it's a deliberate design decision or flag it for action. Once a note is reviewed, mark it with a `// @Review:` resolution line so it's visibly settled; reviewed notes don't need re-reviewing on future commits.
- When lexer behaviour changes, update the expected tokens in `lexer/lexer_test.odin` — offsets included.
- Keep the Sublime build systems (`londolang.sublime-project`) and `.project.gf` in sync with any command or debugger changes.
- Comments explain **why**, never restate the code.

## Environment (the flake)

- All project tooling is declared in the devenv flake: `devenv.nix` (packages/tools) and `devenv.yaml` (inputs).
- **Any environment change must be reflected in the flake.** Adding a tool? Add it to `packages` in `devenv.nix`. Adding an input? Add it to `devenv.yaml` and run `devenv update`.
- Never install project tools ad-hoc (no `nix profile install`, no global packages).
- Odin comes from the `odin-nightly-flake` input (master build) via `languages.odin.package` — not the nixpkgs `odin`.

## Design notes

- `lexer.Token` is `{ offset: int, value: Value }`. Positions are **byte offsets**, never line/col.
- Newlines are explicit `NewLine` tokens; the parser decides if one ends a statement.
- `peek`/`advance` return `(u8, bool)` — `false` means EOF. Never use `0` as an EOF sentinel (NUL is a valid byte).
- In the `lexer` package: `lex_identifier`/`lex_string`/`lex_number` return `(Token, bool)`; `lex` returns `(tokens, ok)` and stops on the first error.
- Line comments (`//`) are skipped by the lexer; `Slash` is only emitted when the `/` isn't followed by another `/`.
- String values are escape-aware (`\"`, `\\`) and are zero-copy slices of the source.
- The `parser` package imports `../lexer`; everything else imports by package path.

## Formatting (manual — there is no odinfmt)

Match the project's hand-aligned style:

- **Tabs** for indentation, one level per nest.
- `::` for all declarations (constants, types, procedures).
- Align the **types** in consecutive field declarations and the `::` in consecutive type/constant declarations within a block:

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

- Alignment is the editor's/agent's job: re-align affected blocks on every edit, even small or restricted ones.

- Align the `=` in multi-line struct/union literals.
- One space around binary operators; one space after commas.
- No space before `(` in calls or parameter lists: `proc(x: int)`, `fmt.println(x)`.
- `case X:` — no space before the colon.
- Keep lines under ~100 columns.
