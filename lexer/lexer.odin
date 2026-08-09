package lexer

import "core:fmt"
import tok "../token"

Lexer :: struct {
	source:   string,
	position: int,
	err:      string,
}

make_lexer :: proc(input: string) -> Lexer {
	return Lexer { source = input, position = 0 }
}

lex :: proc(lexer: ^Lexer, allocator := context.allocator) -> (tokens: [dynamic]tok.Token, ok: bool) {
	result := make([dynamic]tok.Token, allocator)
	ok = true

	lexing: for lexer.position < len(lexer.source) {
		eat_whitespace(lexer)

		if lexer.position >= len(lexer.source) {
			break lexing
		}

		switch lexer.source[lexer.position] {
		case ':':  append(&result, lex_single(lexer, .Colon))
		case '(':  append(&result, lex_single(lexer, .LParen))
		case ')':  append(&result, lex_single(lexer, .RParen))
		case '{':  append(&result, lex_single(lexer, .LSquirly))
		case '}':  append(&result, lex_single(lexer, .RSquirly))
		case ',':  append(&result, lex_single(lexer, .Comma))
		case '=':  append(&result, lex_single(lexer, .Equals))
		case '+':  append(&result, lex_single(lexer, .Plus))
		case '-':  append(&result, lex_single(lexer, .Minus))
		case '*':  append(&result, lex_single(lexer, .Star))
		case '/':
			if next, ok := peek_at(lexer, 1); ok && next == '/' {
				skip_line_comment(lexer)
			} else {
				append(&result, lex_single(lexer, .Slash))
			}
		case '^':  append(&result, lex_single(lexer, .Hat))
		case '\n': append(&result, lex_single(lexer, .NewLine))
		case 'a'..='z':
			token, _ := lex_identifier(lexer)
			append(&result, token)
		case '0'..='9':
			token, _ := lex_number(lexer)
			append(&result, token)
		case '"':
			token, token_ok := lex_string(lexer)
			append(&result, token)
			if !token_ok {
				lexer.err = fmt.tprintf("Unterminated string at byte %d", token.offset)
				ok = false
				break lexing
			}
		case:
			lexer.err = fmt.tprintf("Unrecognised character at byte %d", lexer.position)
			ok = false
			break lexing
		}
	}

	append(&result, tok.Token { offset = len(lexer.source), value = .EOF })

	return result, ok
}

lex_single :: proc(lexer: ^Lexer, token_kind: tok.SimpleToken) -> tok.Token {
	token := tok.Token { offset = lexer.position, value = token_kind }
	advance(lexer)
	return token
}

peek :: proc(lexer: ^Lexer) -> (u8, bool) {
	if lexer.position >= len(lexer.source) do return 0, false
	return lexer.source[lexer.position], true
}

advance :: proc(lexer: ^Lexer) -> (u8, bool) {
	if lexer.position >= len(lexer.source) do return 0, false
	ch := lexer.source[lexer.position]
	lexer.position += 1
	return ch, true
}

peek_at :: proc(lexer: ^Lexer, ahead: int) -> (u8, bool) {
	pos := lexer.position + ahead
	if pos >= len(lexer.source) do return 0, false
	return lexer.source[pos], true
}

lex_identifier :: proc(lexer: ^Lexer) -> (tok.Token, bool) {
	start := lexer.position
	for {
		c, ok := peek(lexer)
		if !ok || !is_lowercase(c) do break
		advance(lexer)
	}
	return tok.Token { offset = start, value = tok.Identifier(lexer.source[start:lexer.position]) }, start != lexer.position
}

lex_string :: proc(lexer: ^Lexer) -> (tok.Token, bool) {
	token_start := lexer.position
	advance(lexer)
	start := lexer.position

	for {
		c, ok := peek(lexer)
		if !ok do break
		if c == '"' do break
		if c == '\\' {
			advance(lexer)
			if _, ok := peek(lexer); ok {
				advance(lexer)
			}
		} else {
			advance(lexer)
		}
	}
	c, ok := peek(lexer)
	terminated := ok && c == '"'
	end := lexer.position

	advance(lexer)

	return tok.Token { offset = token_start, value = tok.StringLiteral(lexer.source[start:end]) }, terminated
}

lex_number :: proc(lexer: ^Lexer) -> (tok.Token, bool) {
	start := lexer.position

	for {
		c, ok := peek(lexer)
		if !ok || !is_digit(c) do break
		advance(lexer)
	}

	maybe_dot, ok := peek(lexer)

	if ok && maybe_dot == '.' {
		advance(lexer)

		for {
			c, ok := peek(lexer)
			if !ok || !is_digit(c) do break
			advance(lexer)
		}
	}

	return tok.Token { offset = start, value = tok.Number(lexer.source[start:lexer.position]) }, start != lexer.position
}

skip_line_comment :: proc(lexer: ^Lexer) {
	for {
		c, ok := peek(lexer)
		if !ok || c == '\n' do break
		advance(lexer)
	}
}

eat_whitespace :: proc(lexer: ^Lexer) {
	for {
		c, ok := peek(lexer)
		if !ok || !is_whitespace(c) do break
		advance(lexer)
	}
}

is_lowercase :: proc(char: u8) -> bool {
	return (char >= 'a' && char <= 'z')
}

is_uppercase :: proc(char: u8) -> bool {
	return (char >= 'A' && char <= 'Z')
}

is_digit :: proc(char: u8) -> bool {
	return (char >= '0' && char <= '9')
}

is_alpha :: proc(char: u8) -> bool {
	return is_lowercase(char) || is_uppercase(char)
}

is_whitespace :: proc(char: u8) -> bool {
	return char == ' ' || char == '\t' || char == '\r'
}
