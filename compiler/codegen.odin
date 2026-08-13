package compiler

import "core:mem"
import "core:strings"

generate :: proc(program: ^Program, allocator: mem.Allocator) -> string {
	code := strings.builder_make(allocator = allocator)
	for decl in program.decls {

		#partial switch d in decl {
		case Const: {

			value: string
			#partial switch rhs in d.value {
			case Number: {
				value = string(rhs.value)
			}

			case Identifier: {
				value = string(rhs.name)
			}
			}

			strings.write_string(&code, "static const int ")
			strings.write_string(&code, string(d.name))
			strings.write_string(&code, " = ")
			strings.write_string(&code, value)
			strings.write_string(&code, ";\n")
		}
		}
	}
	return strings.to_string(code)
}