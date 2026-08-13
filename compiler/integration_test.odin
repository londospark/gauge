package compiler

// End-to-end tests: a source string through the real pipeline — lexer,
// zone pre-pass, parser. The unit tests hand-build token slices, so they
// cannot catch a drift between what the lexer emits and what the parser
// expects; these can. The shapes chosen are the awkward ones: things the
// two stages see differently, or where a naive implementation would
// silently break the §11.16 contract.

import "core:testing"
import "core:mem"

// lex_and_parse runs a source string through the whole front end.
// failed_stage names where it broke ("lex" or "parse") so a test can pin
// the stage, not just the failure.
lex_and_parse :: proc(t: ^testing.T, src: string) -> (program: ^Program, ok: bool, failed_stage: string) {
	arena := new_test_arena(t)
	lexer_state := make_lexer(src)
	tokens, lex_ok := lex(&lexer_state, arena)
	if !lex_ok {
		return nil, false, "lex"
	}

	program, ok, _ = parse(tokens[:], arena)
	if !ok {
		return program, false, "parse"
	}
	return program, true, ""
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
test_e2e_value_must_start_on_same_line :: proc(t: ^testing.T) {
	// The §11.16 ruling, end to end: a newline between `::` and the
	// value is significant (depth 0), so the parenthesised value on the
	// next line has no declaration header to attach to. The lexer
	// happily emits the newline; the parser must refuse.
	src := "x ::\n(3 + 4)"

	_, ok, stage := lex_and_parse(t, src)
	testing.expectf(t, !ok, "want a parse error for a value starting on the next line")
	testing.expectf(t, stage == "parse", "want the failure in the parser, got %s", stage)
}

@(test)
test_e2e_one_decl_per_line :: proc(t: ^testing.T) {
	// The line-bounded ruling, end to end: the lexer emits no newline
	// between the two declarations, so the parser must refuse the
	// second one. One declaration per line, no exceptions.
	src := "x :: 5 y :: 6"

	_, ok, stage := lex_and_parse(t, src)
	testing.expectf(t, !ok, "want a parse error for a second declaration on the same line")
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
