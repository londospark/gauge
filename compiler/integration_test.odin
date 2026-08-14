package compiler

// End-to-end tests: a source string through the real pipeline — lexer,
// zone pre-pass, parser. The unit tests hand-build token slices, so they
// cannot catch a drift between what the lexer emits and what the parser
// expects; these can. The shapes chosen are the awkward ones: things the
// two stages see differently, or where a naive implementation would
// silently break the §11.16 contract.

import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import "core:testing"

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

// --- Full pipeline e2e: gauge source to a compiled binary -------------
//
// The feel-loop as tests: source → lex → parse → generate → C compiler →
// run. The C compiler is the judge (§11.20): these prove the emitted C is
// *valid*, not just the right text. The judge is whichever of cl/cc/gcc
// is on PATH — cl first on Windows, where the MSVC C-mode rules live (the
// C2099 fold exists for it); cc is the unix default; gcc covers mingw
// setups. Scratch files live in the OS temp directory.

C_Compiler :: struct {
	name:    string,
	is_msvc: bool,
}

// find_c_compiler locates the C compiler that judges the e2e tests.
// cl is preferred on Windows — the CI job's MSVC environment exists to
// prove the codegen's C-mode compatibility; cc and gcc are the fallbacks
// for bare shells and mingw setups. Elsewhere cc is the unix default.
find_c_compiler :: proc(allocator: mem.Allocator) -> (cc: C_Compiler, ok: bool) {
	path_env := os.get_env("PATH", allocator)
	defer delete(path_env, allocator)
	if len(path_env) == 0 do return {}, false

	exe_suffix := ".exe" when ODIN_OS == .Windows else ""
	separator  := ";"     when ODIN_OS == .Windows else ":"

	candidates: []string
	when ODIN_OS == .Windows {
		candidates = {"cl", "cc", "gcc"}
	} else {
		candidates = {"cc", "gcc"}
	}

	for candidate in candidates {
		exe_name := strings.concatenate({candidate, exe_suffix}, allocator)
		defer delete(exe_name, allocator)
		// split_iterator consumes its input, so every candidate scans a
		// fresh copy of the PATH header — otherwise the first candidate
		// exhausts the string and the rest find nothing.
		scan := path_env
		for dir in strings.split_iterator(&scan, separator) {
			full := os.join_path({dir, exe_name}, allocator) or_continue
			defer delete(full, allocator)
			if os.is_file(full) {
				return C_Compiler{name = candidate, is_msvc = candidate == "cl"}, true
			}
		}
	}

	return {}, false
}

// scratch_path joins a name onto the OS temp directory, so the e2e tests
// write nowhere near the repo and collide with nothing.
scratch_path :: proc(t: ^testing.T, name: string) -> string {
	scratch, err := os.temp_directory(context.allocator)
	if err != nil {
		testing.expectf(t, false, "temp directory unavailable: %v", err)
		return ""
	}
	defer delete(scratch, context.allocator)

	path := os.join_path({scratch, name}, context.allocator) or_else ""
	if path == "" {
		testing.expectf(t, false, "building the scratch path for %q failed", name)
	}
	return path
}

lex_parse_generate :: proc(t: ^testing.T, src: string) -> string {
	program, ok, stage := lex_and_parse(t, src)
	testing.expectf(t, ok, "expected a successful parse, failed in %s", stage)
	if !ok {
		return ""
	}
	return generate(program, new_test_arena(t))
}

@(test)
test_e2e_gauge_to_compiled_c :: proc(t: ^testing.T) {
	// The walker's output must be valid C, not just the right text: the
	// C compiler is the judge. Forward refs, composites, and a double
	// all in one program — the dependency order and the int/double
	// split must survive the compiler.
	src := "x :: 5\ny :: x + 1\nz :: y * 2\nw :: x + z\nd :: 2.5\n"
	c := lex_parse_generate(t, src)

	cc, cc_ok := find_c_compiler(context.allocator)
	if !cc_ok {
		testing.expectf(t, false, "no C compiler on PATH (cl, cc or gcc) — the e2e tests need one")
		return
	}

	c_path := scratch_path(t, "gauge_e2e_compile.c")
	defer delete(c_path, context.allocator)
	if c_path == "" do return

	if err := os.write_entire_file(c_path, c); err != nil {
		testing.expectf(t, false, "writing %s failed: %v", c_path, err)
		return
	}

	obj_path := scratch_path(t, "gauge_e2e_compile.o")
	defer delete(obj_path, context.allocator)
	if obj_path == "" do return

	command: []string
	fo_arg:  string
	if cc.is_msvc {
		fo_arg = fmt.aprintf("/Fo%s", obj_path, allocator = context.allocator)
		command = {cc.name, "/nologo", "/c", c_path, fo_arg}
	} else {
		command = {cc.name, "-c", c_path, "-o", obj_path}
	}
	// Declared outside the if so the defer outlives the command's use of
	// it — an if-body defer would free the arg before process_exec ran.
	defer if len(fo_arg) > 0 do delete(fo_arg, context.allocator)

	state, stdout, stderr, err := os.process_exec(
		{command = command},
		context.allocator,
	)
	defer delete(stdout)
	defer delete(stderr)

	if err != nil {
		testing.expectf(t, false, "%s failed to start: %v (%s)", cc.name, err, stderr)
		return
	}
	testing.expectf(t, state.exit_code == 0, "%s rejected the generated C with exit %d:\n%s", cc.name, state.exit_code, stderr)
}

@(test)
test_e2e_gauge_to_running_binary :: proc(t: ^testing.T) {
	// The full journey: gauge source → C → C compiler → a binary that
	// runs and prints. This is the demo's route, and the values it
	// prints are the consts' real semantics flowing through the whole
	// pipeline.
	src := "KiB :: 1024\nMiB :: KiB * 1024\nGiB :: MiB * 1024\n"
	gen_c := lex_parse_generate(t, src)

	cc, cc_ok := find_c_compiler(context.allocator)
	if !cc_ok {
		testing.expectf(t, false, "no C compiler on PATH (cl, cc or gcc) — the e2e tests need one")
		return
	}

	gen_path := scratch_path(t, "gauge_e2e_gen.c")
	defer delete(gen_path, context.allocator)
	if gen_path == "" do return

	main_path := scratch_path(t, "gauge_e2e_main.c")
	defer delete(main_path, context.allocator)
	if main_path == "" do return

	bin_path := scratch_path(t, "gauge_e2e_prog")
	defer delete(bin_path, context.allocator)
	if bin_path == "" do return

	if err := os.write_entire_file(gen_path, gen_c); err != nil {
		testing.expectf(t, false, "writing %s failed: %v", gen_path, err)
		return
	}
	// The generated consts are included, then printed. The include is
	// relative because the compiler searches the including file's own
	// directory first — both files live in the scratch dir, and no
	// platform-specific path text ever reaches the C source.
	main_c := "#include \"gauge_e2e_gen.c\"\n#include <stdio.h>\nint main(void) {\n\tprintf(\"%d\\n\", KiB);\n\tprintf(\"%d\\n\", MiB);\n\tprintf(\"%d\\n\", GiB);\n\treturn 0;\n}\n"
	if err := os.write_entire_file(main_path, main_c); err != nil {
		testing.expectf(t, false, "writing %s failed: %v", main_path, err)
		return
	}

	command: []string
	fe_arg:  string
	if cc.is_msvc {
		fe_arg = fmt.aprintf("/Fe%s", bin_path, allocator = context.allocator)
		command = {cc.name, "/nologo", main_path, fe_arg}
	} else {
		command = {cc.name, "-o", bin_path, main_path}
	}
	defer if len(fe_arg) > 0 do delete(fe_arg, context.allocator)

	compile_state, compile_out, compile_err, err := os.process_exec(
		{command = command},
		context.allocator,
	)
	defer delete(compile_out)
	defer delete(compile_err)

	if err != nil {
		testing.expectf(t, false, "%s failed to start: %v (%s)", cc.name, err, compile_err)
		return
	}
	testing.expectf(t, compile_state.exit_code == 0, "%s rejected the generated C with exit %d:\n%s", cc.name, compile_state.exit_code, compile_err)

	state, stdout, stderr, run_err := os.process_exec(
		{command = {bin_path}},
		context.allocator,
	)
	defer delete(stdout)
	defer delete(stderr)

	if run_err != nil {
		testing.expectf(t, false, "running the binary failed: %v (%s)", run_err, stderr)
		return
	}
	testing.expectf(t, state.exit_code == 0, "the binary exited %d: %s", state.exit_code, stderr)
	// The values are the point; the line endings are the C runtime's —
	// Windows printf writes CRLF in text mode, everywhere else LF.
	// Accept both rather than pin the platform's convention.
	got := string(stdout)
	testing.expectf(t,
		got == "1024\n1048576\n1073741824\n" ||
		got == "1024\r\n1048576\r\n1073741824\r\n",
		"want the KiB chain values, got %q", got)
}
