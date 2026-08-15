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

### 5.3 Procedures

`identifier : [type] : proc ( params ) block` — the `proc` keyword is lexed
and recognised; the dispatch and blocks are implemented. A block body is a
newline-separated statement list (§11.16): a statement occupies its line,
ending at a newline or the block's `}`. The parameter list is not — today
`parse_params` consumes the empty `( )`, and typed `name : type` parameters
land with the typed-parameters slice.

A parameter is `name : type`, using the type grammar of §6. The list is
comma-separated and may be empty: `proc()` declares zero parameters and is
*not* the `()` unit value (that is a separate slice). Proc signatures are
explicitly typed (type_system.md §3) — unannotated recursive parameters are
where HM inference goes undecidable-ish.

Deferred, with the slices that provide them:

- **Default values** — `name : type = default`, reusing the `=` initialiser
  of §5.4's `x : type = expr` form; `=` is already a token, so defaults add
  no lexing.
- **Inferred parameters** — `name := default`. The `:=` token needs the
  multi-char operator slice, and inference without a default has no type
  source, so this is a defaults variant, not standalone syntax.

The signature parens are zones (§11.16), so a multi-line parameter list
parses with no extra machinery — the same payoff call arguments get. Return
lists (`-> (int, bool)`) land with the multiple-return-values slice
(type_system.md §4); the signature has room for them after the parens.

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

- **Panics are compiler bugs** — a violated invariant, or out of memory. An
  unimplemented path reached with valid input is *not* one of these: it
  returns `ok = false` with a message that says so plainly (ARB 0001), e.g.
  "Procedure declarations are not implemented yet (byte 8)".
- **`ok = false` with a message on the receiver is a source bug** — or an
  unimplemented feature; the message says which.
- Diagnostics are grammatical sentences, capitalised, positions reported as
  bytes: `Expected an expression at byte 12, got Star`. A not-implemented
  error says "X is not implemented yet (byte N)" — the source is valid, so
  "Expected" would blame the program for the compiler's gap.

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

Calls, assignment, `()` unit, variables (`:=`), slices, tuples, unions,
generic types, multi-char operators, `if`/`while`/`return` as expressions,
typed parameters, discard sugar, and comptime.

See [TODO.md](../TODO.md) for the build roadmap. The type system —
semantic checking, HM with value restriction, multiple return values,
distinct types, discriminated unions, and casts — is designed in
[docs/type_system.md](../docs/type_system.md), ahead of its
implementation.

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
`parse_infix` arms. Resolved: `parse_infix` rejects the armless rows with a
"not implemented yet" error (ARB 0001) before `to_binary_operator` ever
sees them, so a future `x = 5` fails loudly instead of silently parsing as
`x + 5`. `to_binary_operator` keeps its invariant panic for anything that
slips past the Pratt loop's binding-power guard. Assignment stays deferred
until it becomes important.

### 11.15 The identifier dispatch and continuation must agree

**Lesson.** The lexer dispatches identifier *starts* by a switch on the first
character, and continues via `is_allowed_in_identifier`. The two must agree:
when the continuation predicate gained `_`, the start switch still lacked a
`case '_':`, so `_proc` was "Unrecognised character". A comprehensive
identifier test caught it — one rule, two places, and the tests are the
only thing keeping them in lockstep.

### 11.16 Multi-line expressions: paren-zone continuation

**Status.** Decided — paren-zone continuation (option 2 below), adopted. The
question surfaced from `x :: (4 + 2 +` newline `3 + 5)` failing today: the
Pratt loop stops at a `NewLine` because no `NewLine` has binding power, so an
expression was single-line *by accident, not by rule* — a default, not a
choice. The options below stay as the historical record; the decision, the
future path, and the lesson follow at the end of the entry.

**The options.**

1. **Status quo** — expressions are one line. Predictable, and the
   trailing-operator invariant stays airtight. Against: long expressions and
   `f(a,` newline `b)` argument lists are real UI-style patterns; this does
   not age well.
2. **Paren-zone continuation** (Python's model) — inside `( )` and `[ ]`
   newlines are insignificant; outside them, a newline ends the expression.
   `x :: (4 + 2 +` newline `3 + 5)` parses; the paren-less version is an
   error. For: explicit, standard, no machinery, and the recommendation.
   Against: an unclosed `(` swallows following declarations into the zone
   (Python's well-known pain) unless recovery guards it.
3. **Incompleteness continuation** (Haskell/OCaml's model) — a newline is
   absorbed whenever the expression cannot be complete: a trailing operator
   continues, and so does a complete line before a leading operator. For:
   the most permissive, no parens required. Against: every syntax error
   becomes a potential declaration-swallowing incident (`x :: 4 +` and the
   next line is eaten as the operand) — the failure mode to refuse.

**Why option 2 (tentatively).** `{ }` must *not* become zones, or block
statements would need `;` — which gauge deliberately does not have. Option 2
keeps blocks newline-separated and `;` out of the language, preserves the
trailing-operator invariant (continuation requires explicit parens, so
`test_parse_rejects_trailing_operator` survives), and gives the deferred
call slice multi-line argument lists for free.

**Recovery interaction.** Multi-line expressions change the resync set, not
the resync rule: inside an open zone, resync on the matching closer;
otherwise on declaration start (`Ident` `:` lookahead). The zone-depth bit
lives in the pre-pass, not the parser — recovery re-derives it from the raw
token stream. Unclosed-zone swallowing is the hazard; declaration start must
stay a hard sync even inside a zone.

**The deciding question.** May an expression continue across a newline
*without* parens when the previous line ends complete — is `x :: 4 + 2`
newline `+ 3` legal? Python says no; Haskell says yes. The answer picks the
model. The lexer is untouched either way — `NewLine` is already a token;
this is purely the parser's "does a newline end this expression?" judgement
(see AGENTS.md).

**Decision.** Paren-zone continuation — newlines are insignificant inside
`( )` (and, later, `[ ]`); outside them a newline ends the expression. The
deciding question answers **no**: `x :: 4 + 2` newline `+ 3` is an error.
`{ }` does *not* become a zone, so blocks stay newline-separated and `;` stays
out of the language. The trailing-operator invariant survives unchanged:
`x :: 4 +` newline `2` is still an error, because outside a zone the newline
ends the expression and the dangling `+` grabs no right operand.

A declaration occupies its line. The header and the value (if any) start
on the same line as the binding marker — `x ::` newline `(3 + 4)` is an
error, because the newline ends the declaration header and a value on the
next line has no header to attach to — and the declaration ends at the
next newline: `x :: 5 y :: 6` is an error too, one declaration per line.
(The header rule fell out of `parse_decl`'s type-slot disambiguation —
the newline is neither `::` nor a type — while the tail rule is a new
check in the parse loop. A default by accident and a deliberate
completion; both are now rules.)

Blocks inherit the same rule: a statement occupies its line, ending at a
newline or the block's `}`. The escape hatch for putting more than one
statement on a line is `;` — recorded, and deliberately deferred: the
newline model is primary, and `;` is an unrecognised character until the
day it is claimed.

**Implementation.** The decision lands as `zoning_pre_parse`, a token-
filtering pre-pass at the head of `parse`: `NewLine` tokens are dropped
while its paren depth is > 0, the depth clamps at 0 (a stray `)` poisons
nothing), braces never touch the counter, and offsets ride on the tokens so
dropping a newline disturbs nothing. The parser itself is the untouched
single-line parser — newline significance is decided entirely before it
runs, and the lexer is untouched as promised above.

**Future path — OCaml-ward, trailing-operator continuation only.** If gauge
ever relaxes toward incompleteness continuation, the intended variant
continues an expression *only when the current line ends incomplete*: a
trailing operator absorbs the newline and the next line becomes its operand,
with no parens required (`x :: 4 +` newline `2` becomes `4 + 2`). A complete
line never triggers continuation — there is no lookahead past the newline —
so `x :: 4 + 2` newline `- 3` stays two statements (the second a bare unary
expression) and the deciding question still answers **no**. Because the only
newly-legal program is the trailing-operator case (an error today), the move
is a strict relaxation that changes the meaning of no currently-legal
program. The *full* incompleteness model — Haskell/OCaml's rule that a
complete line before a leading operator also continues — is deliberately not
the target: there, `4 + 2` newline `- 3` silently merges into `4 + 2 - 3`,
turning a bare unary statement into a subtraction. A meaning change that
needs no parens is the failure mode to refuse.

**Lesson.** The pre-decision behaviour was a parser *default* dressed as a
rule: no `NewLine` had binding power, so the language was single-line by
accident. A default is a language decision and deserves an explicit ruling.
The sequel: when weighing a relaxation, enumerate what becomes legal. A
relaxation that only turns errors into programs is safe; a relaxation that
re-parses currently-legal programs is a breaking change in disguise. The
trailing-operator-only variant is the former; the full incompleteness rule is
the latter.

### 11.17 Strings are pointer + length, never C strings

**Decision.** gauge compiles to C, but gauge strings are *not* C strings. A
string is a `(data: ^u8, len: int)` pair — pointer plus byte length, exactly
Odin's `string` — in the language, in the AST, and in the generated C.
NUL-termination is a conversion applied only at FFI boundaries, never a
property of the string itself.

**Why.** The same reasons Odin does it:

- **Length is a fact, not a scan.** `strlen` is O(n) on every use and lies
  about the size of anything containing a NUL byte. The pair makes length
  O(1) and intrinsic.
- **Slicing is free and safe.** A substring is an O(1) pointer/length
  adjustment — no copy, no terminator surgery — and bounds are checkable
  against the carried length.
- **NUL is data.** A string may contain `\0`; the length says where it
  ends. C strings make that unrepresentable.
- **The security argument.** Buffer overruns in C are overwhelmingly
  length-handling bugs; the pair removes the whole class at the type level.

**The boundary rule** (Odin's `cstring` story): interop with a C API
converts at the edge — append the terminator there, on the way out, and
trust nothing C hands back without measuring it. The lexer already embodies
the decision: `StringLiteral` values are zero-copy slices of the source
(§3.4), so the front end was pointer + length before this entry was
written.

### 11.18 Call syntax: brackets, positional now, labelled later

**Decision.** Calls use bracket syntax — `f(a, b)`, the shape of the deferred
`ECall` rule, the `LParen` (30,30) binding-power row already in the table,
and the paren-zone makes `f(a,` newline `b)` legal with no new machinery
(§11.16's promise). Arg lists are positional today; labelled (keyword) args
— `f(a, key: value)` — are the deliberate extension, deferred with the call
slice. Positional args precede labelled ones (Swift's rule), so
`f(a, key: v)` is legal and `f(key: v, a)` is not.

**Why brackets.** The alternatives were refused on collisions with committed
decisions, not on taste:

- **S-expressions** (`(f a b)`) collide with grouping: `( )` is already the
  paren-zone construct, `(f)` is genuinely ambiguous, and the whole
  precedence grammar would be replaced. A different language, not a call
  syntax.
- **Juxtaposition** (`f a b`) breaks one-line multi-declarations — `x :: a
  y :: 6` is two declarations today, and under juxtaposition becomes the
  call `a(y)` before choking on the `::`. It also needs layout rules the
  newline model refused (§11.16) and an invisible binding-power row the
  Pratt loop cannot see.
- **Bare Smalltalk messages** fight the newline model (a message is a
  multi-token sequence, and a newline ends it mid-message) and presume an
  object/message paradigm gauge does not have.

**Why labelled args are unambiguous.** `:` has no expression-operator role —
it is absent from `binding_power` and `parse_prefix`, and the type-slot
colon appears only in declaration headers, which never nest inside
expressions. So inside call parens, `Ident` `:` can only be a labelled-arg
separator; the parser claims dead territory. `)` can never be an operator
either: it terminates the current zone at all times, which is what lets the
group and call arms trust zone termination.

**The `()` wrinkle.** `f()` is a zero-arg call; `()` is the deferred Unit
value — position disambiguates (a paren directly after the callee is a
call). Whether `()` is a passable value is a question for the Unit card.

### 11.19 Zero initialisation is the default (ZII, not RAII)

**Decision.** Values are zero-initialised by default. The binding form is
the type slot with no initialiser: `X : int` declares an int binding
initialised to 0. Gauge employs ZII rather than RAII: no constructor/
destructor pairs implicitly acquire and release; a zero value is defined
and inert, initialisation is an explicit step, and cleanup is the
`defer`/`scoped` machinery (docs/scoping.md). A consequence: a value that
was never successfully initialised is still defined (zero) — there is no
undefined state to trip over.

**Status.** Deferred with the variables card — `DeclVarZ` is a deferred
rule in grammar.cf, and `x : T = expr` (`DeclVarT`) already covers
explicit initialisation. Open at implementation time: the AST shape (a
Var node carrying the zero default) and how the failure gate reports a
failed acquisition (an error return vs a zero value).

### 11.20 Codegen: value domain and the first backend

**Decision.** The first backend emits C, straight from the AST, with no
IR — `cc` is the runtime, so gauge programs compile and run. The
provisional value domain: dotless numbers emit as C `int`, dotted numbers
as `double`, literals verbatim; C's implicit conversions bridge the split.
Const references fold at emission: a const's initializer substitutes the
referenced const's already-emitted value, so every initializer is a true C
constant expression — C `const` objects are *not* constant expressions
(MSVC rejects `static const int y = x;` with C2099; gcc/clang accept the
reference form as an extension), and emission is dependency-ordered, so
the referenced value is always already known. An undeclared or cyclic
reference has no folded value and emits its name verbatim, for cc to
report. Strings emit as the §11.17 pointer+length pair, never C strings —
the compiler computes the length at compile time.

**The codegen entry point** takes the AST and the allocator (§11.12) and
returns C text with no error return: codegen-visible failures — undeclared
identifiers, duplicate declarations, dependency cycles — are delegated to
cc, which reports them (in gauge coordinates once §11.21's `#line` lands).
The error handler is the C compiler.

**Forward references.** Consts may reference forward (§11.3); C demands
declaration-before-use. Because gauge consts are pure, the emitter orders
declarations by dependency (a topological sort over identifier
references) — a semantics-preserving reordering.

**Backends.** C is the first of potentially several. One backend emits
from the AST; the *second* backend is what earns an IR — the refactor to
AST → IR → backends happens then, never before. The optimising-backend
landscape, for when the choice arrives: LLVM (best codegen, heavyweight
commitment — when the language is real), Cranelift (fast, embeddable,
good-enough codegen; the JIT/embedded choice), QBE (a few-thousand-line
SSA backend for hobby compilers — the learning choice), libgccjit
(awkward but real), a bytecode VM (instruction design, semantics made
precise — a compiled backend, distinct from the rejected tree-walker),
WASM (a constrained target; pointer+length strings map onto linear
memory), and native asm (the deepest, slowest; ill-suited to a C-interop
language's FFI tax). Until then, `cc -O2` is the optimising backend: C
emission delegates optimisation to the C compiler by design.

### 11.21 Debug info: debug the gauge source, not the generated C

**Decision.** Gauge programs debug at the gauge-source level. The
mechanism is the source-to-C trick: the codegen emits `#line` directives
mapping each generated line back to its gauge source file and line, and
`cc -g` records gauge coordinates in the debug metadata — GDB steps
through gauge lines and breaks on gauge source. On Linux the container is
DWARF; on Windows/MSVC it is PDB; the format is the target's business,
and the same `#line` mechanism feeds both.

**The offset→line boundary.** Gauge positions are byte offsets; debug
metadata wants line numbers. The codegen consults a source line table
(offset → line) built when the source loads — the same convert-at-the-
boundary pattern as §11.17's cstring story: offsets stay the internal
truth.

**Discipline.** Keep the first codegen dumb for the debugger's sake:
emit gauge identifiers verbatim (GDB shows `KiB`, not `g_17`), compile
with `-g -O0`/`-Og` so the mapping stays 1:1. Variable-level inspection
works while gauge values map directly to C objects; it degrades the
moment codegen does clever transforms — decide deliberately before
getting clever. Full hand-rolled DWARF (types, locations, live ranges) is
only worth it when the front end outgrows the C mapping, and then ideally
via LLVM's DIBuilder if that backend ever exists. A bonus: `#line` makes
cc's diagnostics point at gauge source too — the semantic-checker-is-cc
story gains gauge-coordinate errors.
