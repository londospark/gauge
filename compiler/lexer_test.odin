package compiler

import "core:testing"

TestCase :: struct {
	src:          string,
	expected:     []Token,
	expect_error: bool,
}

TestProgram :: `
main :: () {
	answer = 40 + 2
	print(answer)
}`

check_case :: proc(t: ^testing.T, tc: TestCase, i: int) {
	lexer := make_lexer(tc.src)
	tokens, ok := lex(&lexer)
	defer delete(tokens)

	testing.expectf(t, ok != tc.expect_error,
		"case %d (%q): ok=%v, want %v", i, tc.src, ok, !tc.expect_error)

	testing.expectf(t, len(tokens) == len(tc.expected),
		"case %d (%q): got %d tokens, want %d: %v",
		i, tc.src, len(tokens), len(tc.expected), tokens)

	if len(tokens) != len(tc.expected) {
		return
	}
	for j in 0 ..< len(tokens) {
		testing.expectf(t, tokens[j] == tc.expected[j],
			"case %d (%q): token %d: got %v, want %v",
			i, tc.src, j, tokens[j], tc.expected[j])
	}
}

@(test)
test_lex_basics :: proc(t: ^testing.T) {
	cases := []TestCase{
		{
			src = "",
			expected = []Token{
				Token{offset = 0, value = SimpleToken.EOF},
			},
		},
		{
			src = "a ",
			expected = []Token{
				Token{offset = 0, value = IdentifierToken("a")},
				Token{offset = 2, value = SimpleToken.EOF},
			},
		},
		{
			src = "foo",
			expected = []Token{
				Token{offset = 0, value = IdentifierToken("foo")},
				Token{offset = 3, value = SimpleToken.EOF},
			},
		},
		{
			src = "a\r\nb",
			expected = []Token{
				Token{offset = 0, value = IdentifierToken("a")},
				Token{offset = 2, value = SimpleToken.NewLine},
				Token{offset = 3, value = IdentifierToken("b")},
				Token{offset = 4, value = SimpleToken.EOF},
			},
		},
		{
			src = "  \t\r",
			expected = []Token{
				Token{offset = 4, value = SimpleToken.EOF},
			},
		},
		{
			src = "\n",
			expected = []Token{
				Token{offset = 0, value = SimpleToken.NewLine},
				Token{offset = 1, value = SimpleToken.EOF},
			},
		},
	}

	for tc, i in cases {
		check_case(t, tc, i)
	}
}

@(test)
test_lex_identifiers :: proc(t: ^testing.T) {
	// Identifier rule: starts with a letter or underscore, then continues
	// with letters, underscores, and digits. A digit can never start one.
	cases := []TestCase{
		// start: lowercase, uppercase, underscore
		{
			src = "a",
			expected = []Token{
				Token{offset = 0, value = IdentifierToken("a")},
				Token{offset = 1, value = SimpleToken.EOF},
			},
		},
		{
			src = "A",
			expected = []Token{
				Token{offset = 0, value = IdentifierToken("A")},
				Token{offset = 1, value = SimpleToken.EOF},
			},
		},
		{
			src = "_",
			expected = []Token{
				Token{offset = 0, value = IdentifierToken("_")},
				Token{offset = 1, value = SimpleToken.EOF},
			},
		},
		{
			src = "_a",
			expected = []Token{
				Token{offset = 0, value = IdentifierToken("_a")},
				Token{offset = 2, value = SimpleToken.EOF},
			},
		},
		// continue: letters, underscores, digits in any combination
		{
			src = "a1",
			expected = []Token{
				Token{offset = 0, value = IdentifierToken("a1")},
				Token{offset = 2, value = SimpleToken.EOF},
			},
		},
		{
			src = "a_b",
			expected = []Token{
				Token{offset = 0, value = IdentifierToken("a_b")},
				Token{offset = 3, value = SimpleToken.EOF},
			},
		},
		{
			src = "abc123",
			expected = []Token{
				Token{offset = 0, value = IdentifierToken("abc123")},
				Token{offset = 6, value = SimpleToken.EOF},
			},
		},
		{
			src = "KiB",
			expected = []Token{
				Token{offset = 0, value = IdentifierToken("KiB")},
				Token{offset = 3, value = SimpleToken.EOF},
			},
		},
		{
			src = "foo_Bar_123",
			expected = []Token{
				Token{offset = 0, value = IdentifierToken("foo_Bar_123")},
				Token{offset = 11, value = SimpleToken.EOF},
			},
		},
		// keywords are exact matches only — a longer word is a plain ident
		{
			src = "proc123",
			expected = []Token{
				Token{offset = 0, value = IdentifierToken("proc123")},
				Token{offset = 7, value = SimpleToken.EOF},
			},
		},
		{
			src = "_proc",
			expected = []Token{
				Token{offset = 0, value = IdentifierToken("_proc")},
				Token{offset = 5, value = SimpleToken.EOF},
			},
		},
		// boundaries: a digit cannot start an identifier
		{
			src = "123abc",
			expected = []Token{
				Token{offset = 0, value = NumberToken("123")},
				Token{offset = 3, value = IdentifierToken("abc")},
				Token{offset = 6, value = SimpleToken.EOF},
			},
		},
		{
			src = "a 1",
			expected = []Token{
				Token{offset = 0, value = IdentifierToken("a")},
				Token{offset = 2, value = NumberToken("1")},
				Token{offset = 3, value = SimpleToken.EOF},
			},
		},
	}

	for tc, i in cases {
		check_case(t, tc, i)
	}
}

@(test)
test_lex_symbols :: proc(t: ^testing.T) {
	cases := []TestCase{
		{
			src = "(){}",
			expected = []Token{
				Token{offset = 0, value = SimpleToken.LParen},
				Token{offset = 1, value = SimpleToken.RParen},
				Token{offset = 2, value = SimpleToken.LSquirly},
				Token{offset = 3, value = SimpleToken.RSquirly},
				Token{offset = 4, value = SimpleToken.EOF},
			},
		},
		{
			src = "::",
			expected = []Token{
				Token{offset = 0, value = SimpleToken.Colon},
				Token{offset = 1, value = SimpleToken.Colon},
				Token{offset = 2, value = SimpleToken.EOF},
			},
		},
		{
			src = "a,b",
			expected = []Token{
				Token{offset = 0, value = IdentifierToken("a")},
				Token{offset = 1, value = SimpleToken.Comma},
				Token{offset = 2, value = IdentifierToken("b")},
				Token{offset = 3, value = SimpleToken.EOF},
			},
		},
	}

	for tc, i in cases {
		check_case(t, tc, i)
	}
}

@(test)
test_lex_numbers :: proc(t: ^testing.T) {
	cases := []TestCase{
		{
			src = "123",
			expected = []Token{
				Token{offset = 0, value = NumberToken("123")},
				Token{offset = 3, value = SimpleToken.EOF},
			},
		},
		{
			src = "42 7",
			expected = []Token{
				Token{offset = 0, value = NumberToken("42")},
				Token{offset = 3, value = NumberToken("7")},
				Token{offset = 4, value = SimpleToken.EOF},
			},
		},
		{
			src = "12a",
			expected = []Token{
				Token{offset = 0, value = NumberToken("12")},
				Token{offset = 2, value = IdentifierToken("a")},
				Token{offset = 3, value = SimpleToken.EOF},
			},
		},
		{
			src = "3.14",
			expected = []Token{
				Token{offset = 0, value = NumberToken("3.14")},
				Token{offset = 4, value = SimpleToken.EOF},
			},
		},
		{
			src = "12(3)",
			expected = []Token{
				Token{offset = 0, value = NumberToken("12")},
				Token{offset = 2, value = SimpleToken.LParen},
				Token{offset = 3, value = NumberToken("3")},
				Token{offset = 4, value = SimpleToken.RParen},
				Token{offset = 5, value = SimpleToken.EOF},
			},
		},
	}

	for tc, i in cases {
		check_case(t, tc, i)
	}
}

@(test)
test_lex_strings :: proc(t: ^testing.T) {
	cases := []TestCase{
		{
			src = "\"abc\"",
			expected = []Token{
				Token{offset = 0, value = StringLiteralToken("abc")},
				Token{offset = 5, value = SimpleToken.EOF},
			},
		},
		{
			src = "\"a\\\"b\"",
			expected = []Token{
				Token{offset = 0, value = StringLiteralToken("a\\\"b")},
				Token{offset = 6, value = SimpleToken.EOF},
			},
		},
		{
			src = "\"a\\\\b\"",
			expected = []Token{
				Token{offset = 0, value = StringLiteralToken("a\\\\b")},
				Token{offset = 6, value = SimpleToken.EOF},
			},
		},
		{
			src = "\"abc\"xyz",
			expected = []Token{
				Token{offset = 0, value = StringLiteralToken("abc")},
				Token{offset = 5, value = IdentifierToken("xyz")},
				Token{offset = 8, value = SimpleToken.EOF},
			},
		},
	}

	for tc, i in cases {
		check_case(t, tc, i)
	}
}

@(test)
test_lex_operators :: proc(t: ^testing.T) {
	cases := []TestCase{
		{
			src = "=",
			expected = []Token{
				Token{offset = 0, value = SimpleToken.Equals},
				Token{offset = 1, value = SimpleToken.EOF},
			},
		},
		{
			src = "+=",
			expected = []Token{
				Token{offset = 0, value = SimpleToken.Plus},
				Token{offset = 1, value = SimpleToken.Equals},
				Token{offset = 2, value = SimpleToken.EOF},
			},
		},
		{
			src = "a-b",
			expected = []Token{
				Token{offset = 0, value = IdentifierToken("a")},
				Token{offset = 1, value = SimpleToken.Minus},
				Token{offset = 2, value = IdentifierToken("b")},
				Token{offset = 3, value = SimpleToken.EOF},
			},
		},
		{
			src = "a*b",
			expected = []Token{
				Token{offset = 0, value = IdentifierToken("a")},
				Token{offset = 1, value = SimpleToken.Star},
				Token{offset = 2, value = IdentifierToken("b")},
				Token{offset = 3, value = SimpleToken.EOF},
			},
		},
		{
			src = "a/b",
			expected = []Token{
				Token{offset = 0, value = IdentifierToken("a")},
				Token{offset = 1, value = SimpleToken.Slash},
				Token{offset = 2, value = IdentifierToken("b")},
				Token{offset = 3, value = SimpleToken.EOF},
			},
		},
		{
			src = "a^b",
			expected = []Token{
				Token{offset = 0, value = IdentifierToken("a")},
				Token{offset = 1, value = SimpleToken.Hat},
				Token{offset = 2, value = IdentifierToken("b")},
				Token{offset = 3, value = SimpleToken.EOF},
			},
		},
		{
			src = "x = 5",
			expected = []Token{
				Token{offset = 0, value = IdentifierToken("x")},
				Token{offset = 2, value = SimpleToken.Equals},
				Token{offset = 4, value = NumberToken("5")},
				Token{offset = 5, value = SimpleToken.EOF},
			},
		},
	}

	for tc, i in cases {
		check_case(t, tc, i)
	}
}

@(test)
test_lex_keywords :: proc(t: ^testing.T) {
	cases := []TestCase{
		{
			src = "proc",
			expected = []Token{
				Token{offset = 0, value = KeywordToken.Proc},
				Token{offset = 4, value = SimpleToken.EOF},
			},
		},
		{
			// "procedure" is not the keyword — the match must be exact,
			// not a prefix match.
			src = "procedure",
			expected = []Token{
				Token{offset = 0, value = IdentifierToken("procedure")},
				Token{offset = 9, value = SimpleToken.EOF},
			},
		},
		{
			src = "x proc",
			expected = []Token{
				Token{offset = 0, value = IdentifierToken("x")},
				Token{offset = 2, value = KeywordToken.Proc},
				Token{offset = 6, value = SimpleToken.EOF},
			},
		},
	}

	for tc, i in cases {
		check_case(t, tc, i)
	}
}

@(test)
test_lex_errors :: proc(t: ^testing.T) {
	cases := []TestCase{
		{
			src = "\"abc",
			expected = []Token{
				Token{offset = 0, value = StringLiteralToken("abc")},
				Token{offset = 4, value = SimpleToken.EOF},
			},
			expect_error = true,
		},
		{
			src = "a$b",
			expected = []Token{
				Token{offset = 0, value = IdentifierToken("a")},
				Token{offset = 3, value = SimpleToken.EOF},
			},
			expect_error = true,
		},
	}

	for tc, i in cases {
		check_case(t, tc, i)
	}
}

@(test)
test_lex_comments :: proc(t: ^testing.T) {
	cases := []TestCase{
		{
			src = "// hello",
			expected = []Token{
				Token{offset = 8, value = SimpleToken.EOF},
			},
		},
		{
			src = "a // c\nb",
			expected = []Token{
				Token{offset = 0, value = IdentifierToken("a")},
				Token{offset = 6, value = SimpleToken.NewLine},
				Token{offset = 7, value = IdentifierToken("b")},
				Token{offset = 8, value = SimpleToken.EOF},
			},
		},
		{
			src = "a // c",
			expected = []Token{
				Token{offset = 0, value = IdentifierToken("a")},
				Token{offset = 6, value = SimpleToken.EOF},
			},
		},
		{
			src = "a / b",
			expected = []Token{
				Token{offset = 0, value = IdentifierToken("a")},
				Token{offset = 2, value = SimpleToken.Slash},
				Token{offset = 4, value = IdentifierToken("b")},
				Token{offset = 5, value = SimpleToken.EOF},
			},
		},
		{
			src = "//\n",
			expected = []Token{
				Token{offset = 2, value = SimpleToken.NewLine},
				Token{offset = 3, value = SimpleToken.EOF},
			},
		},
		{
			src = "x = 1 // comment\ny = 2",
			expected = []Token{
				Token{offset = 0, value = IdentifierToken("x")},
				Token{offset = 2, value = SimpleToken.Equals},
				Token{offset = 4, value = NumberToken("1")},
				Token{offset = 16, value = SimpleToken.NewLine},
				Token{offset = 17, value = IdentifierToken("y")},
				Token{offset = 19, value = SimpleToken.Equals},
				Token{offset = 21, value = NumberToken("2")},
				Token{offset = 22, value = SimpleToken.EOF},
			},
		},
	}

	for tc, i in cases {
		check_case(t, tc, i)
	}
}

@(test)
test_lex_program :: proc(t: ^testing.T) {
	cases := []TestCase{
		{
			src = TestProgram,
			expected = []Token{
				Token{offset = 0, value = SimpleToken.NewLine},
				Token{offset = 1, value = IdentifierToken("main")},
				Token{offset = 6, value = SimpleToken.Colon},
				Token{offset = 7, value = SimpleToken.Colon},
				Token{offset = 9, value = SimpleToken.LParen},
				Token{offset = 10, value = SimpleToken.RParen},
				Token{offset = 12, value = SimpleToken.LSquirly},
				Token{offset = 13, value = SimpleToken.NewLine},
				Token{offset = 15, value = IdentifierToken("answer")},
				Token{offset = 22, value = SimpleToken.Equals},
				Token{offset = 24, value = NumberToken("40")},
				Token{offset = 27, value = SimpleToken.Plus},
				Token{offset = 29, value = NumberToken("2")},
				Token{offset = 30, value = SimpleToken.NewLine},
				Token{offset = 32, value = IdentifierToken("print")},
				Token{offset = 37, value = SimpleToken.LParen},
				Token{offset = 38, value = IdentifierToken("answer")},
				Token{offset = 44, value = SimpleToken.RParen},
				Token{offset = 45, value = SimpleToken.NewLine},
				Token{offset = 46, value = SimpleToken.RSquirly},
				Token{offset = 47, value = SimpleToken.EOF},
			},
		},
	}

	for tc, i in cases {
		check_case(t, tc, i)
	}
}
