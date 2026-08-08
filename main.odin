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

peek :: proc(lexer: ^Lexer) -> u8 {
	if lexer.position >= len(lexer.source) do return 0
	return lexer.source[lexer.position]
}

advance :: proc(lexer: ^ Lexer) -> u8 {
	if lexer.position >= len(lexer.source) do return 0
	ch := lexer.source[lexer.position]
	lexer.position += 1
	return ch
}

lex_identifier :: proc(lexer: ^Lexer) -> Token {
	start := lexer.position
	for peek(lexer) >= 'a' && peek(lexer) <= 'z' {
		advance(lexer)
	}
	return Token {offset = start, value = Identifier(lexer.source[start:lexer.position]) }
}

lex_string :: proc(lexer: ^Lexer) -> Token {
	token_start := lexer.position
	advance(lexer)               // opening quote
	start := lexer.position

	for peek(lexer) != 0 && peek(lexer) != '"' {
		if peek(lexer) == '\\' {
			advance(lexer)       // the backslash
			if peek(lexer) != 0 {
				advance(lexer)   // the escaped character
			}
		} else {
			advance(lexer)
		}
	}
	end := lexer.position         // at the closing quote, or end of input

	advance(lexer)                // consume the closing quote (no-op at EOF)

	return Token { offset = token_start, value = StringLiteral(lexer.source[start:end]) }
}

eat_whitespace :: proc(lexer: ^Lexer) {
	for is_whitespace(peek(lexer)) {
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