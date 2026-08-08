package main

import "core:testing"

TestCase :: struct {
	src:          string,
	expected:     []Token,
	expect_error: bool,
}

@(test)
test_lex :: proc(t: ^testing.T) {
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
				Token{offset = 0, value = Identifier("a")},
				Token{offset = 2, value = SimpleToken.EOF},
			},
		},
		{
			src = "foo",
			expected = []Token{
				Token{offset = 0, value = Identifier("foo")},
				Token{offset = 3, value = SimpleToken.EOF},
			},
		},
		{
			src = "a\r\nb",
			expected = []Token{
				Token{offset = 0, value = Identifier("a")},
				Token{offset = 2, value = SimpleToken.NewLine},
				Token{offset = 3, value = Identifier("b")},
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
			src = "::",
			expected = []Token{
				Token{offset = 0, value = SimpleToken.Colon},
				Token{offset = 1, value = SimpleToken.Colon},
				Token{offset = 2, value = SimpleToken.EOF},
			},
		},
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
			src = "\n",
			expected = []Token{
				Token{offset = 0, value = SimpleToken.NewLine},
				Token{offset = 1, value = SimpleToken.EOF},
			},
		},
		{
			src = "a,b",
			expected = []Token{
				Token{offset = 0, value = Identifier("a")},
				Token{offset = 1, value = SimpleToken.Comma},
				Token{offset = 2, value = Identifier("b")},
				Token{offset = 3, value = SimpleToken.EOF},
			},
		},
		{
			src = "\"abc",
			expected = []Token{
				Token{offset = 0, value = StringLiteral("abc")},
				Token{offset = 4, value = SimpleToken.EOF},
			},
			expect_error = true,
		},
		{
			src = "\"abc\"",
			expected = []Token{
				Token{offset = 0, value = StringLiteral("abc")},
				Token{offset = 5, value = SimpleToken.EOF},
			},
		},
		{
			src = "\"a\\\"b\"",
			expected = []Token{
				Token{offset = 0, value = StringLiteral("a\\\"b")},
				Token{offset = 6, value = SimpleToken.EOF},
			},
		},
		{
			src = "\"a\\\\b\"",
			expected = []Token{
				Token{offset = 0, value = StringLiteral("a\\\\b")},
				Token{offset = 6, value = SimpleToken.EOF},
			},
		},
		{
			src = "\"abc\"xyz",
			expected = []Token{
				Token{offset = 0, value = StringLiteral("abc")},
				Token{offset = 5, value = Identifier("xyz")},
				Token{offset = 8, value = SimpleToken.EOF},
			},
		},
		{
			src = "123",
			expected = []Token{
				Token{offset = 0, value = Number("123")},
				Token{offset = 3, value = SimpleToken.EOF},
			},
		},
		{
			src = "42 7",
			expected = []Token{
				Token{offset = 0, value = Number("42")},
				Token{offset = 3, value = Number("7")},
				Token{offset = 4, value = SimpleToken.EOF},
			},
		},
		{
			src = "12a",
			expected = []Token{
				Token{offset = 0, value = Number("12")},
				Token{offset = 2, value = Identifier("a")},
				Token{offset = 3, value = SimpleToken.EOF},
			},
		},
		{
			src = "abc123",
			expected = []Token{
				Token{offset = 0, value = Identifier("abc")},
				Token{offset = 3, value = Number("123")},
				Token{offset = 6, value = SimpleToken.EOF},
			},
		},
		{
			src = "3.14",
			expected = []Token{
				Token{offset = 0, value = Number("3.14")},
				Token{offset = 4, value = SimpleToken.EOF},
			},
		},
		{
			src = "12(3)",
			expected = []Token{
				Token{offset = 0, value = Number("12")},
				Token{offset = 2, value = SimpleToken.LParen},
				Token{offset = 3, value = Number("3")},
				Token{offset = 4, value = SimpleToken.RParen},
				Token{offset = 5, value = SimpleToken.EOF},
			},
		},
		{
			src = "a$b",
			expected = []Token{
				Token{offset = 0, value = Identifier("a")},
				Token{offset = 3, value = SimpleToken.EOF},
			},
			expect_error = true,
		},
		{
			src = SimpleProgram,
			expected = []Token{
				Token{offset = 0, value = SimpleToken.NewLine},
				Token{offset = 1, value = Identifier("main")},
				Token{offset = 6, value = SimpleToken.Colon},
				Token{offset = 7, value = SimpleToken.Colon},
				Token{offset = 9, value = SimpleToken.LParen},
				Token{offset = 10, value = SimpleToken.RParen},
				Token{offset = 12, value = SimpleToken.LSquirly},
				Token{offset = 13, value = SimpleToken.NewLine},
				Token{offset = 15, value = Identifier("print")},
				Token{offset = 20, value = SimpleToken.LParen},
				Token{offset = 21, value = StringLiteral("Hellope")},
				Token{offset = 30, value = SimpleToken.Comma},
				Token{offset = 32, value = Number("42")},
				Token{offset = 34, value = SimpleToken.RParen},
				Token{offset = 35, value = SimpleToken.NewLine},
				Token{offset = 36, value = SimpleToken.RSquirly},
				Token{offset = 37, value = SimpleToken.EOF},
			},
		},
	}

	for tc, i in cases {
		lexer := make_lexer(tc.src)
		tokens, ok := lex(&lexer)
		defer delete(tokens)

		testing.expectf(t, ok != tc.expect_error,
			"case %d (%q): ok=%v, want %v", i, tc.src, ok, !tc.expect_error)

		testing.expectf(t, len(tokens) == len(tc.expected),
			"case %d (%q): got %d tokens, want %d: %v",
			i, tc.src, len(tokens), len(tc.expected), tokens)

		if len(tokens) != len(tc.expected) {
			continue
		}
		for j in 0 ..< len(tokens) {
			testing.expectf(t, tokens[j] == tc.expected[j],
				"case %d (%q): token %d: got %v, want %v",
				i, tc.src, j, tokens[j], tc.expected[j])
		}
	}
}
