package main

import "core:flags"
import "core:fmt"
import "core:os"
import "core:strings"
import "compiler"

CommandLineArgs :: struct {
	file: string,
}

main :: proc() {

	args: CommandLineArgs
	flags.parse_or_exit(&args, os.args)
	fmt.println("File: ", args.file)

	contents, read_err := os.read_entire_file(args.file, context.temp_allocator)

	if read_err != nil {
		fmt.eprintln("Error: ", read_err)
		return
	}

	lexer_state := compiler.make_lexer(string(contents))
	tokens, ok := compiler.lex(&lexer_state, context.temp_allocator)

	if !ok {
		fmt.eprintln(lexer_state.err)
		return
	}

	program, _, _ := compiler.parse(tokens[:], context.temp_allocator)
	c_code := compiler.generate(program, context.temp_allocator)

	c_sb := strings.builder_make()
	fmt.sbprintln(&c_sb, "#include <stdio.h>")
	fmt.sbprintln(&c_sb, "")
	fmt.sbprintln(&c_sb, c_code)
	fmt.sbprintln(&c_sb, "")
	fmt.sbprintln(&c_sb, "int main(void) {")
	fmt.sbprintln(&c_sb, "	printf(\"result = %d\\n\", Print);")
	fmt.sbprintln(&c_sb, "return 0;")
	fmt.sbprintln(&c_sb, "}")

	c := strings.to_string(c_sb)

	// Write the generated C.
	_ = os.write_entire_file("gauge_program.c", c)  // returns an Error; check it
	
	// Compile: run + wait + capture, all in one call. The command is a
	// []string — no shell involved, no quoting to escape.
	state, _, stderr, err := os.process_exec(
	    {command = {"cc", "-o", "gauge_program", "gauge_program.c"}},
	    context.allocator,
	)
	defer delete(stderr)                          // the captured slices are yours to free
	if err != nil { /* cc failed to start */ }
	if state.exit_code != 0 { /* cc rejected the C — stderr has the diagnostics */ }
	
	// Run it.
	_, stdout, _, _ := os.process_exec(
	    {command = {"./gauge_program"}},
	    context.allocator,
	)
	defer delete(stdout)
	fmt.print(string(stdout))                     // the program's output
}
