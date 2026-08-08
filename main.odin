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
}
`

main :: proc() {
	lexer := make_lexer(SimpleProgram)
	//lexer := make_lexer("a ")
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
				lexer.position += 1
			case '(':
				append(&result, Token { offset = lexer.position, value = .LParen})
				lexer.position += 1
			case ')':
				append(&result, Token { offset = lexer.position, value = .RParen})
				lexer.position += 1
			case '{':
				append(&result, Token { offset = lexer.position, value = .LSquirly})
				lexer.position += 1
			case '}':
				append(&result, Token { offset = lexer.position, value = .RSquirly})
				lexer.position += 1
			case '\n':
				append(&result, Token { offset = lexer.position, value = .NewLine})
				lexer.position += 1
			case 'a'..='z':
				append(&result, lex_identifier(lexer))
			case '"' :
				append(&result, lex_string(lexer))
				lexer.position += 1
			case:
				fmt.eprintfln("UNRECOGNISED: %v", lexer)
				break lexing
		}
	}

	append(&result, Token { offset = len(lexer.source), value = .EOF })

	return result
}

lex_identifier :: proc(lexer: ^Lexer) -> Token {
	start := lexer.position
	for lexer.position < len(lexer.source) && lexer.source[lexer.position] >= 'a' && lexer.source[lexer.position] <= 'z' {
		lexer.position += 1
	}
	return Token {offset = start, value = Identifier(lexer.source[start:lexer.position]) }
}

lex_string :: proc(lexer: ^Lexer) -> Token {
	lexer.position += 1
	start := lexer.position
	for lexer.position < len(lexer.source) && lexer.source[lexer.position] != '"' {
		lexer.position += 1
	}
	return Token {offset = start, value = StringLiteral(lexer.source[start:lexer.position]) }
}

eat_whitespace :: proc(lexer: ^Lexer) {
	for lexer.position < len(lexer.source) && is_whitespace(lexer.source[lexer.position]) {
		lexer.position += 1
	}
}

is_whitespace :: proc(char: u8) -> bool {
	return char == ' ' || char == '\t' || char == '\r'
}