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
		{offset = 8, value = tok.SimpleToken.LParen},
		{offset = 9, value = tok.SimpleToken.RParen},
		{offset = 11, value = tok.SimpleToken.LSquirly},
		{offset = 12, value = tok.SimpleToken.NewLine},
		{offset = 13, value = tok.SimpleToken.RSquirly},
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
		{offset = 8, value = tok.SimpleToken.LParen},
		{offset = 9, value = tok.SimpleToken.RParen},
		{offset = 11, value = tok.SimpleToken.LSquirly},
		{offset = 12, value = tok.SimpleToken.NewLine},
		{offset = 14, value = tok.Identifier("answer")},
		{offset = 21, value = tok.SimpleToken.Equals},
		{offset = 23, value = tok.Number("40")},
		{offset = 26, value = tok.SimpleToken.Plus},
		{offset = 28, value = tok.Number("2")},
		{offset = 29, value = tok.SimpleToken.NewLine},
		{offset = 30, value = tok.SimpleToken.RSquirly},
		{offset = 31, value = tok.SimpleToken.EOF},
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
