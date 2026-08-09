# Pratt parsing and binding power

A walkthrough of the expression parser gauge uses — precedence and
associativity encoded in two small numbers per operator.

## The problem

`2 + 3 * 4` must mean `2 + (3 * 4)` = 14, not `(2 + 3) * 4` = 20. The `*` has
to hold onto the `3` harder than `+` does. That strength is **precedence**.
And `10 - 3 - 2` must mean `(10 - 3) - 2`, not `10 - (3 - 2)` — that's
**associativity**. Pratt parsing encodes *both* in two numbers per operator.

## The picture

Every operator is a person with two arms, reaching for the things on its left
and right. Give each one two numbers — how hard it pulls **left**, how hard it
pulls **right**:

```
+  ->  (10, 11)
*  ->  (20, 21)
```

Bigger number = stronger grip.

## The arm-wrestle

In `2 + 3 * 4`, the `3` sits between `+` and `*`. Both reach for it. `*` pulls
with 20, `+` pulls with 11 — the `*` wins, so `3` pairs with `4` -> `3 * 4`.
Now `+` is left holding `2` and `(3 * 4)` -> `2 + (3 * 4)`.

Precedence is just "who wins the fight over the number in the middle."

## The mechanical rule

Parse left to right. Carry a number in your pocket: **"the weakest operator
I'm allowed to accept right now."** Start with 0.

When you meet an operator:

1. **Not an operator?** (a number, EOF, newline) — stop.
2. **Its left-strength < your pocket number?** — stop. It's too weak to be
   inside the thing you're building; it belongs to someone outside.
3. **Otherwise** — take it, and parse its right side with its *right*-strength
   in your pocket (the recursion).

That's the whole algorithm. One loop, one recursion, two lookups.

## Associativity falls out of the two numbers

Why is `+` `(10, 11)` and not `(10, 10)`? Trace `10 - 3 - 2`:

- Parse `10`. Meet `-` (10,11). 10 >= 0 — take it.
- Parse the right side with **11** in the pocket: parse `3`. Meet the next `-`
  (10,11). Its left-strength 10 < pocket 11 — **stop**. That `-` can't come
  inside.
- Back out: `(10 - 3)`, then the outer loop grabs the second `-` ->
  `((10 - 3) - 2)`. Left-associative.

The `11` is a **tripwire**: right = left + 1 locks a same-strength operator out
of the right side, so same-strength operators stack to the left.

Right-associativity is the opposite inequality: left strength **greater than**
right strength, `=` as `(2, 1)`. Trace `a = b = c`:

- Parse `a`. Meet `=` (2,1). Take it, parse the right side with **1** in the
  pocket.
- Parse `b`. Meet `=` (2,1). Its left-strength 2 < pocket 1? No — take it.
  Parse its right side -> `c`.
- Result: `a = (b = c)`. Right-associative.

The pair is both precedence *and* associativity: **left** sets the floor for
what may sit to its left, **right** sets the floor for the right operand, and
the *inequality* between them flips the direction — `left < right` is
left-associative, `left > right` is right-associative. No operator needs
`left == right`; a deliberate inequality makes the direction readable at a
glance.

## gauge's table

```
Equals     ( 2, 1 )   right   answer = 40 + 2    -> Assign(answer, 40 + 2)
Plus/Minus (10, 11)   left    2 + 3 + 4          -> (2 + 3) + 4
Star/Slash (20, 21)   left    2 * 3 * 4          -> (2 * 3) * 4
LParen     (30, 30)   call    print(answer)      -> Call(print, [answer])
```

Two consequences of these numbers:

- `=` being weak (2,1) is what makes assignments work: `answer = 40 + 2` —
  the `=` recurses to the right with minimum 1, and both `+` (10) and `*` (20)
  clear that floor, so the *entire rest* becomes the value. `parse_infix` on
  `=` builds `Assign`; `+ - * /` build `Binary`.
- `(` at (30,30) is how calls work as *infix*: the prefix parses `print`, the
  loop sees `(`, takes it, parses the argument list (`parse_args`). It is the
  one equal-powers row — but calls are bracket-delimited, so the associativity
  question never arises: the closing `)` always ends the argument list, and
  chained calls like `f(x)(y)` assemble left.

## The prefix role of `(`: grouping

The table row above is the *infix* role (calls). `(` also has a *prefix* role,
handled in `parse_prefix`, entirely outside the binding-power table:

- `(4 + 2) * 5` — parse_prefix consumes `(`, parses the inner expression at
  power 0, expects `)`, and returns the group as an atomic left operand. The
  loop then meets `*` and builds `Binary(Multiply, (4 + 2), 5)`. No binding
  power is involved — a group is one indivisible thing.
- Position decides the role, so there is no ambiguity: at the *start* of an
  expression, `(` is always grouping; *after* an expression, `(` is always a
  call. `(4 + 2)` starts an expression — grouping. `print` then `(` — call.
- `()` is a grouping of nothing — the `Unit` value. (The allow-unit decision is
  deferred; this is where it lands when it's made.)
- **Why this matters for declarations:** a bracketed constant like
  `x :: (4 + 2) * 3` is a group followed by `* 3`. The `(` after `ident ::`
  is the *grouping* role, not a procedure signature. That is exactly why the
  proc/const dispatch cannot use "(` means proc" — it must checkpoint, try the
  proc signature, and commit only when the `{` appears.

## The code shape

```odin
binding_power :: proc(token: tok.Token) -> (Binding_Power, bool) {
	// the pair for the token; the bool answers "is this even an operator?"
	// (a number, an identifier, EOF, NewLine -> false -> the loop stops)
}

parse_expression :: proc(p: ^Parser, minimum_binding_power: int) -> (expr: ^Expr, ok: bool) {
	lhs := parse_prefix(p) or_return
	for {
		l_bp, r_bp, is_op := binding_power(current(p))
		if !is_op || l_bp < minimum_binding_power do break
		operator := advance(p)
		rhs := parse_expression(p, r_bp) or_return
		lhs = parse_infix(p, operator, lhs, rhs) or_return
	}
	return lhs, true
}
```

`parse_prefix` builds the atomic things — number, identifier, `(`, unary `-`.
`parse_infix` builds the operator node. The `l_bp < minimum_binding_power` check
is the arm-wrestle; the `r_bp` on the recursion is the tripwire.

**Summary: precedence is a number, associativity is a fence, and any expression
parses with one loop and a pocket.**
