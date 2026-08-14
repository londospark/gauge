package compiler

// Golden-output tests for the C emitter, plus the allocator-discipline
// guard. The golden tests are the walker's spec: green where the walker
// has landed, red where it has not. The allocator guard is green — it
// confirms generate routes every allocation through its allocator.

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

@(test)
test_generate_const_number :: proc(t: ^testing.T) {
	// x :: 42 — a bare number atom: verbatim, no parens.
	arena := new_test_arena(t)
	program := build_program(arena,
		new_const("x", nil, new_number("42", 0, arena), 0, arena),
	)

	output := generate(program, arena)
	testing.expectf(t, output == "static const int x = 42;\n", "want %q, got %q", "static const int x = 42;\n", output)
}

@(test)
test_generate_const_reference :: proc(t: ^testing.T) {
	// x :: 5, y :: x — a reference substitutes the referenced const's
	// emitted value, so the initializer stays a true C constant
	// expression: `const` variables are not constant expressions in C,
	// and MSVC rejects `static const int y = x;` with C2099 (gcc/clang
	// accept it as an extension). The substitution is possible because
	// emission is dependency-ordered — x is always emitted first.
	arena := new_test_arena(t)
	program := build_program(arena,
		new_const("x", nil, new_number("5", 0, arena), 0, arena),
		new_const("y", nil, new_ident("x", 0, arena), 0, arena),
	)

	output := generate(program, arena)
	testing.expectf(t, output == "static const int x = 5;\nstatic const int y = 5;\n",
		"want %q, got %q", "static const int x = 5;\nstatic const int y = 5;\n", output)
}

@(test)
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
	testing.expectf(t, output == "static const int x = 5;\nstatic const int y = 5;\n",
		"want %q, got %q", "static const int x = 5;\nstatic const int y = 5;\n", output)
}

// --- The ordering pass, through generate ------------------------------
//
// Three of these are pins: the cycle, self-reference, and undefined-ref
// cases emit in source order today, and the fallback must preserve that
// order when the work-list lands. Four are red specs: they need the
// dependency ordering to emit correctly.

@(test)
test_generate_forward_chain :: proc(t: ^testing.T) {
	// z :: y, y :: x, x :: 5 — declared in full reverse. Only x is
	// ready in the first round; the work-list needs three rounds.
	arena := new_test_arena(t)
	program := build_program(arena,
		new_const("z", nil, new_ident("y", 0, arena), 0, arena),
		new_const("y", nil, new_ident("x", 0, arena), 0, arena),
		new_const("x", nil, new_number("5", 0, arena), 0, arena),
	)

	output := generate(program, arena)
	expected := "static const int x = 5;\nstatic const int y = 5;\nstatic const int z = 5;\n"
	testing.expectf(t, output == expected, "want %q, got %q", expected, output)
}

@(test)
test_generate_diamond_dependency :: proc(t: ^testing.T) {
	// a :: 1, b :: a, c :: a, d :: b + c — b and c become ready in the
	// same round once a emits; d waits for both. Within a round, the
	// work-list emits in source order — that is the deterministic
	// contract this pins.
	arena := new_test_arena(t)
	program := build_program(arena,
		new_const("d", nil,
			new_binary(.Add, new_ident("b", 0, arena), new_ident("c", 0, arena), 0, arena),
			0, arena),
		new_const("a", nil, new_number("1", 0, arena), 0, arena),
		new_const("b", nil, new_ident("a", 0, arena), 0, arena),
		new_const("c", nil, new_ident("a", 0, arena), 0, arena),
	)

	output := generate(program, arena)
	expected := "static const int a = 1;\nstatic const int b = 1;\nstatic const int c = 1;\nstatic const int d = (1 + 1);\n"
	testing.expectf(t, output == expected, "want %q, got %q", expected, output)
}

@(test)
test_generate_forward_reference_type_flows :: proc(t: ^testing.T) {
	// y :: x declared before x :: 3. — reordering and type propagation
	// together: x is double, y inherits it, and x emits first. The type
	// map is order-independent; this pins that the reorder keeps it so.
	arena := new_test_arena(t)
	program := build_program(arena,
		new_const("y", nil, new_ident("x", 0, arena), 0, arena),
		new_const("x", nil, new_number("3.", 0, arena), 0, arena),
	)

	output := generate(program, arena)
	expected := "static const double x = 3.;\nstatic const double y = 3.;\n"
	testing.expectf(t, output == expected, "want %q, got %q", expected, output)
}

@(test)
test_generate_cycle_emits_in_source_order :: proc(t: ^testing.T) {
	// a :: b, b :: a — a cycle never becomes ready; the work-list must
	// not hang. The fallback emits the leftovers in source order and cc
	// reports the undeclared identifier — the codegen always produces
	// output. Green today, must stay green.
	arena := new_test_arena(t)
	program := build_program(arena,
		new_const("a", nil, new_ident("b", 0, arena), 0, arena),
		new_const("b", nil, new_ident("a", 0, arena), 0, arena),
	)

	output := generate(program, arena)
	expected := "static const int a = b;\nstatic const int b = a;\n"
	testing.expectf(t, output == expected, "want %q, got %q", expected, output)
}

@(test)
test_generate_self_reference_does_not_hang :: proc(t: ^testing.T) {
	// a :: a — the degenerate cycle. Same story: fallback, source
	// order, cc's error. Green today, must stay green.
	arena := new_test_arena(t)
	program := build_program(arena,
		new_const("a", nil, new_ident("a", 0, arena), 0, arena),
	)

	output := generate(program, arena)
	expected := "static const int a = a;\n"
	testing.expectf(t, output == expected, "want %q, got %q", expected, output)
}

@(test)
test_generate_undefined_ref_does_not_block_ready :: proc(t: ^testing.T) {
	// a :: 1, b :: a, c :: z (z undefined) — the ready consts emit in
	// order; c stalls, lands in the fallback, and comes last in source
	// order. The undefined reference must not hold the good
	// declarations back. Green today, must stay green.
	arena := new_test_arena(t)
	program := build_program(arena,
		new_const("a", nil, new_number("1", 0, arena), 0, arena),
		new_const("b", nil, new_ident("a", 0, arena), 0, arena),
		new_const("c", nil, new_ident("z", 0, arena), 0, arena),
	)

	output := generate(program, arena)
	expected := "static const int a = 1;\nstatic const int b = 1;\nstatic const int c = z;\n"
	testing.expectf(t, output == expected, "want %q, got %q", expected, output)
}

@(test)
test_generate_ordering_general_case :: proc(t: ^testing.T) {
	// d :: c + b, a :: 1, c :: b * 2, b :: a + 1, e :: missing —
	// everything at once: multi-round readiness, composite refs, an
	// undefined reference, and the fallback. Rounds: a, then b, then
	// c, then d; e stalls and lands last via the fallback.
	arena := new_test_arena(t)
	program := build_program(arena,
		new_const("d", nil,
			new_binary(.Add, new_ident("c", 0, arena), new_ident("b", 0, arena), 0, arena),
			0, arena),
		new_const("a", nil, new_number("1", 0, arena), 0, arena),
		new_const("c", nil,
			new_binary(.Multiply, new_ident("b", 0, arena), new_number("2", 0, arena), 0, arena),
			0, arena),
		new_const("b", nil,
			new_binary(.Add, new_ident("a", 0, arena), new_number("1", 0, arena), 0, arena),
			0, arena),
		new_const("e", nil, new_ident("missing", 0, arena), 0, arena),
	)

	output := generate(program, arena)
	expected := "static const int a = 1;\nstatic const int b = (1 + 1);\nstatic const int c = ((1 + 1) * 2);\nstatic const int d = (((1 + 1) * 2) + (1 + 1));\nstatic const int e = missing;\n"
	testing.expectf(t, output == expected, "want %q, got %q", expected, output)
}

@(test)
test_generate_reference_type_propagates :: proc(t: ^testing.T) {
	// x :: 3. then y :: x — the type of a reference is the type of the
	// const it names: y inherits x's double, so the emission must say
	// `static const double y`, not int. This is the identifier typing the
	// dependency-order pass needs — and the sharper reason the type must
	// flow through references, not just literals.
	arena := new_test_arena(t)
	program := build_program(arena,
		new_const("x", nil, new_number("3.", 0, arena), 0, arena),
		new_const("y", nil, new_ident("x", 0, arena), 0, arena),
	)

	output := generate(program, arena)
	testing.expectf(t, output == "static const double x = 3.;\nstatic const double y = 3.;\n",
		"want %q, got %q", "static const double x = 3.;\nstatic const double y = 3.;\n", output)
}

@(test)
test_generate_undefined_identifier :: proc(t: ^testing.T) {
	// y :: x with no x anywhere — the codegen must not error and must
	// not emit an empty type slot: it defaults the type to int and emits
	// the reference verbatim, so cc reports the real problem
	// ("undeclared identifier `x`") in gauge coordinates instead of a C
	// syntax error from a malformed declaration. §11.20's stance: cc is
	// the error handler.
	arena := new_test_arena(t)
	program := build_program(arena,
		new_const("y", nil, new_ident("x", 0, arena), 0, arena),
	)

	output := generate(program, arena)
	testing.expectf(t, output == "static const int y = x;\n",
		"want %q, got %q", "static const int y = x;\n", output)
}

@(test)
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

@(test)
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
test_generate_unary :: proc(t: ^testing.T) {
	// x :: -42 — the unary arm: Minus emits `-`, the operand follows.
	// Bracketed like every composite, atoms bare.
	arena := new_test_arena(t)
	program := build_program(arena,
		new_const("x", nil, new_unary(.Minus, new_number("42", 0, arena), 0, arena), 0, arena),
	)

	output := generate(program, arena)
	testing.expectf(t, output == "static const int x = (-42);\n",
		"want %q, got %q", "static const int x = (-42);\n", output)
}

@(test)
test_generate_double_unary :: proc(t: ^testing.T) {
	// x :: --4 — the reason unary bracketing is a requirement, not a
	// taste: emitted bare, two minuses become `--4`, which C lexes as
	// the decrement operator. The bracket-everything rule must wrap
	// Unary just as it wraps Binary.
	arena := new_test_arena(t)
	program := build_program(arena,
		new_const("x", nil,
			new_unary(.Minus,
				new_unary(.Minus,
					new_number("4", 0, arena),
					0, arena),
				0, arena),
			0, arena),
	)

	output := generate(program, arena)
	testing.expectf(t, output == "static const int x = (-(-4));\n",
		"want %q, got %q", "static const int x = (-(-4));\n", output)
}

// --- The ordering pass's building blocks ------------------------------
//
// Two pure functions, tested in isolation before the work-list exists.
// The signatures are the contract:
//
//   collect_refs(expr, refs)          — append every identifier the value
//                                       references, in walk order.
//   is_ready(refs, emitted) -> bool   — every name in refs is present in
//                                       emitted; membership, not counts.

check_refs :: proc(t: ^testing.T, arena: mem.Allocator, expr: ^Expr, expected: []IdentifierToken) {
	refs := make([dynamic]IdentifierToken, arena)
	collect_refs(expr, &refs)

	testing.expectf(t, len(refs) == len(expected), "want %d refs, got %d: %v", len(expected), len(refs), refs)
	if len(refs) != len(expected) {
		return
	}
	for i in 0 ..< len(expected) {
		testing.expectf(t, refs[i] == expected[i], "want ref %d = %q, got %q", i, expected[i], refs[i])
	}
}

@(test)
test_collect_refs :: proc(t: ^testing.T) {
	arena := new_test_arena(t)

	// Numbers, in isolation and in variants: a number references nothing.
	check_refs(t, arena, new_number("42", 0, arena), []IdentifierToken{})
	check_refs(t, arena, new_number("3.14", 0, arena), []IdentifierToken{})

	// The identifier in isolation: it references exactly itself.
	check_refs(t, arena, new_ident("y", 0, arena), []IdentifierToken{"y"})
	check_refs(t, arena, new_ident("longer_name", 0, arena), []IdentifierToken{"longer_name"})

	// Unary: walks its operand — both operators, and only identifiers.
	check_refs(t, arena, new_unary(.Minus, new_ident("n", 0, arena), 0, arena), []IdentifierToken{"n"})
	check_refs(t, arena, new_unary(.Plus, new_ident("p", 0, arena), 0, arena), []IdentifierToken{"p"})
	check_refs(t, arena, new_unary(.Minus, new_number("5", 0, arena), 0, arena), []IdentifierToken{})
	// Double negation still resolves to the single operand.
	check_refs(t, arena,
		new_unary(.Minus, new_unary(.Minus, new_ident("x", 0, arena), 0, arena), 0, arena),
		[]IdentifierToken{"x"})

	// Binary: lhs refs before rhs refs — walk order, not name order.
	check_refs(t, arena,
		new_binary(.Add, new_ident("a", 0, arena), new_ident("b", 0, arena), 0, arena),
		[]IdentifierToken{"a", "b"})
	check_refs(t, arena,
		new_binary(.Add, new_ident("b", 0, arena), new_ident("a", 0, arena), 0, arena),
		[]IdentifierToken{"b", "a"})
	// A binary over pure numbers references nothing.
	check_refs(t, arena,
		new_binary(.Divide, new_number("6", 0, arena), new_number("3", 0, arena), 0, arena),
		[]IdentifierToken{})
	// A mixed binary keeps only the identifier side.
	check_refs(t, arena,
		new_binary(.Multiply, new_number("2", 0, arena), new_ident("z", 0, arena), 0, arena),
		[]IdentifierToken{"z"})
	// Duplicates are appended, not deduped — readiness is presence-based,
	// so the collector stays dumb and the predicate copes.
	check_refs(t, arena,
		new_binary(.Add, new_ident("a", 0, arena), new_ident("a", 0, arena), 0, arena),
		[]IdentifierToken{"a", "a"})

	// Unary wrapping a binary: the composite's refs come through whole.
	check_refs(t, arena,
		new_unary(.Minus,
			new_binary(.Add, new_ident("a", 0, arena), new_ident("b", 0, arena), 0, arena),
			0, arena),
		[]IdentifierToken{"a", "b"})

	// The larger general case: nested composites, refs in walk order —
	// (a * (b + c)) - (d + e) collects a, b, c, d, e.
	check_refs(t, arena,
		new_binary(.Subtract,
			new_binary(.Multiply,
				new_ident("a", 0, arena),
				new_binary(.Add, new_ident("b", 0, arena), new_ident("c", 0, arena), 0, arena),
				0, arena),
			new_binary(.Add, new_ident("d", 0, arena), new_ident("e", 0, arena), 0, arena),
			0, arena),
		[]IdentifierToken{"a", "b", "c", "d", "e"})
}

@(test)
test_is_ready :: proc(t: ^testing.T) {
	// No dependencies: always ready, whatever the emitted set holds.
	testing.expectf(t, is_ready([]IdentifierToken{}, []IdentifierToken{}), "no deps, no emitted: ready")
	testing.expectf(t, is_ready([]IdentifierToken{}, []IdentifierToken{"x"}), "no deps regardless of emitted: ready")

	// Presence, not position or count.
	testing.expectf(t, is_ready([]IdentifierToken{"x"}, []IdentifierToken{"x"}), "a satisfied dep is ready")
	testing.expectf(t, is_ready([]IdentifierToken{"x"}, []IdentifierToken{"x", "y"}), "extra emitted names do not block readiness")
	testing.expectf(t, is_ready([]IdentifierToken{"a", "b"}, []IdentifierToken{"b", "a"}), "membership is order-independent")

	// Absence blocks readiness.
	testing.expectf(t, !is_ready([]IdentifierToken{"x"}, []IdentifierToken{}), "an unsatisfied dep is not ready")
	testing.expectf(t, !is_ready([]IdentifierToken{"a", "b"}, []IdentifierToken{"a"}), "one missing dep blocks readiness")
	testing.expectf(t, !is_ready([]IdentifierToken{"z"}, []IdentifierToken{"x", "y"}), "a dep on a non-const is never ready")

	// Equality is exact — no prefix or substring matches.
	testing.expectf(t, !is_ready([]IdentifierToken{"x"}, []IdentifierToken{"x_2"}), "a longer name is not a match")
	testing.expectf(t, !is_ready([]IdentifierToken{"xx"}, []IdentifierToken{"x"}), "a shorter name is not a match")

	// Duplicates are presence, not counts — in either argument.
	testing.expectf(t, is_ready([]IdentifierToken{"x", "x"}, []IdentifierToken{"x"}), "duplicate deps are presence, not counts")
	testing.expectf(t, is_ready([]IdentifierToken{"x"}, []IdentifierToken{"x", "x"}), "duplicate emissions are presence, not counts")

	// The larger general case: many deps, all present; many deps, one missing.
	testing.expectf(t, is_ready([]IdentifierToken{"a", "b", "c", "d"}, []IdentifierToken{"d", "c", "b", "a"}), "many deps, all present: ready")
	testing.expectf(t, !is_ready([]IdentifierToken{"a", "b", "c", "d"}, []IdentifierToken{"d", "c", "b"}), "many deps, one missing: not ready")
}

@(test)
test_generate_allocator_discipline :: proc(t: ^testing.T) {
	// generate must route every allocation through its allocator. While
	// context.allocator points at a fresh tracking allocator, generate
	// into an arena: if any allocation falls through — a builder buffer
	// bound to the wrong allocator, or a composite string built with
	// fmt.tprintf instead of the threaded allocator — the tracker
	// catches it. The input is a Binary on purpose: that is the code
	// path that allocates, and a Number-only input would never exercise
	// it. The guard that caught the pre-pass leak catches these too.
	arena := new_test_arena(t)
	program := build_program(arena,
		new_const("x", nil,
			new_binary(.Add,
				new_unary(.Minus,
					new_number("4", 0, arena),
					0, arena),
				new_number("2", 0, arena),
				0, arena),
			0, arena),
	)

	backing := context.allocator
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, backing)
	defer mem.tracking_allocator_destroy(&tracker)

	// fmt.tprintf hides in context.temp_allocator, not context.allocator —
	// a single guard would watch the wrong one and miss it.
	temp_backing := context.temp_allocator
	temp_tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&temp_tracker, temp_backing)
	defer mem.tracking_allocator_destroy(&temp_tracker)

	output: string
	{
		prev_alloc := context.allocator
		prev_temp := context.temp_allocator
		context.allocator = mem.tracking_allocator(&tracker)
		context.temp_allocator = mem.tracking_allocator(&temp_tracker)
		defer context.allocator = prev_alloc
		defer context.temp_allocator = prev_temp

		output = generate(program, arena)
	}

	// The content is the golden tests' job; this test's job is the
	// allocation property — and that the emitter produced something.
	testing.expectf(t, output != "", "expected generated C output")
	testing.expectf(t, len(tracker.allocation_map) == 0,
		"allocator discipline broken: %d allocation(s) fell through to context.allocator",
		len(tracker.allocation_map))
	testing.expectf(t, len(temp_tracker.allocation_map) == 0,
		"temp allocator discipline broken: %d allocation(s) fell through to context.temp_allocator",
		len(temp_tracker.allocation_map))
}
