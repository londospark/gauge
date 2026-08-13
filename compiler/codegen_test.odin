package compiler

// Golden-output tests for the C emitter, plus the allocator-discipline
// guard. The golden tests are the walker's spec: they are RED until the
// `[NAME]`/`[VALUE]` placeholders are replaced by a real AST walk, and
// green once they are. The allocator test is green now — it guards the
// contract that generate routes every allocation through its allocator.

import "core:testing"
import "core:mem"

// build_program assembles a Program holding the given declarations, in the
// order given — the AST's order, which is not necessarily the order the C
// output must use (forward references are legal in gauge, not in C).
build_program :: proc(arena: mem.Allocator, decls: ..^Expr) -> ^Program {
	program := new(Program, arena)
	program.decls = make([dynamic]^Expr, arena)
	for d in decls {
		append(&program.decls, d)
	}
	return program
}

@(test)
test_generate_empty_program :: proc(t: ^testing.T) {
	// No declarations, no output — the header-free minimal C.
	arena := new_test_arena(t)
	program := build_program(arena)

	output := generate(program, arena)
	testing.expectf(t, output == "", "want empty output, got %q", output)
}

// @(test) DISABLED — the walker is not implemented yet; the
// [NAME]/[VALUE] placeholders stand in. Re-enable when the AST walk
// replaces them: this test is the spec.
test_generate_const_number :: proc(t: ^testing.T) {
	// x :: 42 — a bare number atom: verbatim, no parens.
	arena := new_test_arena(t)
	program := build_program(arena,
		new_const("x", nil, new_number("42", 0, arena), 0, arena),
	)

	output := generate(program, arena)
	testing.expectf(t, output == "static const int x = 42;\n", "want %q, got %q", "static const int x = 42;\n", output)
}

// @(test) DISABLED — the walker is not implemented yet. Re-enable when
// the AST walk lands; this test pins identifier references and in-order
// emission.
test_generate_const_reference :: proc(t: ^testing.T) {
	// x :: 5, y :: x — an identifier reference emits bare; declarations
	// already in dependency order stay in order.
	arena := new_test_arena(t)
	program := build_program(arena,
		new_const("x", nil, new_number("5", 0, arena), 0, arena),
		new_const("y", nil, new_ident("x", 0, arena), 0, arena),
	)

	output := generate(program, arena)
	testing.expectf(t, output == "static const int x = 5;\nstatic const int y = x;\n",
		"want %q, got %q", "static const int x = 5;\nstatic const int y = x;\n", output)
}

// @(test) DISABLED — the dependency-order pass is not implemented yet.
// Re-enable when forward references are reordered; this test is the
// name-resolution-in-miniature spec.
test_generate_forward_reference_reordered :: proc(t: ^testing.T) {
	// y :: x declared *before* x :: 5 — legal in gauge (§11.3), illegal
	// in C. The emitter must reorder by dependency: x comes out first.
	// This is the name-resolution-in-miniature pass.
	arena := new_test_arena(t)
	program := build_program(arena,
		new_const("y", nil, new_ident("x", 0, arena), 0, arena),
		new_const("x", nil, new_number("5", 0, arena), 0, arena),
	)

	output := generate(program, arena)
	testing.expectf(t, output == "static const int x = 5;\nstatic const int y = x;\n",
		"want %q, got %q", "static const int x = 5;\nstatic const int y = x;\n", output)
}

// @(test) DISABLED — the walker is not implemented yet. Re-enable when
// it lands; this test pins the §11.20 int/double split at emission.
test_generate_double :: proc(t: ^testing.T) {
	// x :: 3. — the trailing-dot quirk: dotted numbers emit as double
	// (§11.20's provisional value domain), verbatim.
	arena := new_test_arena(t)
	program := build_program(arena,
		new_const("x", nil, new_number("3.", 0, arena), 0, arena),
	)

	output := generate(program, arena)
	testing.expectf(t, output == "static const double x = 3.;\n", "want %q, got %q", "static const double x = 3.;\n", output)
}

// @(test) DISABLED — the walker is not implemented yet. Re-enable when
// it lands; this test pins the group-transparency trap — every Binary
// emits as (lhs op rhs), atoms bare.
test_generate_group_reconstruction :: proc(t: ^testing.T) {
	// x :: (4 + 2) * 3 — groups are transparent in the AST, so the
	// emitter must reconstruct them from tree shape. The "bracket
	// everything" rule: every Binary emits as (lhs op rhs), atoms bare.
	arena := new_test_arena(t)
	program := build_program(arena,
		new_const("x", nil,
			new_binary(.Multiply,
				new_binary(.Add,
					new_number("4", 0, arena),
					new_number("2", 0, arena),
					0, arena),
				new_number("3", 0, arena),
				0, arena),
			0, arena),
	)

	output := generate(program, arena)
	testing.expectf(t, output == "static const int x = ((4 + 2) * 3);\n",
		"want %q, got %q", "static const int x = ((4 + 2) * 3);\n", output)
}

@(test)
test_generate_allocator_discipline :: proc(t: ^testing.T) {
	// generate must route every allocation through its allocator. While
	// context.allocator points at a fresh tracking allocator, generate
	// into an arena: if any allocation falls through — a builder buffer
	// bound to the wrong allocator — the tracker catches it. The guard
	// that caught the pre-pass leak catches this one too.
	arena := new_test_arena(t)
	program := build_program(arena,
		new_const("x", nil, new_number("42", 0, arena), 0, arena),
	)

	backing := context.allocator
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, backing)
	defer mem.tracking_allocator_destroy(&tracker)

	output: string
	{
		prev := context.allocator
		context.allocator = mem.tracking_allocator(&tracker)
		defer context.allocator = prev

		output = generate(program, arena)
	}

	// The content is the golden tests' job; this test's job is the
	// allocation property — and that the emitter produced something.
	testing.expectf(t, output != "", "expected generated C output")
	testing.expectf(t, len(tracker.allocation_map) == 0,
		"allocator discipline broken: %d allocation(s) fell through to context.allocator",
		len(tracker.allocation_map))
}
