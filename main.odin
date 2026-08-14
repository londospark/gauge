package main

import "core:flags"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import "core:time"
import "compiler"

CommandLineArgs :: struct {
	file: string `args:"pos=0,required" usage:"Input file."`,
	time: bool    `usage:"Time each stage of the pipeline."`,
}

main :: proc() {

	args: CommandLineArgs
	flags.parse_or_exit(&args, os.args)

	t_total := time.now()

	contents, read_err := os.read_entire_file(args.file, context.temp_allocator)

	if read_err != nil {
		fmt.eprintln("Error: ", read_err)
		return
	}
	stage_time("read", t_total, args.time)

	t_stage := time.now()
	lexer_state := compiler.make_lexer(string(contents))
	tokens, ok := compiler.lex(&lexer_state, context.temp_allocator)

	if !ok {
		fmt.eprintln(lexer_state.err)
		return
	}
	stage_time("lex", t_stage, args.time)

	t_stage = time.now()
	program, _, _ := compiler.parse(tokens[:], context.temp_allocator)
	stage_time("parse", t_stage, args.time)

	t_stage = time.now()
	c_code := compiler.generate(program, context.temp_allocator)
	stage_time("codegen", t_stage, args.time)

	t_stage = time.now()
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

	_ = os.write_entire_file("gauge_program.c", c)
	stage_time("write C", t_stage, args.time)

	// Pick the C compiler for this platform. Windows walks a chain: MSVC's
	// `cl` when the shell is set up for it (a Developer Prompt, or vcvarsall
	// run by hand), then `cc` (mingw or clang), then bare `gcc` — whatever
	// the PATH actually holds. The rest of the world stays on `cc`. The run
	// step needs the .exe suffix on Windows — without it the loader cannot
	// find the binary the compiler just wrote.
	compile_command: []string
	run_command:    []string
	when ODIN_OS == .Windows {
		if on_path("cl", context.temp_allocator) {
			compile_command = {"cl", "/nologo", "gauge_program.c"}
		} else if on_path("cc", context.temp_allocator) {
			compile_command = {"cc", "-o", "gauge_program.exe", "gauge_program.c"}
		} else {
			compile_command = {"gcc", "-o", "gauge_program.exe", "gauge_program.c"}
		}
		run_command = {"gauge_program.exe"}
	} else {
		compile_command = {"cc", "-o", "gauge_program", "gauge_program.c"}
		run_command = {"./gauge_program"}
	}

	t_stage = time.now()
	compile_state, _, stderr, err := os.process_exec(
		{command = compile_command},
		context.allocator,
	)
	defer delete(stderr)
	if err != nil {
		fmt.eprintln("C compiler failed to start: ", err)
	}
	if compile_state.exit_code != 0 {
		fmt.eprintln(string(stderr))
	}
	stage_time("compile", t_stage, args.time)

	t_stage = time.now()
	_, stdout, _, run_err := os.process_exec(
		{command = run_command},
		context.allocator,
	)
	defer delete(stdout)
	if run_err != nil {
		fmt.eprintln("Failed to run the compiled program: ", run_err)
	}
	stage_time("run", t_stage, args.time)

	fmt.print(string(stdout))
	stage_time("total", t_total, args.time)
}

// on_path reports whether the named program resolves through PATH — the
// shell was prepared for it, whether by a Developer Prompt (cl), a mingw
// install (gcc), or anything else. Only the Windows build consults it,
// so the .exe suffix and ; separator are the Windows ones. A bare-shell
// Windows user falls through the cl -> cc -> gcc chain to whichever of
// them actually exists.
on_path :: proc(program_name: string, allocator: mem.Allocator) -> bool {
	exe_name := strings.concatenate({program_name, ".exe"}, allocator)
	defer delete(exe_name, allocator)

	path_env := os.get_env("PATH", allocator)
	defer delete(path_env, allocator)
	if len(path_env) == 0 do return false

	// split_iterator consumes its input; scanning a copy keeps path_env
	// intact so the deferred delete frees the original buffer, not an
	// interior pointer.
	scan := path_env
	found := false
	for dir in strings.split_iterator(&scan, ";") {
		candidate := os.join_path({dir, exe_name}, allocator) or_continue
		defer delete(candidate, allocator)
		if os.is_file(candidate) {
			found = true
			break
		}
	}

	return found
}

// stage_time reports one pipeline stage's elapsed time to stderr, gated on
// -time. stderr keeps the program's own stdout output clean — the demo's
// "result = ..." line stays the only thing on stdout. The C compiler step
// is the usual suspect for a slow demo; the other stages prove whether
// that is true or the front end carries the real cost.
stage_time :: proc(name: string, start: time.Time, enabled: bool) {
	if !enabled do return
	fmt.eprintf("time: %-14s %.3f ms\n", name, time.duration_milliseconds(time.since(start)))
}
