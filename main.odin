package main

import "core:fmt"

Token :: struct {
	offset: int,
	value : Value
}

Value :: union #no_nil {
	SimpleToken,
	Identifier,
	Number,
	StringLiteral,
}

Identifier    :: distinct string
Number        :: distinct string
StringLiteral :: distinct string

SimpleToken :: enum {
	Colon,
	LParen,
	RParen,
	LSquirly,
	RSquirly,
	NewLine,
	EOF,
}

Lexer :: struct {
	source  : string,
	position: int,
}

SimpleProgram :: `
main :: () {
	print("Hellope")
}`

main :: proc() {
	lexer := make_lexer(SimpleProgram)
	tokens := lex(&lexer, context.temp_allocator)

	for token in tokens {
		fmt.printfln("Token: %v", token)
	}
}

make_lexer :: proc(input: string) -> Lexer {
	return Lexer { source = input, position = 0}
}

lex :: proc(lexer: ^Lexer, allocator := context.allocator) -> [dynamic]Token {
	result := make([dynamic]Token, allocator)

	lexing: for lexer.position < len(lexer.source) {
		eat_whitespace(lexer)

		if lexer.position >= len(lexer.source) {
			break lexing
		}

		switch lexer.source[lexer.position] {
			case ':':
				append(&result, Token { offset = lexer.position, value = .Colon})
				advance(lexer)
			case '(':
				append(&result, Token { offset = lexer.position, value = .LParen})
				advance(lexer)
			case ')':
				append(&result, Token { offset = lexer.position, value = .RParen})
				advance(lexer)
			case '{':
				append(&result, Token { offset = lexer.position, value = .LSquirly})
				advance(lexer)
			case '}':
				append(&result, Token { offset = lexer.position, value = .RSquirly})
				advance(lexer)
			case '\n':
				append(&result, Token { offset = lexer.position, value = .NewLine})
				advance(lexer)
			case 'a'..='z' :
				append(&result, lex_identifier(lexer))
			case '"' :
				append(&result, lex_string(lexer))
			case:
				fmt.eprintfln("UNRECOGNISED: %v", lexer)
				break lexing
		}
	}

	append(&result, Token { offset = len(lexer.source), value = .EOF })

	return result
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

lex_identifier :: proc(lexer: ^Lexer) -> Token {
	start := lexer.position
	for {
		c, ok := peek(lexer)
		if !ok || !is_lowercase(c) do break
		advance(lexer)
	}
	return Token {offset = start, value = Identifier(lexer.source[start:lexer.position]) }
}

lex_string :: proc(lexer: ^Lexer) -> Token {
	token_start := lexer.position
	advance(lexer)
	start := lexer.position

	for {
		c, ok := peek(lexer)
		if !ok || c == '"' do break
		if c == '\\' {
			advance(lexer)
			if _, ok := peek(lexer); ok {
				advance(lexer)
			}
		} else {
			advance(lexer)
		}
	}
	end := lexer.position

	advance(lexer)

	return Token { offset = token_start, value = StringLiteral(lexer.source[start:end]) }
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