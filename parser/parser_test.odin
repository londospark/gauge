package parser

import "core:testing"
import "../lexer"

@(test)
test_parse_const_number :: proc(t: ^testing.T) {
	tokens := []lexer.Token{
		{offset = 0, value = lexer.Identifier("x")},
		{offset = 2, value = lexer.SimpleToken.Colon},
		{offset = 3, value = lexer.SimpleToken.Colon},
		{offset = 5, value = lexer.Number("42")},
		{offset = 7, value = lexer.SimpleToken.EOF},
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
	tokens := []lexer.Token{
		{offset = 0, value = lexer.Identifier("greeting")},
		{offset = 9, value = lexer.SimpleToken.Colon},
		{offset = 10, value = lexer.SimpleToken.Colon},
		{offset = 12, value = lexer.StringLiteral("hellope")},
		{offset = 20, value = lexer.SimpleToken.EOF},
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
	tokens := []lexer.Token{
		{offset = 0, value = lexer.Identifier("main")},
		{offset = 5, value = lexer.SimpleToken.Colon},
		{offset = 6, value = lexer.SimpleToken.Colon},
		{offset = 8, value = lexer.SimpleToken.LParen},
		{offset = 9, value = lexer.SimpleToken.RParen},
		{offset = 11, value = lexer.SimpleToken.LSquirly},
		{offset = 12, value = lexer.SimpleToken.NewLine},
		{offset = 13, value = lexer.SimpleToken.RSquirly},
		{offset = 14, value = lexer.SimpleToken.EOF},
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
	tokens := []lexer.Token{
		{offset = 0, value = lexer.Identifier("main")},
		{offset = 5, value = lexer.SimpleToken.Colon},
		{offset = 6, value = lexer.SimpleToken.Colon},
		{offset = 8, value = lexer.SimpleToken.LParen},
		{offset = 9, value = lexer.SimpleToken.RParen},
		{offset = 11, value = lexer.SimpleToken.LSquirly},
		{offset = 12, value = lexer.SimpleToken.NewLine},
		{offset = 14, value = lexer.Identifier("answer")},
		{offset = 21, value = lexer.SimpleToken.Equals},
		{offset = 23, value = lexer.Number("40")},
		{offset = 26, value = lexer.SimpleToken.Plus},
		{offset = 28, value = lexer.Number("2")},
		{offset = 29, value = lexer.SimpleToken.NewLine},
		{offset = 30, value = lexer.SimpleToken.RSquirly},
		{offset = 31, value = lexer.SimpleToken.EOF},
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
