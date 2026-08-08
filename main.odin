package main

import "core:fmt"
import "lexer"

SimpleProgram :: `
main :: () {
	print("Hellope", 42)
}`

main :: proc() {
	lexer_state := lexer.make_lexer(SimpleProgram)
	tokens, ok := lexer.lex(&lexer_state, context.temp_allocator)

	if !ok {
		fmt.eprintln("lexing failed")
	}

	for token in tokens {
		fmt.printfln("Token: %v", token)
	}
}
