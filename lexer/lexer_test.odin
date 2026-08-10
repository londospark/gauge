package lexer

import "core:testing"
import tok "../token"

TestCase :: struct {
	src:          string,
	expected:     []tok.Token,
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
			expected = []tok.Token{
				tok.Token{offset = 0, value = tok.SimpleToken.EOF},
			},
		},
		{
			src = "a ",
			expected = []tok.Token{
				tok.Token{offset = 0, value = tok.Identifier("a")},
				tok.Token{offset = 2, value = tok.SimpleToken.EOF},
			},
		},
		{
			src = "foo",
			expected = []tok.Token{
				tok.Token{offset = 0, value = tok.Identifier("foo")},
				tok.Token{offset = 3, value = tok.SimpleToken.EOF},
			},
		},
		{
			src = "a\r\nb",
			expected = []tok.Token{
				tok.Token{offset = 0, value = tok.Identifier("a")},
				tok.Token{offset = 2, value = tok.SimpleToken.NewLine},
				tok.Token{offset = 3, value = tok.Identifier("b")},
				tok.Token{offset = 4, value = tok.SimpleToken.EOF},
			},
		},
		{
			src = "  \t\r",
			expected = []tok.Token{
				tok.Token{offset = 4, value = tok.SimpleToken.EOF},
			},
		},
		{
			src = "\n",
			expected = []tok.Token{
				tok.Token{offset = 0, value = tok.SimpleToken.NewLine},
				tok.Token{offset = 1, value = tok.SimpleToken.EOF},
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
			expected = []tok.Token{
				tok.Token{offset = 0, value = tok.Identifier("a")},
				tok.Token{offset = 1, value = tok.SimpleToken.EOF},
			},
		},
		{
			src = "A",
			expected = []tok.Token{
				tok.Token{offset = 0, value = tok.Identifier("A")},
				tok.Token{offset = 1, value = tok.SimpleToken.EOF},
			},
		},
		{
			src = "_",
			expected = []tok.Token{
				tok.Token{offset = 0, value = tok.Identifier("_")},
				tok.Token{offset = 1, value = tok.SimpleToken.EOF},
			},
		},
		{
			src = "_a",
			expected = []tok.Token{
				tok.Token{offset = 0, value = tok.Identifier("_a")},
				tok.Token{offset = 2, value = tok.SimpleToken.EOF},
			},
		},
		// continue: letters, underscores, digits in any combination
		{
			src = "a1",
			expected = []tok.Token{
				tok.Token{offset = 0, value = tok.Identifier("a1")},
				tok.Token{offset = 2, value = tok.SimpleToken.EOF},
			},
		},
		{
			src = "a_b",
			expected = []tok.Token{
				tok.Token{offset = 0, value = tok.Identifier("a_b")},
				tok.Token{offset = 3, value = tok.SimpleToken.EOF},
			},
		},
		{
			src = "abc123",
			expected = []tok.Token{
				tok.Token{offset = 0, value = tok.Identifier("abc123")},
				tok.Token{offset = 6, value = tok.SimpleToken.EOF},
			},
		},
		{
			src = "KiB",
			expected = []tok.Token{
				tok.Token{offset = 0, value = tok.Identifier("KiB")},
				tok.Token{offset = 3, value = tok.SimpleToken.EOF},
			},
		},
		{
			src = "foo_Bar_123",
			expected = []tok.Token{
				tok.Token{offset = 0, value = tok.Identifier("foo_Bar_123")},
				tok.Token{offset = 11, value = tok.SimpleToken.EOF},
			},
		},
		// keywords are exact matches only — a longer word is a plain ident
		{
			src = "proc123",
			expected = []tok.Token{
				tok.Token{offset = 0, value = tok.Identifier("proc123")},
				tok.Token{offset = 7, value = tok.SimpleToken.EOF},
			},
		},
		{
			src = "_proc",
			expected = []tok.Token{
				tok.Token{offset = 0, value = tok.Identifier("_proc")},
				tok.Token{offset = 5, value = tok.SimpleToken.EOF},
			},
		},
		// boundaries: a digit cannot start an identifier
		{
			src = "123abc",
			expected = []tok.Token{
				tok.Token{offset = 0, value = tok.Number("123")},
				tok.Token{offset = 3, value = tok.Identifier("abc")},
				tok.Token{offset = 6, value = tok.SimpleToken.EOF},
			},
		},
		{
			src = "a 1",
			expected = []tok.Token{
				tok.Token{offset = 0, value = tok.Identifier("a")},
				tok.Token{offset = 2, value = tok.Number("1")},
				tok.Token{offset = 3, value = tok.SimpleToken.EOF},
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
			expected = []tok.Token{
				tok.Token{offset = 0, value = tok.SimpleToken.LParen},
				tok.Token{offset = 1, value = tok.SimpleToken.RParen},
				tok.Token{offset = 2, value = tok.SimpleToken.LSquirly},
				tok.Token{offset = 3, value = tok.SimpleToken.RSquirly},
				tok.Token{offset = 4, value = tok.SimpleToken.EOF},
			},
		},
		{
			src = "::",
			expected = []tok.Token{
				tok.Token{offset = 0, value = tok.SimpleToken.Colon},
				tok.Token{offset = 1, value = tok.SimpleToken.Colon},
				tok.Token{offset = 2, value = tok.SimpleToken.EOF},
			},
		},
		{
			src = "a,b",
			expected = []tok.Token{
				tok.Token{offset = 0, value = tok.Identifier("a")},
				tok.Token{offset = 1, value = tok.SimpleToken.Comma},
				tok.Token{offset = 2, value = tok.Identifier("b")},
				tok.Token{offset = 3, value = tok.SimpleToken.EOF},
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
			expected = []tok.Token{
				tok.Token{offset = 0, value = tok.Number("123")},
				tok.Token{offset = 3, value = tok.SimpleToken.EOF},
			},
		},
		{
			src = "42 7",
			expected = []tok.Token{
				tok.Token{offset = 0, value = tok.Number("42")},
				tok.Token{offset = 3, value = tok.Number("7")},
				tok.Token{offset = 4, value = tok.SimpleToken.EOF},
			},
		},
		{
			src = "12a",
			expected = []tok.Token{
				tok.Token{offset = 0, value = tok.Number("12")},
				tok.Token{offset = 2, value = tok.Identifier("a")},
				tok.Token{offset = 3, value = tok.SimpleToken.EOF},
			},
		},
		{
			src = "3.14",
			expected = []tok.Token{
				tok.Token{offset = 0, value = tok.Number("3.14")},
				tok.Token{offset = 4, value = tok.SimpleToken.EOF},
			},
		},
		{
			src = "12(3)",
			expected = []tok.Token{
				tok.Token{offset = 0, value = tok.Number("12")},
				tok.Token{offset = 2, value = tok.SimpleToken.LParen},
				tok.Token{offset = 3, value = tok.Number("3")},
				tok.Token{offset = 4, value = tok.SimpleToken.RParen},
				tok.Token{offset = 5, value = tok.SimpleToken.EOF},
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
			expected = []tok.Token{
				tok.Token{offset = 0, value = tok.StringLiteral("abc")},
				tok.Token{offset = 5, value = tok.SimpleToken.EOF},
			},
		},
		{
			src = "\"a\\\"b\"",
			expected = []tok.Token{
				tok.Token{offset = 0, value = tok.StringLiteral("a\\\"b")},
				tok.Token{offset = 6, value = tok.SimpleToken.EOF},
			},
		},
		{
			src = "\"a\\\\b\"",
			expected = []tok.Token{
				tok.Token{offset = 0, value = tok.StringLiteral("a\\\\b")},
				tok.Token{offset = 6, value = tok.SimpleToken.EOF},
			},
		},
		{
			src = "\"abc\"xyz",
			expected = []tok.Token{
				tok.Token{offset = 0, value = tok.StringLiteral("abc")},
				tok.Token{offset = 5, value = tok.Identifier("xyz")},
				tok.Token{offset = 8, value = tok.SimpleToken.EOF},
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
			expected = []tok.Token{
				tok.Token{offset = 0, value = tok.SimpleToken.Equals},
				tok.Token{offset = 1, value = tok.SimpleToken.EOF},
			},
		},
		{
			src = "+=",
			expected = []tok.Token{
				tok.Token{offset = 0, value = tok.SimpleToken.Plus},
				tok.Token{offset = 1, value = tok.SimpleToken.Equals},
				tok.Token{offset = 2, value = tok.SimpleToken.EOF},
			},
		},
		{
			src = "a-b",
			expected = []tok.Token{
				tok.Token{offset = 0, value = tok.Identifier("a")},
				tok.Token{offset = 1, value = tok.SimpleToken.Minus},
				tok.Token{offset = 2, value = tok.Identifier("b")},
				tok.Token{offset = 3, value = tok.SimpleToken.EOF},
			},
		},
		{
			src = "a*b",
			expected = []tok.Token{
				tok.Token{offset = 0, value = tok.Identifier("a")},
				tok.Token{offset = 1, value = tok.SimpleToken.Star},
				tok.Token{offset = 2, value = tok.Identifier("b")},
				tok.Token{offset = 3, value = tok.SimpleToken.EOF},
			},
		},
		{
			src = "a/b",
			expected = []tok.Token{
				tok.Token{offset = 0, value = tok.Identifier("a")},
				tok.Token{offset = 1, value = tok.SimpleToken.Slash},
				tok.Token{offset = 2, value = tok.Identifier("b")},
				tok.Token{offset = 3, value = tok.SimpleToken.EOF},
			},
		},
		{
			src = "a^b",
			expected = []tok.Token{
				tok.Token{offset = 0, value = tok.Identifier("a")},
				tok.Token{offset = 1, value = tok.SimpleToken.Hat},
				tok.Token{offset = 2, value = tok.Identifier("b")},
				tok.Token{offset = 3, value = tok.SimpleToken.EOF},
			},
		},
		{
			src = "x = 5",
			expected = []tok.Token{
				tok.Token{offset = 0, value = tok.Identifier("x")},
				tok.Token{offset = 2, value = tok.SimpleToken.Equals},
				tok.Token{offset = 4, value = tok.Number("5")},
				tok.Token{offset = 5, value = tok.SimpleToken.EOF},
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
			expected = []tok.Token{
				tok.Token{offset = 0, value = tok.Keyword.Proc},
				tok.Token{offset = 4, value = tok.SimpleToken.EOF},
			},
		},
		{
			// "procedure" is not the keyword — the match must be exact,
			// not a prefix match.
			src = "procedure",
			expected = []tok.Token{
				tok.Token{offset = 0, value = tok.Identifier("procedure")},
				tok.Token{offset = 9, value = tok.SimpleToken.EOF},
			},
		},
		{
			src = "x proc",
			expected = []tok.Token{
				tok.Token{offset = 0, value = tok.Identifier("x")},
				tok.Token{offset = 2, value = tok.Keyword.Proc},
				tok.Token{offset = 6, value = tok.SimpleToken.EOF},
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
			expected = []tok.Token{
				tok.Token{offset = 0, value = tok.StringLiteral("abc")},
				tok.Token{offset = 4, value = tok.SimpleToken.EOF},
			},
			expect_error = true,
		},
		{
			src = "a$b",
			expected = []tok.Token{
				tok.Token{offset = 0, value = tok.Identifier("a")},
				tok.Token{offset = 3, value = tok.SimpleToken.EOF},
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
			expected = []tok.Token{
				tok.Token{offset = 8, value = tok.SimpleToken.EOF},
			},
		},
		{
			src = "a // c\nb",
			expected = []tok.Token{
				tok.Token{offset = 0, value = tok.Identifier("a")},
				tok.Token{offset = 6, value = tok.SimpleToken.NewLine},
				tok.Token{offset = 7, value = tok.Identifier("b")},
				tok.Token{offset = 8, value = tok.SimpleToken.EOF},
			},
		},
		{
			src = "a // c",
			expected = []tok.Token{
				tok.Token{offset = 0, value = tok.Identifier("a")},
				tok.Token{offset = 6, value = tok.SimpleToken.EOF},
			},
		},
		{
			src = "a / b",
			expected = []tok.Token{
				tok.Token{offset = 0, value = tok.Identifier("a")},
				tok.Token{offset = 2, value = tok.SimpleToken.Slash},
				tok.Token{offset = 4, value = tok.Identifier("b")},
				tok.Token{offset = 5, value = tok.SimpleToken.EOF},
			},
		},
		{
			src = "//\n",
			expected = []tok.Token{
				tok.Token{offset = 2, value = tok.SimpleToken.NewLine},
				tok.Token{offset = 3, value = tok.SimpleToken.EOF},
			},
		},
		{
			src = "x = 1 // comment\ny = 2",
			expected = []tok.Token{
				tok.Token{offset = 0, value = tok.Identifier("x")},
				tok.Token{offset = 2, value = tok.SimpleToken.Equals},
				tok.Token{offset = 4, value = tok.Number("1")},
				tok.Token{offset = 16, value = tok.SimpleToken.NewLine},
				tok.Token{offset = 17, value = tok.Identifier("y")},
				tok.Token{offset = 19, value = tok.SimpleToken.Equals},
				tok.Token{offset = 21, value = tok.Number("2")},
				tok.Token{offset = 22, value = tok.SimpleToken.EOF},
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
			expected = []tok.Token{
				tok.Token{offset = 0, value = tok.SimpleToken.NewLine},
				tok.Token{offset = 1, value = tok.Identifier("main")},
				tok.Token{offset = 6, value = tok.SimpleToken.Colon},
				tok.Token{offset = 7, value = tok.SimpleToken.Colon},
				tok.Token{offset = 9, value = tok.SimpleToken.LParen},
				tok.Token{offset = 10, value = tok.SimpleToken.RParen},
				tok.Token{offset = 12, value = tok.SimpleToken.LSquirly},
				tok.Token{offset = 13, value = tok.SimpleToken.NewLine},
				tok.Token{offset = 15, value = tok.Identifier("answer")},
				tok.Token{offset = 22, value = tok.SimpleToken.Equals},
				tok.Token{offset = 24, value = tok.Number("40")},
				tok.Token{offset = 27, value = tok.SimpleToken.Plus},
				tok.Token{offset = 29, value = tok.Number("2")},
				tok.Token{offset = 30, value = tok.SimpleToken.NewLine},
				tok.Token{offset = 32, value = tok.Identifier("print")},
				tok.Token{offset = 37, value = tok.SimpleToken.LParen},
				tok.Token{offset = 38, value = tok.Identifier("answer")},
				tok.Token{offset = 44, value = tok.SimpleToken.RParen},
				tok.Token{offset = 45, value = tok.SimpleToken.NewLine},
				tok.Token{offset = 46, value = tok.SimpleToken.RSquirly},
				tok.Token{offset = 47, value = tok.SimpleToken.EOF},
			},
		},
	}

	for tc, i in cases {
		check_case(t, tc, i)
	}
}
