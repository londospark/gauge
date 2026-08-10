package integration

// End-to-end tests: a source string through the real pipeline — lexer,
// zone pre-pass, parser. The unit suites hand-build token slices, so they
// cannot catch a drift between what the lexer emits and what the parser
// expects; these can. The shapes chosen are the awkward ones: things the
// two stages see differently, or where a naive implementation would
// silently break the §11.16 contract.

import "core:testing"
import "core:mem"
import "../lexer"
import "../parser"
import tok "../token"

// new_test_arena returns an allocator backed by a fresh dynamic arena whose
// lifetime is tied to the test — the same discipline the parser suite uses,
// so a full pipeline run reports a balanced alloc/free pair instead of
// leaks.
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

// lex_and_parse runs a source string through the whole front end.
// failed_stage names where it broke ("lex" or "parse") so a test can pin
// the stage, not just the failure.
lex_and_parse :: proc(t: ^testing.T, src: string) -> (program: ^parser.Program, ok: bool, failed_stage: string) {
	arena := new_test_arena(t)
	lexer_state := lexer.make_lexer(src)
	tokens, lex_ok := lexer.lex(&lexer_state, arena)
	if !lex_ok {
		return nil, false, "lex"
	}

	program, ok, _ = parser.parse(tokens[:], arena)
	if !ok {
		return program, false, "parse"
	}
	return program, true, ""
}

// --- assertion helpers -------------------------------------------------
//
// Each helper asserts the expected node and hands the test whatever it
// needs next, so assertions read top-down instead of nesting. The `_at`
// variants also pin the node's byte offset.

expect_decls :: proc(t: ^testing.T, program: ^parser.Program, count: int) {
	testing.expectf(t, len(program.decls) == count, "want %d declaration(s), got %d", count, len(program.decls))
}

expect_const :: proc(t: ^testing.T, decl: ^parser.Expr, name: tok.Identifier) -> ^parser.Expr {
	#partial switch d in decl^ {
	case parser.Const:
		testing.expectf(t, d.name == name, "want const %q, got %q", name, d.name)
		return d.value
	case:
		testing.expectf(t, false, "want a const named %q", name)
	}
	return nil
}

expect_binary :: proc(t: ^testing.T, expr: ^parser.Expr, operator: parser.BinaryOperator) -> (lhs: ^parser.Expr, rhs: ^parser.Expr) {
	#partial switch v in expr^ {
	case parser.Binary:
		testing.expectf(t, v.operator == operator, "want binary %v, got %v", operator, v.operator)
		return v.lhs, v.rhs
	case:
		testing.expectf(t, false, "want a binary %v", operator)
	}
	return nil, nil
}

expect_binary_at :: proc(t: ^testing.T, expr: ^parser.Expr, operator: parser.BinaryOperator, offset: int) -> (lhs: ^parser.Expr, rhs: ^parser.Expr) {
	lhs, rhs = expect_binary(t, expr, operator)
	#partial switch v in expr^ {
	case parser.Binary:
		testing.expectf(t, v.offset == offset, "want %v at byte %d, got %d", operator, offset, v.offset)
	}
	return lhs, rhs
}

expect_number :: proc(t: ^testing.T, expr: ^parser.Expr, value: tok.Number) {
	#partial switch v in expr^ {
	case parser.Number:
		testing.expectf(t, v.value == value, "want number %q, got %q", value, v.value)
	case:
		testing.expectf(t, false, "want a number %q", value)
	}
}

expect_string :: proc(t: ^testing.T, expr: ^parser.Expr, value: tok.StringLiteral) {
	#partial switch v in expr^ {
	case parser.String:
		testing.expectf(t, v.value == value, "want string %q, got %q", value, v.value)
	case:
		testing.expectf(t, false, "want a string literal")
	}
}

expect_unary :: proc(t: ^testing.T, expr: ^parser.Expr, operator: parser.UnaryOperator) -> ^parser.Expr {
	#partial switch v in expr^ {
	case parser.Unary:
		testing.expectf(t, v.operator == operator, "want unary %v, got %v", operator, v.operator)
		return v.operand
	case:
		testing.expectf(t, false, "want a unary %v", operator)
	}
	return nil
}

@(test)
test_e2e_multiline_zone_arithmetic :: proc(t: ^testing.T) {
	// The §11.16 flagship through the real pipeline: the lexer emits the
	// newline, the pre-pass drops it inside the zone, and the parser
	// sees one continuous expression — with byte offsets intact, so the
	// root operator still points at the source's last `+`.
	src := "x :: (4 + 2 +\n3 + 5)"

	program, ok, stage := lex_and_parse(t, src)
	testing.expectf(t, ok, "expected a successful parse, failed in %s", stage)
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
test_e2e_string_with_newline_and_parens :: proc(t: ^testing.T) {
	// The awkward one: a string whose content contains both parens and a
	// newline. The parens are string data, not zone markers — the lexer
	// must not count them, the pre-pass must never see them, and the
	// parser must receive the content whole.
	src := "x :: \"(\n)\""

	program, ok, stage := lex_and_parse(t, src)
	testing.expectf(t, ok, "expected a successful parse, failed in %s", stage)
	if !ok {
		return
	}

	expect_decls(t, program, 1)
	expect_string(t, expect_const(t, program.decls[0], "x"), "(\n)")
}

@(test)
test_e2e_comment_inside_zone :: proc(t: ^testing.T) {
	// A comment inside a zone: the lexer skips the comment but still
	// emits the newline that ends it, the pre-pass drops that newline
	// (depth 1), and the expression continues across the comment as if
	// it were blank.
	src := "x :: (4 + // note\n2)"

	program, ok, stage := lex_and_parse(t, src)
	testing.expectf(t, ok, "expected a successful parse, failed in %s", stage)
	if !ok {
		return
	}

	expect_decls(t, program, 1)
	lhs, rhs := expect_binary_at(t, expect_const(t, program.decls[0], "x"), .Add, 8)
	expect_number(t, lhs, "4")
	expect_number(t, rhs, "2")
}

@(test)
test_e2e_parenless_continuation_rejected :: proc(t: ^testing.T) {
	// The deciding question, end to end: no parens, so the newline ends
	// the expression, and `+ 3` cannot start a declaration. The lexer is
	// perfectly happy — the parser must refuse.
	src := "x :: 4 + 2\n+ 3"

	_, ok, stage := lex_and_parse(t, src)
	testing.expectf(t, !ok, "want a parse error for a paren-less continuation")
	testing.expectf(t, stage == "parse", "want the failure in the parser, got %s", stage)
}

@(test)
test_e2e_unclosed_zone_swallows_decl :: proc(t: ^testing.T) {
	// The swallow hazard, end to end: the unclosed `(` eats the newline
	// and the following declaration, so the pipeline must fail in the
	// parser — and the declaration never surfaces.
	src := "x :: (4 + 2\ny :: 5"

	_, ok, stage := lex_and_parse(t, src)
	testing.expectf(t, !ok, "want a parse error for an unclosed zone")
	testing.expectf(t, stage == "parse", "want the failure in the parser, got %s", stage)
}

@(test)
test_e2e_zone_closes_then_newline_separates :: proc(t: ^testing.T) {
	// The depth-0 boundary, end to end: once the `)` closes the zone,
	// the next newline is significant again and a second declaration
	// follows.
	src := "x :: (4 + 2)\ny :: 5"

	program, ok, stage := lex_and_parse(t, src)
	testing.expectf(t, ok, "expected a successful parse, failed in %s", stage)
	if !ok {
		return
	}

	expect_decls(t, program, 2)
	expect_number(t, expect_const(t, program.decls[1], "y"), "5")
}

@(test)
test_e2e_blank_lines_between_decls :: proc(t: ^testing.T) {
	// Blank lines are just more newlines at declaration level; the
	// parser skips them. Two declarations, one blank line between.
	src := "x :: 5\n\ny :: 6\n"

	program, ok, stage := lex_and_parse(t, src)
	testing.expectf(t, ok, "expected a successful parse, failed in %s", stage)
	if !ok {
		return
	}

	expect_decls(t, program, 2)
	expect_number(t, expect_const(t, program.decls[0], "x"), "5")
}

@(test)
test_e2e_trailing_dot_number :: proc(t: ^testing.T) {
	// The trailing-dot quirk (spec/language.md §3.3, mirrored in
	// grammar.cf): `3.` is a legal number with zero fractional digits.
	// The lexer emits it whole and the parser accepts it.
	src := "x :: 3."

	program, ok, stage := lex_and_parse(t, src)
	testing.expectf(t, ok, "expected a successful parse, failed in %s", stage)
	if !ok {
		return
	}

	expect_decls(t, program, 1)
	expect_number(t, expect_const(t, program.decls[0], "x"), "3.")
}

@(test)
test_e2e_unterminated_string :: proc(t: ^testing.T) {
	// A string that runs off the end of the file: the lexer must fail,
	// and the parser must never be reached.
	src := "x :: \"abc"

	_, ok, stage := lex_and_parse(t, src)
	testing.expectf(t, !ok, "want a lex error for an unterminated string")
	testing.expectf(t, stage == "lex", "want the failure in the lexer, got %s", stage)
}
