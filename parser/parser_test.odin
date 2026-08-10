package parser

import "core:testing"
import "core:mem"
import tok "../token"

// new_test_arena returns an allocator backed by a fresh dynamic arena whose
// lifetime is tied to the test. A registered cleanup destroys the arena
// before the runner's leak check, so a parse that routes every allocation
// through the arena reports a balanced alloc/free pair instead of leaks.
new_test_arena :: proc(t: ^testing.T) -> mem.Allocator {
	arena := new(mem.Dynamic_Arena)
	mem.dynamic_arena_init(arena)
	testing.cleanup(t, destroy_test_arena, arena)
	return mem.dynamic_arena_allocator(arena)
}

destroy_test_arena :: proc(user_data: rawptr) {
	arena := cast(^mem.Dynamic_Arena)user_data
	mem.dynamic_arena_destroy(arena)
	free(arena)
}

// --- assertion helpers -------------------------------------------------
//
// Each helper asserts the expected node and hands the test whatever it
// needs next, so assertions read top-down instead of nesting four levels
// of #partial switch deep. On a mismatch the helper fails the test and
// returns zero values; the calls after it fail too, cascading noise — but
// the first message names the real problem.
//
// The `_at` variants also pin the node's byte offset, for tests where the
// offset is the point.

expect_decls :: proc(t: ^testing.T, program: ^Program, count: int) {
	testing.expectf(t, len(program.decls) == count, "want %d declaration(s), got %d", count, len(program.decls))
}

expect_const :: proc(t: ^testing.T, decl: ^Expr, name: tok.Identifier) -> ^Expr {
	#partial switch d in decl^ {
	case Const:
		testing.expectf(t, d.name == name, "want const %q, got %q", name, d.name)
		return d.value
	case:
		testing.expectf(t, false, "want a const named %q", name)
	}
	return nil
}

expect_binary :: proc(t: ^testing.T, expr: ^Expr, operator: BinaryOperator) -> (lhs: ^Expr, rhs: ^Expr) {
	#partial switch v in expr^ {
	case Binary:
		testing.expectf(t, v.operator == operator, "want binary %v, got %v", operator, v.operator)
		return v.lhs, v.rhs
	case:
		testing.expectf(t, false, "want a binary %v", operator)
	}
	return nil, nil
}

expect_binary_at :: proc(t: ^testing.T, expr: ^Expr, operator: BinaryOperator, offset: int) -> (lhs: ^Expr, rhs: ^Expr) {
	lhs, rhs = expect_binary(t, expr, operator)
	#partial switch v in expr^ {
	case Binary:
		testing.expectf(t, v.offset == offset, "want %v at byte %d, got %d", operator, offset, v.offset)
	}
	return lhs, rhs
}

expect_number :: proc(t: ^testing.T, expr: ^Expr, value: tok.Number) {
	#partial switch v in expr^ {
	case Number:
		testing.expectf(t, v.value == value, "want number %q, got %q", value, v.value)
	case:
		testing.expectf(t, false, "want a number %q", value)
	}
}

expect_string :: proc(t: ^testing.T, expr: ^Expr, value: tok.StringLiteral) {
	#partial switch v in expr^ {
	case String:
		testing.expectf(t, v.value == value, "want string %q, got %q", value, v.value)
	case:
		testing.expectf(t, false, "want a string literal")
	}
}

expect_ident :: proc(t: ^testing.T, expr: ^Expr, name: tok.Identifier) {
	#partial switch v in expr^ {
	case Ident:
		testing.expectf(t, v.name == name, "want identifier %q, got %q", name, v.name)
	case:
		testing.expectf(t, false, "want an identifier %q", name)
	}
}

expect_unary :: proc(t: ^testing.T, expr: ^Expr, operator: UnaryOperator) -> ^Expr {
	#partial switch v in expr^ {
	case Unary:
		testing.expectf(t, v.operator == operator, "want unary %v, got %v", operator, v.operator)
		return v.operand
	case:
		testing.expectf(t, false, "want a unary %v", operator)
	}
	return nil
}

expect_assign :: proc(t: ^testing.T, expr: ^Expr, name: tok.Identifier) -> ^Expr {
	#partial switch v in expr^ {
	case Assign:
		testing.expectf(t, v.name == name, "want assignment to %q, got %q", name, v.name)
		return v.value
	case:
		testing.expectf(t, false, "want an assignment to %q", name)
	}
	return nil
}

expect_call_at :: proc(t: ^testing.T, expr: ^Expr, name: tok.Identifier, offset: int) -> []^Expr {
	#partial switch v in expr^ {
	case Call:
		testing.expectf(t, v.name == name, "want call to %q, got %q", name, v.name)
		testing.expectf(t, v.offset == offset, "want Call at byte %d, got %d", offset, v.offset)
		return v.args[:]
	case:
		testing.expectf(t, false, "want a call to %q", name)
	}
	return nil
}

expect_proc :: proc(t: ^testing.T, decl: ^Expr, name: tok.Identifier) -> ^Block {
	#partial switch d in decl^ {
	case Proc:
		testing.expectf(t, d.name == name, "want procedure %q, got %q", name, d.name)
		return d.body
	case:
		testing.expectf(t, false, "want a procedure named %q", name)
	}
	return nil
}

expect_block :: proc(t: ^testing.T, block: ^Block, count: int) -> []^Expr {
	testing.expectf(t, len(block.body) == count, "want %d body expression(s), got %d", count, len(block.body))
	return block.body[:]
}

expect_type_name :: proc(t: ^testing.T, ty: ^Type, name: tok.Identifier) {
	#partial switch v in ty^ {
	case TypeName:
		testing.expectf(t, v.name == name, "want type %q, got %q", name, v.name)
	case:
		testing.expectf(t, false, "want a type name %q", name)
	}
}

expect_type_pointer :: proc(t: ^testing.T, ty: ^Type, offset: int) -> ^Type {
	#partial switch v in ty^ {
	case TypePointer:
		testing.expectf(t, v.offset == offset, "want pointer at byte %d, got %d", offset, v.offset)
		return v.pointee
	case:
		testing.expectf(t, false, "want a pointer type")
	}
	return nil
}

@(test)
test_parse_const_number :: proc(t: ^testing.T) {
	tokens := []tok.Token{
		{offset = 0, value = tok.Identifier("x")},
		{offset = 2, value = tok.SimpleToken.Colon},
		{offset = 3, value = tok.SimpleToken.Colon},
		{offset = 5, value = tok.Number("42")},
		{offset = 7, value = tok.SimpleToken.EOF},
	}

	program, ok, err := parse(tokens, new_test_arena(t))
	testing.expectf(t, ok, "parse failed: %s", err)
	if !ok {
		return
	}

	expect_decls(t, program, 1)
	expect_number(t, expect_const(t, program.decls[0], "x"), "42")
}

@(test)
test_parse_const_string :: proc(t: ^testing.T) {
	tokens := []tok.Token{
		{offset = 0, value = tok.Identifier("greeting")},
		{offset = 9, value = tok.SimpleToken.Colon},
		{offset = 10, value = tok.SimpleToken.Colon},
		{offset = 12, value = tok.StringLiteral("hellope")},
		{offset = 20, value = tok.SimpleToken.EOF},
	}

	program, ok, err := parse(tokens, new_test_arena(t))
	testing.expectf(t, ok, "parse failed: %s", err)
	if !ok {
		return
	}

	expect_decls(t, program, 1)
	expect_string(t, expect_const(t, program.decls[0], "greeting"), "hellope")
}

// @(test) DISABLED — proc-dispatch not yet implemented. Re-enable by
// uncommenting the @(test) attribute when parse_decl grows the proc path.
test_parse_empty_proc :: proc(t: ^testing.T) {
	tokens := []tok.Token{
		{offset = 0, value = tok.Identifier("main")},
		{offset = 5, value = tok.SimpleToken.Colon},
		{offset = 6, value = tok.SimpleToken.Colon},
		{offset = 8, value = tok.Keyword.Proc},
		{offset = 12, value = tok.SimpleToken.LParen},
		{offset = 13, value = tok.SimpleToken.RParen},
		{offset = 15, value = tok.SimpleToken.LSquirly},
		{offset = 16, value = tok.SimpleToken.NewLine},
		{offset = 17, value = tok.SimpleToken.RSquirly},
		{offset = 18, value = tok.SimpleToken.EOF},
	}

	program, ok, err := parse(tokens, new_test_arena(t))
	testing.expectf(t, ok, "parse failed: %s", err)
	if !ok {
		return
	}

	expect_decls(t, program, 1)
	expect_block(t, expect_proc(t, program.decls[0], "main"), 0)
}

// @(test) DISABLED — needs two things: proc dispatch (parse_decl) and the
// Equals infix arm (assignment is deferred to the calls/assignment card).
// The body's `answer = 40 + 2` must become an Assign; until the Equals arm
// lands, re-enabling this test panics — to_binary_operator has no .Equals
// arm. test_parse_empty_proc and test_parse_multiline_group_inside_block
// cover the blocks slice without it.
test_parse_proc_body :: proc(t: ^testing.T) {
	tokens := []tok.Token{
		{offset = 0, value = tok.Identifier("main")},
		{offset = 5, value = tok.SimpleToken.Colon},
		{offset = 6, value = tok.SimpleToken.Colon},
		{offset = 8, value = tok.Keyword.Proc},
		{offset = 12, value = tok.SimpleToken.LParen},
		{offset = 13, value = tok.SimpleToken.RParen},
		{offset = 15, value = tok.SimpleToken.LSquirly},
		{offset = 16, value = tok.SimpleToken.NewLine},
		{offset = 18, value = tok.Identifier("answer")},
		{offset = 25, value = tok.SimpleToken.Equals},
		{offset = 27, value = tok.Number("40")},
		{offset = 30, value = tok.SimpleToken.Plus},
		{offset = 32, value = tok.Number("2")},
		{offset = 33, value = tok.SimpleToken.NewLine},
		{offset = 34, value = tok.SimpleToken.RSquirly},
		{offset = 35, value = tok.SimpleToken.EOF},
	}

	program, ok, err := parse(tokens, new_test_arena(t))
	testing.expectf(t, ok, "parse failed: %s", err)
	if !ok {
		return
	}

	expect_decls(t, program, 1)
	body := expect_block(t, expect_proc(t, program.decls[0], "main"), 1)
	expect_assign(t, body[0], "answer")
}

@(test)
test_parse_const_arithmetic_reference :: proc(t: ^testing.T) {
	tokens := []tok.Token{
		{offset = 0, value = tok.Identifier("KiB")},
		{offset = 4, value = tok.SimpleToken.Colon},
		{offset = 5, value = tok.SimpleToken.Colon},
		{offset = 7, value = tok.Number("1024")},
		{offset = 11, value = tok.SimpleToken.NewLine},
		{offset = 12, value = tok.Identifier("MiB")},
		{offset = 16, value = tok.SimpleToken.Colon},
		{offset = 17, value = tok.SimpleToken.Colon},
		{offset = 19, value = tok.Number("1024")},
		{offset = 24, value = tok.SimpleToken.Star},
		{offset = 26, value = tok.Identifier("KiB")},
		{offset = 29, value = tok.SimpleToken.EOF},
	}

	program, ok, err := parse(tokens, new_test_arena(t))
	testing.expectf(t, ok, "parse failed: %s", err)
	if !ok {
		return
	}

	expect_decls(t, program, 2)
	expect_number(t, expect_const(t, program.decls[0], "KiB"), "1024")
	kib_lhs, kib_rhs := expect_binary(t, expect_const(t, program.decls[1], "MiB"), .Multiply)
	expect_number(t, kib_lhs, "1024")
	expect_ident(t, kib_rhs, "KiB")
}

@(test)
test_parse_precedence :: proc(t: ^testing.T) {
	// 1 + 2 * 3 must group as 1 + (2 * 3), not (1 + 2) * 3.
	tokens := []tok.Token{
		{offset = 0, value = tok.Identifier("x")},
		{offset = 2, value = tok.SimpleToken.Colon},
		{offset = 3, value = tok.SimpleToken.Colon},
		{offset = 5, value = tok.Number("1")},
		{offset = 7, value = tok.SimpleToken.Plus},
		{offset = 9, value = tok.Number("2")},
		{offset = 11, value = tok.SimpleToken.Star},
		{offset = 13, value = tok.Number("3")},
		{offset = 14, value = tok.SimpleToken.EOF},
	}

	program, ok, err := parse(tokens, new_test_arena(t))
	testing.expectf(t, ok, "parse failed: %s", err)
	if !ok {
		return
	}

	expect_decls(t, program, 1)
	root_lhs, root_rhs := expect_binary(t, expect_const(t, program.decls[0], "x"), .Add)
	expect_number(t, root_lhs, "1")
	expect_binary(t, root_rhs, .Multiply)
}

@(test)
test_parse_bracketed_const :: proc(t: ^testing.T) {
	// x :: (4 + 2) * 3 — the `(` is grouping, not a proc signature.
	// Exercises the LParen prefix arm; the group is one atomic left operand.
	tokens := []tok.Token{
		{offset = 0, value = tok.Identifier("x")},
		{offset = 2, value = tok.SimpleToken.Colon},
		{offset = 3, value = tok.SimpleToken.Colon},
		{offset = 5, value = tok.SimpleToken.LParen},
		{offset = 6, value = tok.Number("4")},
		{offset = 8, value = tok.SimpleToken.Plus},
		{offset = 10, value = tok.Number("2")},
		{offset = 11, value = tok.SimpleToken.RParen},
		{offset = 13, value = tok.SimpleToken.Star},
		{offset = 15, value = tok.Number("3")},
		{offset = 16, value = tok.SimpleToken.EOF},
	}

	program, ok, err := parse(tokens, new_test_arena(t))
	testing.expectf(t, ok, "parse failed: %s", err)
	if !ok {
		return
	}

	expect_decls(t, program, 1)
	root_lhs, root_rhs := expect_binary(t, expect_const(t, program.decls[0], "x"), .Multiply)
	expect_binary(t, root_lhs, .Add)
	expect_number(t, root_rhs, "3")
}

@(test)
test_parse_rejects_stray_close_paren :: proc(t: ^testing.T) {
	// x :: )  — a close paren where an expression must be. parse_prefix
	// must reject it as a source error, not treat every SimpleToken as
	// the grouping LParen arm.
	tokens := []tok.Token{
		{offset = 0, value = tok.Identifier("x")},
		{offset = 2, value = tok.SimpleToken.Colon},
		{offset = 3, value = tok.SimpleToken.Colon},
		{offset = 5, value = tok.SimpleToken.RParen},
		{offset = 6, value = tok.SimpleToken.EOF},
	}

	program, ok, _ := parse(tokens, new_test_arena(t))
	testing.expectf(t, !ok, "want a parse error for a stray close paren, but parse succeeded")
	// The parser returns any partially-built program with ok=false; the
	// caller must gate on ok, so a non-nil program here is not an error.
	_ = program
}

@(test)
test_parse_unary_minus :: proc(t: ^testing.T) {
	// x :: -5 — a leading minus is a real Unary expression, not an
	// error and not a silent +5: Unary(Minus, Number(5)) must be produced.
	tokens := []tok.Token{
		{offset = 0, value = tok.Identifier("x")},
		{offset = 2, value = tok.SimpleToken.Colon},
		{offset = 3, value = tok.SimpleToken.Colon},
		{offset = 5, value = tok.SimpleToken.Minus},
		{offset = 6, value = tok.Number("5")},
		{offset = 7, value = tok.SimpleToken.EOF},
	}

	program, ok, err := parse(tokens, new_test_arena(t))
	testing.expectf(t, ok, "parse failed: %s", err)
	if !ok {
		return
	}

	expect_decls(t, program, 1)
	expect_number(t, expect_unary(t, expect_const(t, program.decls[0], "x"), .Minus), "5")
}

@(test)
test_parse_unary_minus_binds_tighter_than_plus :: proc(t: ^testing.T) {
	// x :: -2 + 3 must group as (-2) + 3, not -(2 + 3). This is the
	// floor test: parsing the unary operand at 0 would drag the + in.
	tokens := []tok.Token{
		{offset = 0, value = tok.Identifier("x")},
		{offset = 2, value = tok.SimpleToken.Colon},
		{offset = 3, value = tok.SimpleToken.Colon},
		{offset = 5, value = tok.SimpleToken.Minus},
		{offset = 6, value = tok.Number("2")},
		{offset = 8, value = tok.SimpleToken.Plus},
		{offset = 10, value = tok.Number("3")},
		{offset = 11, value = tok.SimpleToken.EOF},
	}

	program, ok, err := parse(tokens, new_test_arena(t))
	testing.expectf(t, ok, "parse failed: %s", err)
	if !ok {
		return
	}

	expect_decls(t, program, 1)
	root_lhs, _ := expect_binary(t, expect_const(t, program.decls[0], "x"), .Add)
	expect_unary(t, root_lhs, .Minus)
}

@(test)
test_parse_double_unary_minus :: proc(t: ^testing.T) {
	// x :: --5 — double negation nests: Unary(Minus, Unary(Minus, 5)).
	// The recursion must allow it, and the shape must be two nested
	// Unary nodes, not an error.
	tokens := []tok.Token{
		{offset = 0, value = tok.Identifier("x")},
		{offset = 2, value = tok.SimpleToken.Colon},
		{offset = 3, value = tok.SimpleToken.Colon},
		{offset = 5, value = tok.SimpleToken.Minus},
		{offset = 6, value = tok.SimpleToken.Minus},
		{offset = 7, value = tok.Number("5")},
		{offset = 8, value = tok.SimpleToken.EOF},
	}

	program, ok, err := parse(tokens, new_test_arena(t))
	testing.expectf(t, ok, "parse failed: %s", err)
	if !ok {
		return
	}

	expect_decls(t, program, 1)
	inner := expect_unary(t, expect_const(t, program.decls[0], "x"), .Minus)
	expect_number(t, expect_unary(t, inner, .Minus), "5")
}

@(test)
test_parse_unary_minus_binds_tighter_than_star :: proc(t: ^testing.T) {
	// x :: -2 * 3 must group as (-2) * 3, not -(2 * 3). The unary
	// operand binds at floor 25, strictly above `*`'s left strength 20.
	tokens := []tok.Token{
		{offset = 0, value = tok.Identifier("x")},
		{offset = 2, value = tok.SimpleToken.Colon},
		{offset = 3, value = tok.SimpleToken.Colon},
		{offset = 5, value = tok.SimpleToken.Minus},
		{offset = 6, value = tok.Number("2")},
		{offset = 8, value = tok.SimpleToken.Star},
		{offset = 10, value = tok.Number("3")},
		{offset = 11, value = tok.SimpleToken.EOF},
	}

	program, ok, err := parse(tokens, new_test_arena(t))
	testing.expectf(t, ok, "parse failed: %s", err)
	if !ok {
		return
	}

	expect_decls(t, program, 1)
	root_lhs, _ := expect_binary(t, expect_const(t, program.decls[0], "x"), .Multiply)
	expect_number(t, expect_unary(t, root_lhs, .Minus), "2")
}

@(test)
test_unary_binding_power_minus :: proc(t: ^testing.T) {
	// The mechanism that replaced the inline 25 in parse_prefix: a dedicated
	// lookup owns the floor. Its contract is (a) the value, pinned here as
	// 25, and (b) strictly above `*`'s left strength (20), so a prefix
	// operand can never swallow a multiplication.
	bp, ok := unary_binding_power(tok.Token{value = tok.SimpleToken.Minus})
	testing.expectf(t, ok, "Minus must be recognised as a unary operator")
	testing.expectf(t, bp == 25, "want floor 25 for unary minus, got %d", bp)
	testing.expectf(t, bp > 20, "unary floor %d must exceed `*`'s left strength 20", bp)
}

@(test)
test_unary_binding_power_plus :: proc(t: ^testing.T) {
	// Plus shares minus's floor: `+5` would bind exactly like `-5` once
	// parse_prefix grows the arm. The row is dormant today — the parse test
	// below pins that.
	minus_bp, _ := unary_binding_power(tok.Token{value = tok.SimpleToken.Minus})
	plus_bp, plus_ok := unary_binding_power(tok.Token{value = tok.SimpleToken.Plus})
	testing.expectf(t, plus_ok, "Plus must be recognised as a unary operator")
	testing.expectf(t, plus_bp == 25, "want floor 25 for unary plus, got %d", plus_bp)
	testing.expectf(t, plus_bp == minus_bp,
		"unary plus and minus must share one floor, got %d and %d", plus_bp, minus_bp)
}

@(test)
test_unary_binding_power_rejects_non_unary :: proc(t: ^testing.T) {
	// The lookup's bool answers "is this a unary operator at all?". Binary
	// operators and atoms must be rejected with floor 0, not silently
	// given minus's floor.
	rejected := []tok.Value{
		tok.SimpleToken.Star,
		tok.SimpleToken.LParen,
		tok.Number("5"),
	}
	for v in rejected {
		bp, ok := unary_binding_power(tok.Token{value = v})
		testing.expectf(t, !ok, "token %v must not be a unary operator", v)
		testing.expectf(t, bp == 0, "rejected token %v must report floor 0, got %d", v, bp)
	}
}

@(test)
test_parse_unary_plus :: proc(t: ^testing.T) {
	// x :: +5 — a leading plus must be a real Unary expression, not an
	// error: Unary(Plus, Number(5)). This is the arm test.
	tokens := []tok.Token{
		{offset = 0, value = tok.Identifier("x")},
		{offset = 2, value = tok.SimpleToken.Colon},
		{offset = 3, value = tok.SimpleToken.Colon},
		{offset = 5, value = tok.SimpleToken.Plus},
		{offset = 6, value = tok.Number("5")},
		{offset = 7, value = tok.SimpleToken.EOF},
	}

	program, ok, err := parse(tokens, new_test_arena(t))
	testing.expectf(t, ok, "parse failed: %s", err)
	if !ok {
		return
	}

	expect_decls(t, program, 1)
	expect_number(t, expect_unary(t, expect_const(t, program.decls[0], "x"), .Plus), "5")
}

@(test)
test_parse_unary_plus_binds_tighter_than_plus :: proc(t: ^testing.T) {
	// x :: +2 + 3 must group as (+2) + 3, not +(2 + 3). The unary
	// operand's floor keeps the binary + out of it.
	tokens := []tok.Token{
		{offset = 0, value = tok.Identifier("x")},
		{offset = 2, value = tok.SimpleToken.Colon},
		{offset = 3, value = tok.SimpleToken.Colon},
		{offset = 5, value = tok.SimpleToken.Plus},
		{offset = 6, value = tok.Number("2")},
		{offset = 8, value = tok.SimpleToken.Plus},
		{offset = 10, value = tok.Number("3")},
		{offset = 11, value = tok.SimpleToken.EOF},
	}

	program, ok, err := parse(tokens, new_test_arena(t))
	testing.expectf(t, ok, "parse failed: %s", err)
	if !ok {
		return
	}

	expect_decls(t, program, 1)
	root_lhs, _ := expect_binary(t, expect_const(t, program.decls[0], "x"), .Add)
	expect_unary(t, root_lhs, .Plus)
}

@(test)
test_parse_unary_plus_binds_tighter_than_star :: proc(t: ^testing.T) {
	// x :: +2 * 3 must group as (+2) * 3, not +(2 * 3). The unary
	// operand binds at the shared floor, strictly above `*`'s left
	// strength 20.
	tokens := []tok.Token{
		{offset = 0, value = tok.Identifier("x")},
		{offset = 2, value = tok.SimpleToken.Colon},
		{offset = 3, value = tok.SimpleToken.Colon},
		{offset = 5, value = tok.SimpleToken.Plus},
		{offset = 6, value = tok.Number("2")},
		{offset = 8, value = tok.SimpleToken.Star},
		{offset = 10, value = tok.Number("3")},
		{offset = 11, value = tok.SimpleToken.EOF},
	}

	program, ok, err := parse(tokens, new_test_arena(t))
	testing.expectf(t, ok, "parse failed: %s", err)
	if !ok {
		return
	}

	expect_decls(t, program, 1)
	root_lhs, _ := expect_binary(t, expect_const(t, program.decls[0], "x"), .Multiply)
	expect_number(t, expect_unary(t, root_lhs, .Plus), "2")
}

@(test)
test_parse_unary_plus_minus_mix :: proc(t: ^testing.T) {
	// x :: +-5 — mixed signs nest: Unary(Plus, Unary(Minus, 5)). The
	// plus arm must recurse back into the minus arm.
	tokens := []tok.Token{
		{offset = 0, value = tok.Identifier("x")},
		{offset = 2, value = tok.SimpleToken.Colon},
		{offset = 3, value = tok.SimpleToken.Colon},
		{offset = 5, value = tok.SimpleToken.Plus},
		{offset = 6, value = tok.SimpleToken.Minus},
		{offset = 7, value = tok.Number("5")},
		{offset = 8, value = tok.SimpleToken.EOF},
	}

	program, ok, err := parse(tokens, new_test_arena(t))
	testing.expectf(t, ok, "parse failed: %s", err)
	if !ok {
		return
	}

	expect_decls(t, program, 1)
	inner := expect_unary(t, expect_const(t, program.decls[0], "x"), .Plus)
	expect_number(t, expect_unary(t, inner, .Minus), "5")
}

@(test)
test_parse_rejects_trailing_operator :: proc(t: ^testing.T) {
	// x :: 1 + — the operator grabs a right operand, then hits EOF.
	// The arm-wrestle recurses into parse_prefix at EOF, which must
	// fail cleanly rather than crash or produce a malformed tree.
	tokens := []tok.Token{
		{offset = 0, value = tok.Identifier("x")},
		{offset = 2, value = tok.SimpleToken.Colon},
		{offset = 3, value = tok.SimpleToken.Colon},
		{offset = 5, value = tok.Number("1")},
		{offset = 7, value = tok.SimpleToken.Plus},
		{offset = 8, value = tok.SimpleToken.EOF},
	}

	program, ok, _ := parse(tokens, new_test_arena(t))
	testing.expectf(t, !ok, "want a parse error for a trailing operator, but parse succeeded")
	_ = program
}

@(test)
test_parse_rejects_unterminated_group :: proc(t: ^testing.T) {
	// x :: (4 + 2 — the closing paren is missing. The grouping arm
	// must report the missing `)` as an error, not parse on forever.
	tokens := []tok.Token{
		{offset = 0, value = tok.Identifier("x")},
		{offset = 2, value = tok.SimpleToken.Colon},
		{offset = 3, value = tok.SimpleToken.Colon},
		{offset = 5, value = tok.SimpleToken.LParen},
		{offset = 6, value = tok.Number("4")},
		{offset = 8, value = tok.SimpleToken.Plus},
		{offset = 10, value = tok.Number("2")},
		{offset = 11, value = tok.SimpleToken.EOF},
	}

	program, ok, _ := parse(tokens, new_test_arena(t))
	testing.expectf(t, !ok, "want a parse error for an unterminated group, but parse succeeded")
	_ = program
}

@(test)
test_parse_rejects_empty_group :: proc(t: ^testing.T) {
	// x :: () — an empty group. `()` is the deferred Unit value; until
	// that lands it must be an error, not silently a done expression.
	tokens := []tok.Token{
		{offset = 0, value = tok.Identifier("x")},
		{offset = 2, value = tok.SimpleToken.Colon},
		{offset = 3, value = tok.SimpleToken.Colon},
		{offset = 5, value = tok.SimpleToken.LParen},
		{offset = 6, value = tok.SimpleToken.RParen},
		{offset = 7, value = tok.SimpleToken.EOF},
	}

	program, ok, _ := parse(tokens, new_test_arena(t))
	testing.expectf(t, !ok, "want a parse error for an empty group, but parse succeeded")
	_ = program
}

@(test)
test_parse_rejects_missing_double_colon :: proc(t: ^testing.T) {
	// x 5 — a bare identifier with no `::`. parse_decl must reject it
	// as a source error (missing `::`), not create some other node.
	tokens := []tok.Token{
		{offset = 0, value = tok.Identifier("x")},
		{offset = 2, value = tok.Number("5")},
		{offset = 3, value = tok.SimpleToken.EOF},
	}

	program, ok, _ := parse(tokens, new_test_arena(t))
	testing.expectf(t, !ok, "want a parse error for a missing `::`, but parse succeeded")
	_ = program
}

@(test)
test_parse_typed_const_pointer :: proc(t: ^testing.T) {
	// x : ^int : 5 — an explicit type slot. The `^` is the pointer
	// marker, `int` the name. parse_type must build
	// TypePointer(TypeName(int)).
	tokens := []tok.Token{
		{offset = 0, value = tok.Identifier("x")},
		{offset = 2, value = tok.SimpleToken.Colon},
		{offset = 4, value = tok.SimpleToken.Hat},
		{offset = 5, value = tok.Identifier("int")},
		{offset = 8, value = tok.SimpleToken.Colon},
		{offset = 10, value = tok.Number("5")},
		{offset = 11, value = tok.SimpleToken.EOF},
	}

	program, ok, err := parse(tokens, new_test_arena(t))
	testing.expectf(t, ok, "parse failed: %s", err)
	if !ok {
		return
	}

	expect_decls(t, program, 1)
	#partial switch d in program.decls[0]^ {
	case Const:
		expect_type_name(t, expect_type_pointer(t, d.type, 4), "int")
		expect_number(t, d.value, "5")
	case:
		testing.expect(t, false, "declaration should be a constant")
	}
}

@(test)
test_parse_typed_const_double_pointer :: proc(t: ^testing.T) {
	// x : ^^int : 5 — pointer-to-pointer. The `^ Type` production must
	// recurse: TypePointer(TypePointer(TypeName(int))).
	tokens := []tok.Token{
		{offset = 0, value = tok.Identifier("x")},
		{offset = 2, value = tok.SimpleToken.Colon},
		{offset = 4, value = tok.SimpleToken.Hat},
		{offset = 5, value = tok.SimpleToken.Hat},
		{offset = 6, value = tok.Identifier("int")},
		{offset = 9, value = tok.SimpleToken.Colon},
		{offset = 11, value = tok.Number("5")},
		{offset = 12, value = tok.SimpleToken.EOF},
	}

	program, ok, err := parse(tokens, new_test_arena(t))
	testing.expectf(t, ok, "parse failed: %s", err)
	if !ok {
		return
	}

	expect_decls(t, program, 1)
	#partial switch d in program.decls[0]^ {
	case Const:
		expect_type_name(t, expect_type_pointer(t, expect_type_pointer(t, d.type, 4), 5), "int")
	case:
		testing.expect(t, false, "declaration should be a constant")
	}
}

@(test)
test_parse_typed_const_name :: proc(t: ^testing.T) {
	// x : int : 5 — a bare name in the type slot (no marker). Must be a
	// TypeName, and the value must still parse.
	tokens := []tok.Token{
		{offset = 0, value = tok.Identifier("x")},
		{offset = 2, value = tok.SimpleToken.Colon},
		{offset = 4, value = tok.Identifier("int")},
		{offset = 7, value = tok.SimpleToken.Colon},
		{offset = 9, value = tok.Number("5")},
		{offset = 10, value = tok.SimpleToken.EOF},
	}

	program, ok, err := parse(tokens, new_test_arena(t))
	testing.expectf(t, ok, "parse failed: %s", err)
	if !ok {
		return
	}

	expect_decls(t, program, 1)
	#partial switch d in program.decls[0]^ {
	case Const:
		expect_type_name(t, d.type, "int")
		expect_number(t, d.value, "5")
	case:
		testing.expect(t, false, "declaration should be a constant")
	}
}

// --- Non-nil invariant spec ---
//
// In a successfully-parsed tree, every pointer field that holds a child
// node must be non-nil. The one deliberate exception is Const.type: nil
// means "inferred" (`x :: 5`) and is a legal absence.
//
// Layer 1 walks a real parse and asserts the invariant. Layer 2 pins the
// mechanism: the new_* constructors must reject nil for required fields.

check_type_non_nil :: proc(t: ^testing.T, ty: ^Type) {
	testing.expectf(t, ty != nil, "present type must not be nil")
	if ty == nil {
		return
	}
	#partial switch v in ty^ {
	case TypePointer:
		testing.expectf(t, v.pointee != nil, "TypePointer.pointee must not be nil")
		check_type_non_nil(t, v.pointee)
	case TypeName:
		// leaf — nothing to check
	}
}

check_expr_non_nil :: proc(t: ^testing.T, e: ^Expr) {
	testing.expectf(t, e != nil, "expression must not be nil")
	if e == nil {
		return
	}
	#partial switch v in e^ {
	case Binary:
		testing.expectf(t, v.lhs != nil, "Binary.lhs must not be nil")
		testing.expectf(t, v.rhs != nil, "Binary.rhs must not be nil")
		check_expr_non_nil(t, v.lhs)
		check_expr_non_nil(t, v.rhs)
	case Unary:
		testing.expectf(t, v.operand != nil, "Unary.operand must not be nil")
		check_expr_non_nil(t, v.operand)
	case Assign:
		testing.expectf(t, v.value != nil, "Assign.value must not be nil")
		check_expr_non_nil(t, v.value)
	case Const:
		testing.expectf(t, v.value != nil, "Const.value must not be nil")
		check_expr_non_nil(t, v.value)
		if v.type != nil {
			check_type_non_nil(t, v.type)
		}
	case Call:
		for arg in v.args {
			check_expr_non_nil(t, arg)
		}
	case Block:
		for stmt in v.body {
			check_expr_non_nil(t, stmt)
		}
	case Proc:
		testing.expectf(t, v.body != nil, "Proc.body must not be nil")
		if v.body != nil {
			for stmt in v.body.body {
				check_expr_non_nil(t, stmt)
			}
		}
	case:
		// Unit, String, Number, Ident — leaves, nothing to check.
	}
}

@(test)
test_non_nil_invariant_across_parse :: proc(t: ^testing.T) {
	// A program exercising every currently-parseable node kind:
	// Const with Binary (nested), Unary, String, Ident, and references.
	tokens := []tok.Token{
		{offset = 0, value = tok.Identifier("y")},
		{offset = 2, value = tok.SimpleToken.Colon},
		{offset = 3, value = tok.SimpleToken.Colon},
		{offset = 5, value = tok.Number("1")},
		{offset = 7, value = tok.SimpleToken.Plus},
		{offset = 9, value = tok.Number("2")},
		{offset = 11, value = tok.SimpleToken.Star},
		{offset = 13, value = tok.Number("3")},
		{offset = 14, value = tok.SimpleToken.NewLine},
		{offset = 15, value = tok.Identifier("z")},
		{offset = 17, value = tok.SimpleToken.Colon},
		{offset = 18, value = tok.SimpleToken.Colon},
		{offset = 20, value = tok.SimpleToken.Minus},
		{offset = 21, value = tok.Identifier("y")},
		{offset = 22, value = tok.SimpleToken.NewLine},
		{offset = 23, value = tok.Identifier("s")},
		{offset = 25, value = tok.SimpleToken.Colon},
		{offset = 26, value = tok.SimpleToken.Colon},
		{offset = 28, value = tok.StringLiteral("hello")},
		{offset = 35, value = tok.SimpleToken.NewLine},
		{offset = 36, value = tok.Identifier("w")},
		{offset = 38, value = tok.SimpleToken.Colon},
		{offset = 39, value = tok.SimpleToken.Colon},
		{offset = 41, value = tok.Identifier("x")},
		{offset = 42, value = tok.SimpleToken.EOF},
	}

	program, ok, err := parse(tokens, new_test_arena(t))
	testing.expectf(t, ok, "parse failed: %s", err)
	if !ok {
		return
	}

	testing.expectf(t, program != nil, "program must not be nil")
	if program == nil {
		return
	}
	for decl, _ in program.decls {
		check_expr_non_nil(t, decl)
	}
}

// --- Layer 2: constructor rejection ---

@(test)
test_new_binary_rejects_nil_operands :: proc(t: ^testing.T) {
	n := new_binary(.Add, nil, nil, 0, new_test_arena(t))
	testing.expectf(t, n == nil, "new_binary must reject nil operands")
}

@(test)
test_new_unary_rejects_nil_operand :: proc(t: ^testing.T) {
	n := new_unary(.Minus, nil, 0, new_test_arena(t))
	testing.expectf(t, n == nil, "new_unary must reject a nil operand")
}

@(test)
test_new_assign_rejects_nil_value :: proc(t: ^testing.T) {
	n := new_assign("x", nil, 0, new_test_arena(t))
	testing.expectf(t, n == nil, "new_assign must reject a nil value")
}

@(test)
test_new_const_rejects_nil_value :: proc(t: ^testing.T) {
	n := new_const("x", nil, nil, 0, new_test_arena(t))
	testing.expectf(t, n == nil, "new_const must reject a nil value")
}

@(test)
test_new_const_allows_nil_type :: proc(t: ^testing.T) {
	// The one deliberate exception: Const.type is nilable (inferred).
	value := new_number("5", 0, new_test_arena(t))
	n := new_const("x", nil, value, 0, new_test_arena(t))
	testing.expectf(t, n != nil, "new_const must allow a nil type (inferred const)")
}

@(test)
test_new_proc_rejects_nil_body :: proc(t: ^testing.T) {
	n := new_proc("main", nil, 0, new_test_arena(t))
	testing.expectf(t, n == nil, "new_proc must reject a nil body")
}

@(test)
test_parse_type_pointer_offsets :: proc(t: ^testing.T) {
	// x : ^^int : 5 — the creating-token convention says each
	// TypePointer.offset is the byte of its own `^`, not the byte
	// after it. The ^s are at 4 and 5.
	tokens := []tok.Token{
		{offset = 0, value = tok.Identifier("x")},
		{offset = 2, value = tok.SimpleToken.Colon},
		{offset = 4, value = tok.SimpleToken.Hat},
		{offset = 5, value = tok.SimpleToken.Hat},
		{offset = 6, value = tok.Identifier("int")},
		{offset = 9, value = tok.SimpleToken.Colon},
		{offset = 11, value = tok.Number("5")},
		{offset = 12, value = tok.SimpleToken.EOF},
	}

	program, ok, err := parse(tokens, new_test_arena(t))
	testing.expectf(t, ok, "parse failed: %s", err)
	if !ok {
		return
	}

	#partial switch d in program.decls[0]^ {
	case Const:
		expect_type_pointer(t, expect_type_pointer(t, d.type, 4), 5)
	case:
		testing.expect(t, false, "declaration should be a constant")
	}
}

@(test)
test_allocator_discipline :: proc(t: ^testing.T) {
	// A successful parse must route every allocation through the passed
	// allocator. While context.allocator points at a fresh tracking
	// allocator, parse into a fixed-buffer arena: if any allocation falls
	// through to context.allocator, the tracker catches it. The context
	// swap is scoped so the assertions run with the ambient allocator.
	backing := context.allocator

	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, backing)
	defer mem.tracking_allocator_destroy(&tracker)

	buffer := make([]byte, 1 << 16, backing)
	defer delete(buffer, backing)

	arena: mem.Arena
	mem.arena_init(&arena, buffer)

	tokens := []tok.Token{
		{offset = 0, value = tok.Identifier("x")},
		{offset = 2, value = tok.SimpleToken.Colon},
		{offset = 3, value = tok.SimpleToken.Colon},
		{offset = 5, value = tok.Number("42")},
		{offset = 7, value = tok.SimpleToken.EOF},
	}

	program: ^Program
	ok: bool
	err: string
	{
		prev := context.allocator
		context.allocator = mem.tracking_allocator(&tracker)
		defer context.allocator = prev

		program, ok, err = parse(tokens, mem.arena_allocator(&arena))
	}

	testing.expectf(t, ok, "parse failed: %s", err)
	testing.expectf(t, len(tracker.allocation_map) == 0,
		"allocator discipline broken: %d allocation(s) fell through to context.allocator",
		len(tracker.allocation_map))
	_ = program
}

// --- Paren-zone newlines (§11.16) --------------------------------------
//
// The multi-line decision, pinned: newlines are insignificant inside ( ),
// significant everywhere else. The deciding question — may an expression
// continue across a newline without parens? — answers no.
//
// Motivating shapes:
//
//   x :: (4 + 2 +        — one expression, continuing inside the zone:
//           3 + 5)         (((4 + 2) + 3) + 5)
//
//   x :: (4 + 2          — same zone, but the operator sits on the next
//            * 3)          line: 4 + (2 * 3). The zone absorbs the
//                          newline at the *operator* position too, not
//                          just after an operator.
//
//   x :: 4 + 2           — NOT one expression: the newline ends it, and
//   + 3                    `+ 3` cannot even start a declaration. Error.
//
//   x :: 4 +             — still an error outside a zone: the dangling +
//   2                      has no right operand. The trailing-operator
//                          invariant survives the decision unchanged.
//
//   x :: (4 + 2)         — the zone closes; newline significance returns.
//   y :: 5                  Two declarations.
//
//   x :: (4 + 2          — the swallow hazard, pinned at the boundary: an
//   y :: 5                 unclosed zone eats the next declaration, so
//                          this must stay an error. Recovery's job later
//                          is to resync on the matching closer.
//
// Block bodies are newline-separated and never zones — that is what keeps
// `;` out of the language. A group inside a block is contained by its
// parens and must not disturb the statement separation around it.
//
// The zone rule lives in zoning_pre_parse, the pre-pass at the head of
// parse: NewLines at paren depth > 0 are dropped before the parser runs,
// so the parser never sees a newline inside a zone. The depth clamps at
// 0, braces are never zones, and the parser itself is untouched.

@(test)
test_parse_multiline_group_continues :: proc(t: ^testing.T) {
	// x :: (4 + 2 +\n3 + 5) — the operator sits on the first line, the
	// operand on the second; the zone absorbs the newline between them.
	// Must parse as (((4 + 2) + 3) + 5). RED: the Pratt loop stops at a
	// NewLine today, so the group never finds its `)`.
	tokens := []tok.Token{
		{offset = 0, value = tok.Identifier("x")},
		{offset = 2, value = tok.SimpleToken.Colon},
		{offset = 3, value = tok.SimpleToken.Colon},
		{offset = 5, value = tok.SimpleToken.LParen},
		{offset = 6, value = tok.Number("4")},
		{offset = 8, value = tok.SimpleToken.Plus},
		{offset = 10, value = tok.Number("2")},
		{offset = 12, value = tok.SimpleToken.Plus},
		{offset = 13, value = tok.SimpleToken.NewLine},
		{offset = 14, value = tok.Number("3")},
		{offset = 16, value = tok.SimpleToken.Plus},
		{offset = 18, value = tok.Number("5")},
		{offset = 19, value = tok.SimpleToken.RParen},
		{offset = 20, value = tok.SimpleToken.EOF},
	}

	program, ok, err := parse(tokens, new_test_arena(t))
	testing.expectf(t, ok, "parse failed: %s", err)
	if !ok {
		return
	}

	expect_decls(t, program, 1)
	value := expect_const(t, program.decls[0], "x")
	root_lhs, root_rhs := expect_binary_at(t, value, .Add, 16)
	middle_lhs, middle_rhs := expect_binary_at(t, root_lhs, .Add, 12)
	inner_lhs, inner_rhs := expect_binary_at(t, middle_lhs, .Add, 8)
	expect_number(t, inner_lhs, "4")
	expect_number(t, inner_rhs, "2")
	expect_number(t, middle_rhs, "3")
	expect_number(t, root_rhs, "5")
}

@(test)
test_parse_multiline_group_operator_on_next_line :: proc(t: ^testing.T) {
	// x :: (4 + 2\n* 3) — a complete line inside the zone, then an
	// operator starting the next. The Pratt *loop* must absorb the
	// newline and see the `*`; without that, the group fails. RED: the
	// loop stops at the NewLine today.
	tokens := []tok.Token{
		{offset = 0, value = tok.Identifier("x")},
		{offset = 2, value = tok.SimpleToken.Colon},
		{offset = 3, value = tok.SimpleToken.Colon},
		{offset = 5, value = tok.SimpleToken.LParen},
		{offset = 6, value = tok.Number("4")},
		{offset = 8, value = tok.SimpleToken.Plus},
		{offset = 10, value = tok.Number("2")},
		{offset = 11, value = tok.SimpleToken.NewLine},
		{offset = 12, value = tok.SimpleToken.Star},
		{offset = 14, value = tok.Number("3")},
		{offset = 15, value = tok.SimpleToken.RParen},
		{offset = 16, value = tok.SimpleToken.EOF},
	}

	program, ok, err := parse(tokens, new_test_arena(t))
	testing.expectf(t, ok, "parse failed: %s", err)
	if !ok {
		return
	}

	expect_decls(t, program, 1)
	root_lhs, root_rhs := expect_binary_at(t, expect_const(t, program.decls[0], "x"), .Add, 8)
	expect_number(t, root_lhs, "4")
	expect_binary_at(t, root_rhs, .Multiply, 12)
}

@(test)
test_parse_multiline_group_multiple_newlines :: proc(t: ^testing.T) {
	// x :: (4 +\n\n2) — two newlines inside the zone: a trailing operator
	// before them, the operand after. The operand-position site
	// (parse_prefix) must skip both. RED: parse_prefix rejects the
	// NewLine today.
	tokens := []tok.Token{
		{offset = 0, value = tok.Identifier("x")},
		{offset = 2, value = tok.SimpleToken.Colon},
		{offset = 3, value = tok.SimpleToken.Colon},
		{offset = 5, value = tok.SimpleToken.LParen},
		{offset = 6, value = tok.Number("4")},
		{offset = 8, value = tok.SimpleToken.Plus},
		{offset = 9, value = tok.SimpleToken.NewLine},
		{offset = 10, value = tok.SimpleToken.NewLine},
		{offset = 11, value = tok.Number("2")},
		{offset = 12, value = tok.SimpleToken.RParen},
		{offset = 13, value = tok.SimpleToken.EOF},
	}

	program, ok, err := parse(tokens, new_test_arena(t))
	testing.expectf(t, ok, "parse failed: %s", err)
	if !ok {
		return
	}

	expect_decls(t, program, 1)
	lhs, rhs := expect_binary(t, expect_const(t, program.decls[0], "x"), .Add)
	expect_number(t, lhs, "4")
	expect_number(t, rhs, "2")
}

@(test)
test_parse_multiline_group_nested :: proc(t: ^testing.T) {
	// x :: ((4 +\n2) + 3) — zones nest; each group pushes and pops its
	// own depth, so the inner newline is absorbed and the outer one
	// (after the inner `)`) still ends the outer expression. RED today.
	tokens := []tok.Token{
		{offset = 0, value = tok.Identifier("x")},
		{offset = 2, value = tok.SimpleToken.Colon},
		{offset = 3, value = tok.SimpleToken.Colon},
		{offset = 5, value = tok.SimpleToken.LParen},
		{offset = 6, value = tok.SimpleToken.LParen},
		{offset = 7, value = tok.Number("4")},
		{offset = 9, value = tok.SimpleToken.Plus},
		{offset = 10, value = tok.SimpleToken.NewLine},
		{offset = 11, value = tok.Number("2")},
		{offset = 12, value = tok.SimpleToken.RParen},
		{offset = 14, value = tok.SimpleToken.Plus},
		{offset = 16, value = tok.Number("3")},
		{offset = 17, value = tok.SimpleToken.RParen},
		{offset = 18, value = tok.SimpleToken.EOF},
	}

	program, ok, err := parse(tokens, new_test_arena(t))
	testing.expectf(t, ok, "parse failed: %s", err)
	if !ok {
		return
	}

	expect_decls(t, program, 1)
	root_lhs, root_rhs := expect_binary_at(t, expect_const(t, program.decls[0], "x"), .Add, 14)
	expect_binary_at(t, root_lhs, .Add, 9)
	expect_number(t, root_rhs, "3")
}

@(test)
test_parse_multiline_group_then_newline_ends_expression :: proc(t: ^testing.T) {
	// x :: (4 + 2)\ny :: 5 — the zone closes at the `)`, depth returns
	// to zero, and the newline ends the declaration again. This pins
	// that zone state does not leak past the closer. Green today and
	// green after: it is the guardrail for the depth discipline.
	tokens := []tok.Token{
		{offset = 0, value = tok.Identifier("x")},
		{offset = 2, value = tok.SimpleToken.Colon},
		{offset = 3, value = tok.SimpleToken.Colon},
		{offset = 5, value = tok.SimpleToken.LParen},
		{offset = 6, value = tok.Number("4")},
		{offset = 8, value = tok.SimpleToken.Plus},
		{offset = 10, value = tok.Number("2")},
		{offset = 11, value = tok.SimpleToken.RParen},
		{offset = 12, value = tok.SimpleToken.NewLine},
		{offset = 13, value = tok.Identifier("y")},
		{offset = 15, value = tok.SimpleToken.Colon},
		{offset = 16, value = tok.SimpleToken.Colon},
		{offset = 18, value = tok.Number("5")},
		{offset = 19, value = tok.SimpleToken.EOF},
	}

	program, ok, err := parse(tokens, new_test_arena(t))
	testing.expectf(t, ok, "parse failed: %s", err)
	if !ok {
		return
	}

	expect_decls(t, program, 2)
	expect_binary(t, expect_const(t, program.decls[0], "x"), .Add)
	expect_number(t, expect_const(t, program.decls[1], "y"), "5")
}

@(test)
test_parse_rejects_parenless_continuation :: proc(t: ^testing.T) {
	// x :: 4 + 2\n+ 3 — the deciding question, answered no: outside a
	// zone the newline ends the expression, and `+ 3` cannot start a
	// declaration. Green today and green after: the decision must not
	// accidentally relax this.
	tokens := []tok.Token{
		{offset = 0, value = tok.Identifier("x")},
		{offset = 2, value = tok.SimpleToken.Colon},
		{offset = 3, value = tok.SimpleToken.Colon},
		{offset = 5, value = tok.Number("4")},
		{offset = 7, value = tok.SimpleToken.Plus},
		{offset = 9, value = tok.Number("2")},
		{offset = 10, value = tok.SimpleToken.NewLine},
		{offset = 11, value = tok.SimpleToken.Plus},
		{offset = 13, value = tok.Number("3")},
		{offset = 14, value = tok.SimpleToken.EOF},
	}

	program, ok, _ := parse(tokens, new_test_arena(t))
	testing.expectf(t, !ok, "want a parse error for a paren-less continuation, but parse succeeded")
	_ = program
}

@(test)
test_parse_rejects_trailing_operator_at_newline :: proc(t: ^testing.T) {
	// x :: 4 +\n2 — the trailing-operator invariant outside a zone,
	// with a full operand waiting on the next line. Without parens the
	// newline ends the expression, so the dangling `+` still has no
	// right operand to grab. The zone rule must not absorb this.
	tokens := []tok.Token{
		{offset = 0, value = tok.Identifier("x")},
		{offset = 2, value = tok.SimpleToken.Colon},
		{offset = 3, value = tok.SimpleToken.Colon},
		{offset = 5, value = tok.Number("4")},
		{offset = 7, value = tok.SimpleToken.Plus},
		{offset = 8, value = tok.SimpleToken.NewLine},
		{offset = 9, value = tok.Number("2")},
		{offset = 10, value = tok.SimpleToken.EOF},
	}

	program, ok, _ := parse(tokens, new_test_arena(t))
	testing.expectf(t, !ok, "want a parse error for a trailing operator at a newline, but parse succeeded")
	_ = program
}

@(test)
test_parse_rejects_unclosed_zone_swallowing_decl :: proc(t: ^testing.T) {
	// x :: (4 + 2\ny :: 5 — the swallow hazard, pinned at the boundary.
	// The unclosed `(` eats the following declaration, so this must stay
	// an error both today (newline ends the inner expression, no `)`
	// follows) and after the zone rule (the zone absorbs the newline,
	// parses `y`, and still never finds its `)`). When recovery lands,
	// declaration start must resync even inside a zone; this test is
	// the guardrail for that too.
	tokens := []tok.Token{
		{offset = 0, value = tok.Identifier("x")},
		{offset = 2, value = tok.SimpleToken.Colon},
		{offset = 3, value = tok.SimpleToken.Colon},
		{offset = 5, value = tok.SimpleToken.LParen},
		{offset = 6, value = tok.Number("4")},
		{offset = 8, value = tok.SimpleToken.Plus},
		{offset = 10, value = tok.Number("2")},
		{offset = 11, value = tok.SimpleToken.NewLine},
		{offset = 12, value = tok.Identifier("y")},
		{offset = 14, value = tok.SimpleToken.Colon},
		{offset = 15, value = tok.SimpleToken.Colon},
		{offset = 17, value = tok.Number("5")},
		{offset = 18, value = tok.SimpleToken.EOF},
	}

	program, ok, _ := parse(tokens, new_test_arena(t))
	testing.expectf(t, !ok, "want a parse error for an unclosed zone, but parse succeeded")
	_ = program
}

// --- Zone-depth discipline ---------------------------------------------
//
// The counter has two jobs: absorb newlines while it is > 0, and be
// *inert* at 0. These tests pin the edges of that contract — the closer
// boundaries, the depth-0 behaviour, and deep nesting. Three are RED
// against the committed baseline; three are pins (green both before and
// after, guarding the depth-0 side).

@(test)
test_parse_multiline_group_newline_before_closer :: proc(t: ^testing.T) {
	// x :: (4 + 2\n) — a newline directly before the `)`. The closer
	// must still be found: the zone absorbs the newline, then ends.
	// RED against baseline: the loop stops at the NewLine and the
	// group never reaches its `)`.
	tokens := []tok.Token{
		{offset = 0, value = tok.Identifier("x")},
		{offset = 2, value = tok.SimpleToken.Colon},
		{offset = 3, value = tok.SimpleToken.Colon},
		{offset = 5, value = tok.SimpleToken.LParen},
		{offset = 6, value = tok.Number("4")},
		{offset = 8, value = tok.SimpleToken.Plus},
		{offset = 10, value = tok.Number("2")},
		{offset = 11, value = tok.SimpleToken.NewLine},
		{offset = 12, value = tok.SimpleToken.RParen},
		{offset = 13, value = tok.SimpleToken.EOF},
	}

	program, ok, err := parse(tokens, new_test_arena(t))
	testing.expectf(t, ok, "parse failed: %s", err)
	if !ok {
		return
	}

	expect_decls(t, program, 1)
	expect_binary(t, expect_const(t, program.decls[0], "x"), .Add)
}

@(test)
test_parse_multiline_group_triple_nested :: proc(t: ^testing.T) {
	// x :: (((4 +\n2))) — three zones deep, one newline at the bottom.
	// Every push must be matched by a pop: the inner newline is
	// absorbed, and all three closers resolve. RED against baseline.
	tokens := []tok.Token{
		{offset = 0, value = tok.Identifier("x")},
		{offset = 2, value = tok.SimpleToken.Colon},
		{offset = 3, value = tok.SimpleToken.Colon},
		{offset = 5, value = tok.SimpleToken.LParen},
		{offset = 6, value = tok.SimpleToken.LParen},
		{offset = 7, value = tok.SimpleToken.LParen},
		{offset = 8, value = tok.Number("4")},
		{offset = 10, value = tok.SimpleToken.Plus},
		{offset = 11, value = tok.SimpleToken.NewLine},
		{offset = 12, value = tok.Number("2")},
		{offset = 13, value = tok.SimpleToken.RParen},
		{offset = 14, value = tok.SimpleToken.RParen},
		{offset = 15, value = tok.SimpleToken.RParen},
		{offset = 16, value = tok.SimpleToken.EOF},
	}

	program, ok, err := parse(tokens, new_test_arena(t))
	testing.expectf(t, ok, "parse failed: %s", err)
	if !ok {
		return
	}

	expect_decls(t, program, 1)
	lhs, rhs := expect_binary(t, expect_const(t, program.decls[0], "x"), .Add)
	expect_number(t, lhs, "4")
	expect_number(t, rhs, "2")
}

@(test)
test_parse_multiline_group_unary_across_newline :: proc(t: ^testing.T) {
	// x :: (-\n5) — the unary arm also rides the zone: the operand may
	// start on the next line. RED against baseline: parse_prefix meets
	// the NewLine at the operand position and refuses it.
	tokens := []tok.Token{
		{offset = 0, value = tok.Identifier("x")},
		{offset = 2, value = tok.SimpleToken.Colon},
		{offset = 3, value = tok.SimpleToken.Colon},
		{offset = 5, value = tok.SimpleToken.LParen},
		{offset = 6, value = tok.SimpleToken.Minus},
		{offset = 7, value = tok.SimpleToken.NewLine},
		{offset = 8, value = tok.Number("5")},
		{offset = 9, value = tok.SimpleToken.RParen},
		{offset = 10, value = tok.SimpleToken.EOF},
	}

	program, ok, err := parse(tokens, new_test_arena(t))
	testing.expectf(t, ok, "parse failed: %s", err)
	if !ok {
		return
	}

	expect_decls(t, program, 1)
	expect_number(t, expect_unary(t, expect_const(t, program.decls[0], "x"), .Minus), "5")
}

@(test)
test_parse_rejects_unary_at_newline_at_depth_zero :: proc(t: ^testing.T) {
	// x :: -\n5 — the depth-0 twin of the test above: without the zone,
	// the newline still ends the expression and the unary `-` is left
	// dangling with no operand. The zone is what licenses continuation;
	// depth 0 must not quietly grow that licence.
	tokens := []tok.Token{
		{offset = 0, value = tok.Identifier("x")},
		{offset = 2, value = tok.SimpleToken.Colon},
		{offset = 3, value = tok.SimpleToken.Colon},
		{offset = 5, value = tok.SimpleToken.Minus},
		{offset = 6, value = tok.SimpleToken.NewLine},
		{offset = 7, value = tok.Number("5")},
		{offset = 8, value = tok.SimpleToken.EOF},
	}

	program, ok, _ := parse(tokens, new_test_arena(t))
	testing.expectf(t, !ok, "want a parse error for a dangling unary at a newline, but parse succeeded")
	_ = program
}

@(test)
test_parse_zone_closes_and_binary_continues_same_line :: proc(t: ^testing.T) {
	// x :: (4) + 2 — the counter must return to 0 the moment the `)`
	// matches, not lazily: a same-line binary operator after the closer
	// still binds at depth 0. If the pop were delayed, this would break.
	tokens := []tok.Token{
		{offset = 0, value = tok.Identifier("x")},
		{offset = 2, value = tok.SimpleToken.Colon},
		{offset = 3, value = tok.SimpleToken.Colon},
		{offset = 5, value = tok.SimpleToken.LParen},
		{offset = 6, value = tok.Number("4")},
		{offset = 7, value = tok.SimpleToken.RParen},
		{offset = 9, value = tok.SimpleToken.Plus},
		{offset = 11, value = tok.Number("2")},
		{offset = 12, value = tok.SimpleToken.EOF},
	}

	program, ok, err := parse(tokens, new_test_arena(t))
	testing.expectf(t, ok, "parse failed: %s", err)
	if !ok {
		return
	}

	expect_decls(t, program, 1)
	root_lhs, root_rhs := expect_binary_at(t, expect_const(t, program.decls[0], "x"), .Add, 9)
	expect_number(t, root_lhs, "4")
	expect_number(t, root_rhs, "2")
}

@(test)
test_parse_rejects_stray_closer_after_zone :: proc(t: ^testing.T) {
	// x :: (4)) — the group closes at the first `)`, dropping the depth
	// to 0; the second `)` is then a stray closer at depth 0 and must
	// be rejected. The counter must not swallow extra closers on its way
	// down — a pop matches a push, one for one.
	tokens := []tok.Token{
		{offset = 0, value = tok.Identifier("x")},
		{offset = 2, value = tok.SimpleToken.Colon},
		{offset = 3, value = tok.SimpleToken.Colon},
		{offset = 5, value = tok.SimpleToken.LParen},
		{offset = 6, value = tok.Number("4")},
		{offset = 7, value = tok.SimpleToken.RParen},
		{offset = 8, value = tok.SimpleToken.RParen},
		{offset = 9, value = tok.SimpleToken.EOF},
	}

	program, ok, _ := parse(tokens, new_test_arena(t))
	testing.expectf(t, !ok, "want a parse error for a stray closer, but parse succeeded")
	_ = program
}

@(test)
test_parse_rejects_newline_before_value :: proc(t: ^testing.T) {
	// x ::\n(3 + 4) — the §11.16 ruling: a declaration's value starts
	// on the same line as its `::`. The newline at depth 0 ends the
	// declaration header, so a parenthesised value on the next line has
	// no header to attach to. Green today (the newline is neither `::`
	// nor a type, so parse_decl's type-slot disambiguation refuses it);
	// this pins the accident as a rule.
	tokens := []tok.Token{
		{offset = 0, value = tok.Identifier("x")},
		{offset = 2, value = tok.SimpleToken.Colon},
		{offset = 3, value = tok.SimpleToken.Colon},
		{offset = 4, value = tok.SimpleToken.NewLine},
		{offset = 5, value = tok.SimpleToken.LParen},
		{offset = 6, value = tok.Number("3")},
		{offset = 8, value = tok.SimpleToken.Plus},
		{offset = 10, value = tok.Number("4")},
		{offset = 11, value = tok.SimpleToken.RParen},
		{offset = 12, value = tok.SimpleToken.EOF},
	}

	program, ok, _ := parse(tokens, new_test_arena(t))
	testing.expectf(t, !ok, "want a parse error for a value starting on the next line, but parse succeeded")
	_ = program
}

@(test)
test_parse_rejects_second_decl_on_same_line :: proc(t: ^testing.T) {
	// x :: 5 y :: 6 — the tail of the line-bounded ruling (§11.16): a
	// declaration occupies its line, so a second declaration on the same
	// line is an error. RED against the committed baseline, where the
	// parse loop happily consumed the second decl after the newline-free
	// gap.
	tokens := []tok.Token{
		{offset = 0, value = tok.Identifier("x")},
		{offset = 2, value = tok.SimpleToken.Colon},
		{offset = 3, value = tok.SimpleToken.Colon},
		{offset = 5, value = tok.Number("5")},
		{offset = 7, value = tok.Identifier("y")},
		{offset = 9, value = tok.SimpleToken.Colon},
		{offset = 10, value = tok.SimpleToken.Colon},
		{offset = 12, value = tok.Number("6")},
		{offset = 13, value = tok.SimpleToken.EOF},
	}

	program, ok, _ := parse(tokens, new_test_arena(t))
	testing.expectf(t, !ok, "want a parse error for a second declaration on the same line, but parse succeeded")
	_ = program
}

// --- Pre-pass unit tests ------------------------------------------------
//
// The pre-pass is the whole §11.16 decision in one function, so it earns
// direct tests on its own contract — the two failures that would be
// silent at the parse level.

@(test)
test_zoning_pre_parse_braces_are_not_zones :: proc(t: ^testing.T) {
	// { 4\n2 } — braces must never touch the counter: the NewLine inside
	// the block survives. If the pre-pass treated { } as a zone, block
	// statements would silently merge into one expression — statement
	// separation lost without a single error. This pins the asymmetry.
	tokens := []tok.Token{
		{offset = 0, value = tok.SimpleToken.LSquirly},
		{offset = 2, value = tok.Number("4")},
		{offset = 4, value = tok.SimpleToken.NewLine},
		{offset = 6, value = tok.Number("2")},
		{offset = 8, value = tok.SimpleToken.RSquirly},
		{offset = 9, value = tok.SimpleToken.EOF},
	}

	filtered := zoning_pre_parse(tokens, new_test_arena(t))
	testing.expectf(t, len(filtered) == 6, "want all 6 tokens kept, got %d", len(filtered))
	if len(filtered) != 6 {
		return
	}

	if simple, ok := filtered[2].value.(tok.SimpleToken); ok {
		testing.expectf(t, simple == .NewLine, "want the NewLine to survive, got %v", simple)
	} else {
		testing.expect(t, false, "want a SimpleToken at index 2")
	}
	testing.expectf(t, filtered[2].offset == 4, "want NewLine offset 4, got %d", filtered[2].offset)
}

@(test)
test_zoning_pre_parse_stray_closer_does_not_poison :: proc(t: ^testing.T) {
	// ) \n ( 4 +\n2 ) — a stray closer at depth 0 must be clamped, not
	// decremented into the negative. The NewLine right after it stays
	// (depth 0), but the NewLine inside the following zone is still
	// dropped. Without the clamp the interior NewLine survives too, and
	// a perfectly balanced zone expression breaks — the poisoning the
	// one-line guard prevents.
	tokens := []tok.Token{
		{offset = 0, value = tok.SimpleToken.RParen},
		{offset = 1, value = tok.SimpleToken.NewLine},
		{offset = 3, value = tok.SimpleToken.LParen},
		{offset = 4, value = tok.Number("4")},
		{offset = 6, value = tok.SimpleToken.Plus},
		{offset = 8, value = tok.SimpleToken.NewLine},
		{offset = 10, value = tok.Number("2")},
		{offset = 11, value = tok.SimpleToken.RParen},
		{offset = 13, value = tok.SimpleToken.EOF},
	}

	filtered := zoning_pre_parse(tokens, new_test_arena(t))
	testing.expectf(t, len(filtered) == 8, "want 8 tokens, got %d", len(filtered))
	if len(filtered) != 8 {
		return
	}

	// The stray closer and the depth-0 newline survive...
	if simple, ok := filtered[1].value.(tok.SimpleToken); ok {
		testing.expectf(t, simple == .NewLine, "want the depth-0 NewLine to survive, got %v", simple)
	} else {
		testing.expect(t, false, "want a SimpleToken at index 1")
	}
	// ...and the interior newline is gone: the operand `2` is compacted
	// to index 5, still carrying its original offset.
	testing.expectf(t, filtered[5].offset == 10, "want `2` compacted to index 5 at offset 10, got offset %d", filtered[5].offset)
}

// @(test) DISABLED — blocks not yet implemented. Re-enable by uncommenting
// the @(test) attribute when parse_decl grows the proc path and parse_block
// lands. This pins the zone-inside-block contract: the group is contained
// by its parens and must not disturb statement separation around it — if
// zone depth leaked past `)`, the two statements would merge into one.
test_parse_multiline_group_inside_block :: proc(t: ^testing.T) {
	// main :: proc() {\n(1 +\n2)\n(3 +\n4)\n} — two statements, each a
	// multi-line group. The block body stays newline-separated (braces
	// are not zones); the groups absorb their own newlines.
	tokens := []tok.Token{
		{offset = 0, value = tok.Identifier("main")},
		{offset = 5, value = tok.SimpleToken.Colon},
		{offset = 6, value = tok.SimpleToken.Colon},
		{offset = 8, value = tok.Keyword.Proc},
		{offset = 12, value = tok.SimpleToken.LParen},
		{offset = 13, value = tok.SimpleToken.RParen},
		{offset = 15, value = tok.SimpleToken.LSquirly},
		{offset = 16, value = tok.SimpleToken.NewLine},
		{offset = 17, value = tok.SimpleToken.LParen},
		{offset = 18, value = tok.Number("1")},
		{offset = 20, value = tok.SimpleToken.Plus},
		{offset = 21, value = tok.SimpleToken.NewLine},
		{offset = 22, value = tok.Number("2")},
		{offset = 23, value = tok.SimpleToken.RParen},
		{offset = 24, value = tok.SimpleToken.NewLine},
		{offset = 25, value = tok.SimpleToken.LParen},
		{offset = 26, value = tok.Number("3")},
		{offset = 28, value = tok.SimpleToken.Plus},
		{offset = 29, value = tok.SimpleToken.NewLine},
		{offset = 30, value = tok.Number("4")},
		{offset = 31, value = tok.SimpleToken.RParen},
		{offset = 32, value = tok.SimpleToken.NewLine},
		{offset = 33, value = tok.SimpleToken.RSquirly},
		{offset = 34, value = tok.SimpleToken.EOF},
	}

	program, ok, err := parse(tokens, new_test_arena(t))
	testing.expectf(t, ok, "parse failed: %s", err)
	if !ok {
		return
	}

	expect_decls(t, program, 1)
	body := expect_block(t, expect_proc(t, program.decls[0], "main"), 2)
	expect_binary_at(t, body[0], .Add, 20)
	expect_binary_at(t, body[1], .Add, 28)
}

// @(test) DISABLED — calls not yet implemented. Re-enable by uncommenting
// the @(test) attribute when parse_args and the call infix arm land. This
// pins §11.16's payoff: call parens are zones, so a multi-line argument
// list parses with no special machinery — the same zone depth the grouping
// arm pushes.
test_parse_multiline_args :: proc(t: ^testing.T) {
	// x :: f(a,\nb) — the comma's newline is absorbed inside the call's
	// paren zone. The Call node owns the args; the `(` offset 7 is the
	// creating token per the AST convention.
	tokens := []tok.Token{
		{offset = 0, value = tok.Identifier("x")},
		{offset = 2, value = tok.SimpleToken.Colon},
		{offset = 3, value = tok.SimpleToken.Colon},
		{offset = 5, value = tok.Identifier("f")},
		{offset = 7, value = tok.SimpleToken.LParen},
		{offset = 8, value = tok.Identifier("a")},
		{offset = 9, value = tok.SimpleToken.Comma},
		{offset = 10, value = tok.SimpleToken.NewLine},
		{offset = 11, value = tok.Identifier("b")},
		{offset = 12, value = tok.SimpleToken.RParen},
		{offset = 13, value = tok.SimpleToken.EOF},
	}

	program, ok, err := parse(tokens, new_test_arena(t))
	testing.expectf(t, ok, "parse failed: %s", err)
	if !ok {
		return
	}

	expect_decls(t, program, 1)
	args := expect_call_at(t, expect_const(t, program.decls[0], "x"), "f", 7)
	expect_ident(t, args[0], "a")
	expect_ident(t, args[1], "b")
}
