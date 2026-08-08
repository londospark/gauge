package main

import "core:testing"

TestCase :: struct {
	src:      string,
	expected: []Token,
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
			src = "\"abc",
			expected = []Token{
				Token{offset = 1, value = StringLiteral("abc")},
				Token{offset = 4, value = SimpleToken.EOF},
			},
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
				Token{offset = 22, value = StringLiteral("Hellope")},
				Token{offset = 30, value = SimpleToken.RParen},
				Token{offset = 31, value = SimpleToken.NewLine},
				Token{offset = 32, value = SimpleToken.RSquirly},
				Token{offset = 33, value = SimpleToken.NewLine},
				Token{offset = 34, value = SimpleToken.EOF},
			},
		},
	}

	for tc, i in cases {
		lexer := make_lexer(tc.src)
		tokens := lex(&lexer)
		defer delete(tokens)

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
