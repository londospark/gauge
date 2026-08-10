package main

import "core:fmt"
import "lexer"
import "parser"

SimpleProgram :: `
KiB :: 1024
MiB :: KiB * 1024
GiB :: MiB * 1024`

main :: proc() {
	lexer_state := lexer.make_lexer(SimpleProgram)
	tokens, ok := lexer.lex(&lexer_state, context.temp_allocator)

	if !ok {
		fmt.eprintln(lexer_state.err)
		return
	}

	program, _, _ := parser.parse(tokens[:], context.temp_allocator)

	for token in tokens {
		fmt.printfln("Token: %v", token)
	}

	fmt.printfln("Program: %v", program)

	for decl in program.decls {
		fmt.printfln("Decl: %v", decl)
	}
}
