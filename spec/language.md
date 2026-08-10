# gauge language specification

This is the specification of gauge as it stands. It describes what the front
end (lexer + parser) actually implements today; deferred features are marked
`(deferred)`. The grammar proper lives in [grammar.cf](grammar.cf), written in
LBNF (the BNF Converter formalism); this document explains the semantics and
records the design decisions.

> gauge is a railway-precision language: the track is the grammar, the
> signalbox is the parser, and everything deferred is a siding, not a
> dead end.

## 1. Purpose

gauge exists for the **declarative, scope-based resource model**: anything
with a begin/end lifecycle (a file, a window, a layout element, a frame) is a
first-class scoped block, and the same scope model powers immediate-mode UI
ergonomics. See [docs/scoping.md](../docs/scoping.md) for the full design.
Everything else in the language serves that feature.

## 2. Conventions

- **Positions are byte offsets**, never line/column.
- **Everything is an expression.** There are no statements; what looks like a
  statement is an expression returning unit.
- **Newlines are pure separators.** They separate declarations and
  expressions and carry no value semantics.
- **EBNF notation** in this document: `{ x }` = zero or more, `[ x ]` = zero
  or one, `"a" .. "z"` = character range. The grammar proper in `grammar.cf`
  is LBNF, where `[X]` means a list (zero or more) and optionals appear as
  paired rules (`DeclInferred`/`DeclTyped`).

## 3. Lexical structure

### 3.1 Identifiers

```
identifier = ( letter | "_" ) , { letter | digit | "_" } ;
```

An identifier starts with a letter (`a`..`z`, `A`..`Z`) or underscore and
continues with letters, digits, and underscores. A digit can never start one.

### 3.2 Keywords

Keywords are **hard** — reserved at the lexical level, not context-dependent.
The current keyword is:

| keyword | meaning                      |
|---------|------------------------------|
| `proc`  | procedure declaration marker |

Keyword matching is exact: `proc` is the keyword, `proc123` and `_proc` are
plain identifiers. Every future keyword (`scoped`, `defer`) is added the same
way — see [docs/design.md](../docs/design.md).

### 3.3 Numbers

```
number = digit , { digit } , [ "." , digit , { digit } ] ;
```

Integer and decimal literals (`42`, `3.14`). Values are kept as raw text in
the AST; conversion to a typed value happens in the constant-folding pass
(deferred). *Implementation quirk:* the lexer accepts a trailing dot (`3.`)
with zero fractional digits.

### 3.4 Strings

```
string = '"' , { string_char } , '"' ;
```

Double-quoted, escape-aware: a backslash escapes the following character
(`\"` and `\\` today; any `\x` pair is skipped). String values are
zero-copy slices of the source. An unterminated string is a source error.

### 3.5 Comments

`//` runs to the end of the line and is skipped by the lexer. A `/` not
followed by `/` is the `Slash` operator.

### 3.6 Newlines and punctuators

`\n` is an explicit `NewLine` token; the parser decides whether one ends a
declaration. The punctuator tokens are:

```
:  (  )  {  }  ,  =  +  -  *  /  ^
```

`::` is two `Colon` tokens (there is no single `::` token). `EOF` terminates
every token stream.

## 4. Program structure

```
program = { newline } , { declaration , { newline } } ;
```

A program is a sequence of declarations separated by newlines.

## 5. Declarations

### 5.1 Constants

```
declaration = identifier , ":" , [ type ] , ":" , expression ;
```

A constant binds a name to the value of an expression:

```
KiB :: 1024
MiB :: 1024 * KiB
scale : f64 : 2.5
```

- `x :: expr` — type inferred from the expression; the `Type` slot is empty.
- `x : Type : expr` — explicit type between the colons.

A `Const` node's AST type field is `nil` exactly when the form was inferred.

### 5.2 Forward references

Constants may reference later declarations: `GiB :: 1024 * TiB` is legal
with `TiB` declared afterwards. The parser never resolves names; name
resolution happens in the constant-folding pass, which must not assume source
order. A cyclic chain (`A :: B; B :: A`) is a source error diagnosed at fold
time, never a hang or panic. See [docs/design.md](../docs/design.md).

### 5.3 Procedures *(deferred)*

`identifier : [type] : proc ( ) block` — the `proc` keyword is lexed and
recognised, but the dispatch, parameters, and blocks are not yet implemented.

### 5.4 Variables *(deferred)*

`x := expr` and `x : Type = expr` use the same optional type slot; the
declaration binder differs from constants.

## 6. Types

```
type = "^" , type | identifier ;
```

A type expression is a chain of prefix markers ending in a named type:

| form | meaning |
|---|---|
| `int` | named type |
| `^int` | pointer to `int` |
| `^^[]string` | pointer to pointer to slice of string *(slice deferred)* |

The AST holds a type as a tree: `TypeName` (the leaf) or `TypePointer`
(recursive). A `TypePointer` node's offset is the byte of its `^`.

*(Deferred: slices `[]T`, tuples, unions, generic applications.)*

## 7. Expressions

### 7.1 Precedence

| level | operators | associativity |
|---|---|---|
| unary | `-` `+` | — |
| multiplicative | `*` `/` | left |
| additive | `+` `-` | left |
| assignment | `=` *(deferred)* | right |

The implementation is a Pratt parser; the binding-power table encodes the
same precedence:

| token | binding power (left, right) | status |
|---|---|---|
| `=` | (2, 1) | row present; `Assign` arm deferred |
| `+` `-` | (10, 11) | implemented |
| `*` `/` | (20, 21) | implemented |
| `(` | (30, 30) | row present; call arm deferred |
| unary `-` | operand floor **25** | implemented |
| unary `+` | operand floor **25** | implemented |

Associativity falls out of the asymmetry: `left < right` is
left-associative, `left > right` is right-associative. See
[docs/pratt_parsing.md](../docs/pratt_parsing.md).

### 7.2 Primary expressions

```
primary = number | string | identifier | "(" , expression , ")" ;
```

Grouping `( expr )` is an atomic unit; `()` is the unit value *(deferred —
currently an error)*.

### 7.3 Unary operators

The prefix operators are `-` and `+`. Both bind their operand at
binding-power floor 25 — strictly above `*`'s left strength (20) — decided
by the single `unary_binding_power` lookup, so the two signs share one floor
by construction and a second copy of the value can never drift in. Both are
wired into `parse_prefix` through one shared arm; `to_unary_operator` maps
the token to the AST operator. The forms:

```
-5         →  Unary(Minus, 5)
-2 * 3     →  (-2) * 3
-2 + 3     →  (-2) + 3
--5        →  Unary(Minus, Unary(Minus, 5))
+5         →  Unary(Plus, 5)
+-5        →  Unary(Plus, Unary(Minus, 5))
```

### 7.4 Calls and assignment *(deferred)*

`f(x)` and `x = expr` have binding-power rows but no `parse_infix` arms yet.
They will land together with their rows.

## 8. Diagnostics

- **Panics are compiler bugs** — an unimplemented path reached with valid
  input (`panic("todo: …")`), a violated invariant, or out of memory.
- **`ok = false` with a message on the receiver is a source bug.**
- Diagnostics are grammatical sentences, capitalised, positions reported as
  bytes: `Expected an expression at byte 12, got Star`.

See [docs/style_guide.md](../docs/style_guide.md).

## 9. Implementation invariants

- **Non-nil:** in a successfully-parsed tree, every pointer field that holds
  a child is non-nil. Constructors reject nil for required fields. The one
  deliberate exception is `Const.type` — `nil` means "inferred".
- **Offsets:** a node's offset is the byte of the token that created it — the
  operator for `Binary`, the `^` for `TypePointer`, the token itself for
  atoms and `Const`.
- **Allocators:** the allocator is threaded explicitly through every parse
  function and constructor; there are no defaulting allocator parameters.

## 10. Deferred features

Blocks, procedures, calls, assignment, `()` unit, variables (`:=`), slices,
tuples, unions, generic types, multi-char operators, `if`/`while`/`return`
as expressions, typed parameters, discard sugar, and comptime.

See [TODO.md](../TODO.md) for the build roadmap.

## 11. Design decisions and lessons learned

The reasons behind the choices above — each entry records the decision and
the lesson that produced it. If a future change overturns one, update the
entry, don't delete it; the history is the point.

### 11.1 `proc` is a keyword

**Decision.** Procedures are declared `name :: proc() { }`; `proc` is a hard
keyword, not a context-dependent marker.

**Why.** A keyword-free form (`main :: () { }`, Jai-style) requires the parser
to checkpoint, look past the parens, and commit only when `{` appears —
because `x :: (4 + 2) * 3` (grouping) and `main :: (x) { }` (proc) are
indistinguishable at the `(`. The keyword makes the dispatch a one-token
decision. It also names the *concept* "callable": `proc` is the function
type, so the keyword earns its keep as a type constructor, not just a
declaration marker.

### 11.2 Keywords are hard by default

**Decision.** Every keyword is reserved at the lexical level; none is
context-dependent. Revisit only if it causes pain.

**Why.** Making a word non-reserved later is a breaking change to every
program that used it as a name. Reserving up-front is the safe direction, and
matches Odin's model.

### 11.3 Constants may reference forward

**Decision.** `GiB :: 1024 * TiB` is legal with `TiB` declared later — no
forward declaration.

**Why.** Forcing declaration order is C-like ceremony with no payoff: the
parser never resolves names, so an `Ident` is order-agnostic by construction.
The cost is that cycles (`A :: B; B :: A`) become expressible; they are a
source error at fold time, never a hang or panic.

### 11.4 The type slot is a grammar, not an identifier

**Decision.** `type = "^" , type | identifier` — a recursive grammar, parsed
by a dedicated `parse_type`, not a single-identifier lookup.

**Why.** The naive reading ("one name between the colons") cannot express
composite types (`^int`, `^^[]string`) — and tuples, unions, and result types
will contain *multiple* identifiers with markers between them. Building the
grammar now means later composites slot in as new productions instead of a
retrofit.

### 11.5 Position decides role

**Decision.** A token's meaning is decided by its position: `(` at the start
of an expression is grouping, after an expression it will be a call; `-` and
`+` at the start are unary, between operands they are binary.

**Why.** This is what makes the grammar unambiguous without lookahead. It is
also why the proc dispatch must use the `proc` keyword rather than "`(` means
proc" — the `(` in `x :: (4 + 2) * 3` is unambiguously grouping, and only
the keyword can separate that from a signature.

### 11.6 Unary operators bind at floor 25

**Decision.** The operand of a unary operator is parsed at binding-power floor
25 — strictly above `*`'s left strength (20) — and the floor is supplied by
one `unary_binding_power` lookup serving both `-` and `+`, so the value lives
in a single place instead of an inline literal in `parse_prefix`.

**Why.** Parsing the operand at floor 0 drags lower-precedence operators
inside: `-2 * 3` becomes `-(2 * 3)`. The floor is the guard; the recursion is
the mechanism. Any floor strictly above 20 works today; 25 leaves headroom
above `*`/`/`.

### 11.7 Precedence and associativity are two numbers

**Decision.** Each operator carries an asymmetric pair `(left, right)`:
`left < right` is left-associative, `left > right` is right-associative.

**Why.** The pair is both precedence *and* associativity — the `right` value
acts as a tripwire that locks same-strength operators out of the right side,
so `10 - 3 - 2` folds left without a special case. No operator needs
`left == right`; a deliberate inequality makes the direction readable.

### 11.8 Odin's empty-case grouping is a trap

**Lesson.** `case A:` followed by an empty `case B:` does **not** share a body
in Odin — the empty case does nothing and falls out of the switch. Grouping is
the comma form: `case A, B:`.

**Why it bit us.** `binding_power` used stacked empty cases for `Plus`/`Minus`
and `Star`/`Slash`; `Plus` and `Star` silently returned `false`, breaking
every expression using them. The compiler caught nothing; only a probe did.

### 11.9 Union-switch exhaustiveness is a feature

**Lesson.** In a union switch, a `case:` default does **not** satisfy the
exhaustiveness check — every union member must be named, or the switch must
be `#partial`.

**Why it's good.** Adding a member to the token `Value` union broke every
switch that reads it, forcing each to confront the new token. That is the
boundary-typing principle enforced by the compiler: the vocabulary grew, and
the compiler demanded a decision at each switch.

### 11.10 A node's offset is its creating token

**Decision.** `Node.offset` is the byte of the token that created the node —
the operator for `Binary`, the `^` for `TypePointer`, the token itself for
atoms and `Const`. Never the start of the whole span.

**Why.** Pulling a span start out of the `Expr` union requires variant
switches; the creating token is already in hand and is the more precise
diagnostic target. The lesson: capture `token := current(p)` *before*
matching — reading `p.position` after `match_simple` yields the *token index*,
not a byte offset, and it is off by one past the matched token.

### 11.11 `#no_nil` constrains values, not pointers

**Lesson.** `#no_nil` on a union forbids an empty union *value*; it says
nothing about pointers to it. A `^Type` may be nil (that is how `parse_type`
signals failure), while no `Type` value can be empty.

**Why it matters.** `Const.value` must be non-nil in a successful tree, but it
cannot be a by-value `Expr`: the union is recursive (`Expr` contains `Const`,
which would contain `Expr`) — infinite size — so the pointer is structural,
and the guarantee is enforced by construction plus constructor nil-rejection.

### 11.12 The allocator is threaded, with no defaults

**Decision.** Every parse function and constructor takes
`allocator: mem.Allocator` — no `:= context.allocator` default.

**Why.** A default that is always overridden hides the contract and lets a
dropped allocator silently allocate from ambient context. Removing the default
makes the compiler enforce the threading: a dropped allocator is a compile
error. The caller owns the allocator (arena in tests, temp in the demo) and
the AST outlives the parse call, so the allocator cannot be ambient.

### 11.13 The test "leaks" were arena garbage

**Lesson.** Tests that parse into `context.temp_allocator` show `+++ leak`
reports because the runner resets the temp arena at the *start* of each test
but checks for leaks at the *end* — every test's AST is live at check time.
Not a real leak.

**Why the fix works.** Each test now allocates its own dynamic arena and
destroys it via a registered cleanup before the leak check — a balanced
alloc/free pair that satisfies the tracker.

### 11.14 The table and the arms must agree

**Lesson.** `binding_power` and `parse_infix` must cover exactly the same
operator set. The table admits `=` (2,1) and `(` (30,30) with no
`parse_infix` arms. Resolved: `to_binary_operator` now panics on an operator
it does not recognise, so a future `x = 5` fails loudly as a compiler bug
instead of silently parsing as `x + 5`. Assignment stays deferred until it
becomes important.

### 11.15 The identifier dispatch and continuation must agree

**Lesson.** The lexer dispatches identifier *starts* by a switch on the first
character, and continues via `is_allowed_in_identifier`. The two must agree:
when the continuation predicate gained `_`, the start switch still lacked a
`case '_':`, so `_proc` was "Unrecognised character". A comprehensive
identifier test caught it — one rule, two places, and the tests are the
only thing keeping them in lockstep.
