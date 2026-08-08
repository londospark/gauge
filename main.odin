package main

import "core:fmt"

Token :: union #no_nil {
	SimpleToken,
	Identifier,
	Number,
}

Identifier :: distinct string
Number :: distinct string

SimpleToken :: enum {
	Colon,
	Proc,
	LParen,
	RParen,
	LSquirly,
	RSquirly,
	EOF,
}

print_simple_token :: proc(t: SimpleToken) {
	fmt.printfln("SimpleToken: {}", t)
}

main :: proc() {
	tokens := lexer("")

	for token in tokens {
		#partial switch t in token {
			case Identifier:
				fmt.printfln("IDENT: {}", t)
			case SimpleToken:
				print_simple_token(t)
			
		}
	}
}

lexer :: proc(input: string) -> (result: [dynamic]Token) {
	append(&result, Identifier("main"))
	append(&result, SimpleToken.EOF)
	return
}