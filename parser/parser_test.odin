package parser

import "core:testing"
import tok "../token"

@(test)
test_parse_const_number :: proc(t: ^testing.T) {
	tokens := []tok.Token{
		{offset = 0, value = tok.Identifier("x")},
		{offset = 2, value = tok.SimpleToken.Colon},
		{offset = 3, value = tok.SimpleToken.Colon},
		{offset = 5, value = tok.Number("42")},
		{offset = 7, value = tok.SimpleToken.EOF},
	}

	program, ok, err := parse(tokens, context.temp_allocator)
	testing.expectf(t, ok, "parse failed: %s", err)
	if !ok {
		return
	}

	testing.expectf(t, len(program.decls) == 1, "want 1 declaration, got %d", len(program.decls))
	if len(program.decls) != 1 {
		return
	}

	#partial switch d in program.decls[0]^ {
	case Const:
		testing.expectf(t, d.name == "x", "want constant 'x', got %q", d.name)
		#partial switch v in d.value^ {
		case Number:
			testing.expectf(t, v.value == "42", "want number 42, got %q", v.value)
		case:
			testing.expect(t, false, "constant value should be a number literal")
		}
	case:
		testing.expect(t, false, "first declaration should be a constant")
	}
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

	program, ok, err := parse(tokens, context.temp_allocator)
	testing.expectf(t, ok, "parse failed: %s", err)
	if !ok {
		return
	}

	testing.expectf(t, len(program.decls) == 1, "want 1 declaration, got %d", len(program.decls))
	if len(program.decls) != 1 {
		return
	}

	#partial switch d in program.decls[0]^ {
	case Const:
		testing.expectf(t, d.name == "greeting", "want constant 'greeting', got %q", d.name)
		#partial switch v in d.value^ {
		case String:
			testing.expectf(t, v.value == "hellope", "want string \"hellope\", got %q", v.value)
		case:
			testing.expect(t, false, "constant value should be a string literal")
		}
	case:
		testing.expect(t, false, "first declaration should be a constant")
	}
}

@(test)
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

	program, ok, err := parse(tokens, context.temp_allocator)
	testing.expectf(t, ok, "parse failed: %s", err)
	if !ok {
		return
	}

	testing.expectf(t, len(program.decls) == 1, "want 1 declaration, got %d", len(program.decls))
	if len(program.decls) != 1 {
		return
	}

	#partial switch d in program.decls[0]^ {
	case Proc:
		testing.expectf(t, d.name == "main", "want procedure 'main', got %q", d.name)
		testing.expectf(t, len(d.body.body) == 0, "want an empty body, got %d expressions", len(d.body.body))
	case:
		testing.expect(t, false, "first declaration should be a procedure")
	}
}

@(test)
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

	program, ok, err := parse(tokens, context.temp_allocator)
	testing.expectf(t, ok, "parse failed: %s", err)
	if !ok {
		return
	}

	testing.expectf(t, len(program.decls) == 1, "want 1 declaration, got %d", len(program.decls))
	if len(program.decls) != 1 {
		return
	}

	#partial switch d in program.decls[0]^ {
	case Proc:
		testing.expectf(t, d.name == "main", "want procedure 'main', got %q", d.name)
		testing.expectf(t, len(d.body.body) == 1, "want 1 body expression, got %d", len(d.body.body))
		if len(d.body.body) != 1 {
			return
		}
		#partial switch first in d.body.body[0]^ {
		case Assign:
			testing.expectf(t, first.name == "answer", "want assignment to 'answer', got %q", first.name)
		case:
			testing.expect(t, false, "body expression should be an assignment")
		}
	case:
		testing.expect(t, false, "first declaration should be a procedure")
	}
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

	program, ok, err := parse(tokens, context.temp_allocator)
	testing.expectf(t, ok, "parse failed: %s", err)
	if !ok {
		return
	}

	testing.expectf(t, len(program.decls) == 2, "want 2 declarations, got %d", len(program.decls))
	if len(program.decls) != 2 {
		return
	}

	#partial switch d in program.decls[0]^ {
	case Const:
		testing.expectf(t, d.name == "KiB", "want constant 'KiB', got %q", d.name)
		#partial switch v in d.value^ {
		case Number:
			testing.expectf(t, v.value == "1024", "want KiB value 1024, got %q", v.value)
		case:
			testing.expect(t, false, "KiB value should be a number literal")
		}
	case:
		testing.expect(t, false, "first declaration should be a constant")
	}

	#partial switch d in program.decls[1]^ {
	case Const:
		testing.expectf(t, d.name == "MiB", "want constant 'MiB', got %q", d.name)
		#partial switch v in d.value^ {
		case Binary:
			testing.expectf(t, v.operator == .Multiply, "want Multiply, got %v", v.operator)
			#partial switch lhs in v.lhs^ {
			case Number:
				testing.expectf(t, lhs.value == "1024", "want lhs number 1024, got %q", lhs.value)
			case:
				testing.expect(t, false, "MiB lhs should be a number literal")
			}
			#partial switch rhs in v.rhs^ {
			case Ident:
				testing.expectf(t, rhs.name == "KiB", "want rhs reference to KiB, got %q", rhs.name)
			case:
				testing.expect(t, false, "MiB rhs should be a reference to KiB")
			}
		case:
			testing.expect(t, false, "MiB value should be a multiplication")
		}
	case:
		testing.expect(t, false, "second declaration should be a constant")
	}
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

	program, ok, err := parse(tokens, context.temp_allocator)
	testing.expectf(t, ok, "parse failed: %s", err)
	if !ok {
		return
	}

	testing.expectf(t, len(program.decls) == 1, "want 1 declaration, got %d", len(program.decls))
	if len(program.decls) != 1 {
		return
	}

	#partial switch d in program.decls[0]^ {
	case Const:
		#partial switch v in d.value^ {
		case Binary:
			// Root is `+`: lhs=1, rhs=(2 * 3).
			testing.expectf(t, v.operator == .Add, "want root Add, got %v", v.operator)
			#partial switch lhs in v.lhs^ {
			case Number:
				testing.expectf(t, lhs.value == "1", "want lhs 1, got %q", lhs.value)
			case:
				testing.expect(t, false, "root lhs should be 1")
			}
			#partial switch rhs in v.rhs^ {
			case Binary:
				testing.expectf(t, rhs.operator == .Multiply, "want rhs Multiply, got %v", rhs.operator)
			case:
				testing.expect(t, false, "root rhs should be the 2 * 3 multiplication")
			}
		case:
			testing.expect(t, false, "value should be a binary expression")
		}
	case:
		testing.expect(t, false, "declaration should be a constant")
	}
}

@(test)
test_parse_bracketed_const :: proc(t: ^testing.T) {
	// x :: (4 + 2) * 3 — the `(` is grouping, not a proc signature.
	// Exercises the LParen prefix arm; red until parse_prefix grows it.
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

	program, ok, err := parse(tokens, context.temp_allocator)
	testing.expectf(t, ok, "parse failed: %s", err)
	if !ok {
		return
	}

	testing.expectf(t, len(program.decls) == 1, "want 1 declaration, got %d", len(program.decls))
	if len(program.decls) != 1 {
		return
	}

	#partial switch d in program.decls[0]^ {
	case Const:
		#partial switch v in d.value^ {
		case Binary:
			// Root is `*`: lhs=(4 + 2), rhs=3. The group is one atom.
			testing.expectf(t, v.operator == .Multiply, "want root Multiply, got %v", v.operator)
			#partial switch lhs in v.lhs^ {
			case Binary:
				testing.expectf(t, lhs.operator == .Add, "want grouped Add, got %v", lhs.operator)
			case:
				testing.expect(t, false, "root lhs should be the grouped (4 + 2)")
			}
			#partial switch rhs in v.rhs^ {
			case Number:
				testing.expectf(t, rhs.value == "3", "want rhs 3, got %q", rhs.value)
			case:
				testing.expect(t, false, "root rhs should be 3")
			}
		case:
			testing.expect(t, false, "value should be a binary expression")
		}
	case:
		testing.expect(t, false, "declaration should be a constant")
	}
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

	program, ok, _ := parse(tokens, context.temp_allocator)
	testing.expectf(t, !ok, "want a parse error for a stray close paren, but parse succeeded")
	// The parser returns any partially-built program with ok=false; the
	// caller must gate on ok, so a non-nil program here is not an error.
	_ = program
}

@(test)
test_parse_unary_minus :: proc(t: ^testing.T) {
	// x :: -5 — a leading minus is a real Unary expression, not an
	// error and not a silent +5. Until the unary arm lands this is
	// the spec: Unary(Minus, Number(5)) must be produced.
	tokens := []tok.Token{
		{offset = 0, value = tok.Identifier("x")},
		{offset = 2, value = tok.SimpleToken.Colon},
		{offset = 3, value = tok.SimpleToken.Colon},
		{offset = 5, value = tok.SimpleToken.Minus},
		{offset = 6, value = tok.Number("5")},
		{offset = 7, value = tok.SimpleToken.EOF},
	}

	program, ok, err := parse(tokens, context.temp_allocator)
	testing.expectf(t, ok, "parse failed: %s", err)
	if !ok {
		return
	}

	testing.expectf(t, len(program.decls) == 1, "want 1 declaration, got %d", len(program.decls))
	if len(program.decls) != 1 {
		return
	}

	#partial switch d in program.decls[0]^ {
	case Const:
		#partial switch v in d.value^ {
		case Unary:
			testing.expectf(t, v.operator == .Minus, "want unary Minus, got %v", v.operator)
			#partial switch operand in v.operand^ {
			case Number:
				testing.expectf(t, operand.value == "5", "want operand 5, got %q", operand.value)
			case:
				testing.expect(t, false, "unary operand should be a number literal")
			}
		case:
			testing.expect(t, false, "value should be a Unary expression")
		}
	case:
		testing.expect(t, false, "declaration should be a constant")
	}
}

@(test)
test_parse_unary_minus_binds_looser_than_plus :: proc(t: ^testing.T) {
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

	program, ok, err := parse(tokens, context.temp_allocator)
	testing.expectf(t, ok, "parse failed: %s", err)
	if !ok {
		return
	}

	testing.expectf(t, len(program.decls) == 1, "want 1 declaration, got %d", len(program.decls))
	if len(program.decls) != 1 {
		return
	}

	#partial switch d in program.decls[0]^ {
	case Const:
		#partial switch v in d.value^ {
		case Binary:
			// Root is `+`, so the unary grabbed only the 2.
			testing.expectf(t, v.operator == .Add, "want root Add, got %v", v.operator)
			#partial switch lhs in v.lhs^ {
			case Unary:
				testing.expectf(t, lhs.operator == .Minus, "want lhs unary Minus, got %v", lhs.operator)
			case:
				testing.expect(t, false, "root lhs should be the Unary(-2)")
			}
		case:
			testing.expect(t, false, "value should be a binary expression")
		}
	case:
		testing.expect(t, false, "declaration should be a constant")
	}
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

	program, ok, err := parse(tokens, context.temp_allocator)
	testing.expectf(t, ok, "parse failed: %s", err)
	if !ok {
		return
	}

	testing.expectf(t, len(program.decls) == 1, "want 1 declaration, got %d", len(program.decls))
	if len(program.decls) != 1 {
		return
	}

	#partial switch d in program.decls[0]^ {
	case Const:
		#partial switch v in d.value^ {
		case Unary:
			testing.expectf(t, v.operator == .Minus, "want outer unary Minus, got %v", v.operator)
			#partial switch inner in v.operand^ {
			case Unary:
				testing.expectf(t, inner.operator == .Minus, "want inner unary Minus, got %v", inner.operator)
				#partial switch num in inner.operand^ {
				case Number:
					testing.expectf(t, num.value == "5", "want innermost 5, got %q", num.value)
				case:
					testing.expect(t, false, "innermost should be the number 5")
				}
			case:
				testing.expect(t, false, "outer operand should be another Unary")
			}
		case:
			testing.expect(t, false, "value should be a Unary expression")
		}
	case:
		testing.expect(t, false, "declaration should be a constant")
	}
}

@(test)
test_parse_unary_minus_binds_tighter_than_star :: proc(t: ^testing.T) {
	// x :: -2 * 3 must group as (-2) * 3, not -(2 * 3). The unary
	// operand binds at power 21, strictly above `*`'s left strength 20.
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

	program, ok, err := parse(tokens, context.temp_allocator)
	testing.expectf(t, ok, "parse failed: %s", err)
	if !ok {
		return
	}

	testing.expectf(t, len(program.decls) == 1, "want 1 declaration, got %d", len(program.decls))
	if len(program.decls) != 1 {
		return
	}

	#partial switch d in program.decls[0]^ {
	case Const:
		#partial switch v in d.value^ {
		case Binary:
			// Root is `*`, so the unary bound first: lhs = Unary(-2).
			testing.expectf(t, v.operator == .Multiply, "want root Multiply, got %v", v.operator)
			#partial switch lhs in v.lhs^ {
			case Unary:
				testing.expectf(t, lhs.operator == .Minus, "want lhs unary Minus, got %v", lhs.operator)
				#partial switch operand in lhs.operand^ {
				case Number:
					testing.expectf(t, operand.value == "2", "want unary operand 2, got %q", operand.value)
				case:
					testing.expect(t, false, "unary operand should be 2")
				}
			case:
				testing.expect(t, false, "root lhs should be the Unary(-2)")
			}
		case:
			testing.expect(t, false, "value should be a multiplication")
		}
	case:
		testing.expect(t, false, "declaration should be a constant")
	}
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

	program, ok, _ := parse(tokens, context.temp_allocator)
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

	program, ok, _ := parse(tokens, context.temp_allocator)
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

	program, ok, _ := parse(tokens, context.temp_allocator)
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

	program, ok, _ := parse(tokens, context.temp_allocator)
	testing.expectf(t, !ok, "want a parse error for a missing `::`, but parse succeeded")
	_ = program
}
