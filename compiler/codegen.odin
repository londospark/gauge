package compiler

import "core:fmt"
import "core:mem"
import "core:slice"
import "core:strings"

TypeMap   :: map[IdentifierToken]string
ConstRefs :: map[IdentifierToken]([dynamic]IdentifierToken)

Codegen :: struct {
	sb:    strings.Builder,
	types: TypeMap
}

get_type :: proc(types: ^TypeMap, identifier: IdentifierToken) -> string {
	if type, ok := types[identifier]; ok {
		return type
	}

	return "int"
}

collect_refs :: proc(expr: ^Expr, refs: ^[dynamic]IdentifierToken) {
	#partial switch e in expr {
	case Identifier: 
		append(refs, e.name)
	
	case Unary:
		collect_refs(e.operand, refs)

	case Binary:
		collect_refs(e.lhs, refs)
		collect_refs(e.rhs, refs)
	}
}

is_ready :: proc(refs: []IdentifierToken, emitted: []IdentifierToken) -> bool {
	for ref in refs {

		found := false
		for e in emitted {
			if e == ref {
				found = true
				break
			}
		}

		if !found {
			return false
		}
	}

	return true
}

generate :: proc(program: ^Program, allocator: mem.Allocator) -> string {
	codegen := Codegen{
		sb = strings.builder_make(allocator = allocator),
		types = make(TypeMap, allocator = allocator)
	}

	const_references := make(ConstRefs, allocator)
	unemitted := make([dynamic]Expr, allocator)
	for decl in program.decls {
		#partial switch d in decl {
		case Const:
			#partial switch rhs in d.value {
			case Number:
				value := string(rhs.value)
				if strings.contains_rune(value, '.') {
					codegen.types[d.name] = "double"
				} else {
					codegen.types[d.name] = "int"
				}
			
			}

			const_references[d.name] = make([dynamic]IdentifierToken, allocator)
			collect_refs(d.value, &const_references[d.name])
			append(&unemitted, d)
		}
	}

	emitted := make([dynamic]IdentifierToken, allocator)
	for {
		round_has_emissions := false
		for &decl in program.decls {

			#partial switch &d in decl {
			case Const:
				if slice.contains(emitted[:], d.name) do continue

				if is_ready(const_references[d.name][:], emitted[:]) {
					round_has_emissions = true
					emit_const(&codegen, &d, allocator)
					append(&emitted, d.name)
				}
			}
		}

		if !round_has_emissions do break
	}

	for &decl in program.decls {

		#partial switch &d in decl {
		case Const:
			if slice.contains(emitted[:], d.name) do continue
			emit_const(&codegen, &d, allocator)
		}
	}

	return strings.to_string(codegen.sb)
}

unary_to_string :: proc(op: UnaryOperator) -> (result: string) {
	switch op {
	case .Minus:
		result = "-"
	case .Plus:
		result = "+"
	}
	return
}

binary_to_string :: proc(op: BinaryOperator) -> (result: string) {
	switch op {
	case .Add:
		result = "+"
	case .Subtract:
		result = "-"
	case .Multiply:
		result = "*"
	case .Divide:
		result = "/"
	}
	return
}

emit_const :: proc(codegen: ^Codegen, const: ^Const, allocator: mem.Allocator) {

	// @Note: `name` threads down to the leaves so the Number case can
	//        look up the const's own type via get_type(types, name) —
	//        the provisional leaf-typing types no node itself, every
	//        leaf inherits the const's map entry.
	// @Review: resolved — the accepted provisional seam (§11.20): the
	//          checker (docs/type_system.md) owns real typing, and when
	//          it lands, leaves carry their own types and this
	//          parameter dies with the seam.
	resolve_expr :: proc(name: IdentifierToken, expr: ^Expr, types: ^TypeMap, allocator: mem.Allocator) -> (type: string, value: string) {
		#partial switch rhs in expr {
		case Number:
			value = string(rhs.value)
			type = get_type(types, name)

		case Identifier:
			value = string(rhs.name)
			type = get_type(types, rhs.name)
			
		case Unary:
			inner_type, inner_value := resolve_expr(name, rhs.operand, types, allocator)
			value = fmt.aprintf("(%v%v)", unary_to_string(rhs.operator), inner_value, allocator = allocator)
			type = inner_type


		case Binary:
			lhs_type, lhs_value := resolve_expr(name, rhs.lhs, types, allocator)
			rhs_type, rhs_value := resolve_expr(name, rhs.rhs, types, allocator)
			value = fmt.aprintf("(%v %v %v)", lhs_value, binary_to_string(rhs.operator), rhs_value, allocator = allocator)
			type = lhs_type
		}

		return
	}

	type, value := resolve_expr(const.name, const.value, &codegen.types, allocator)

	strings.write_string(&codegen.sb, "static const ")
	strings.write_string(&codegen.sb, type)
	strings.write_string(&codegen.sb, " ")
	strings.write_string(&codegen.sb, string(const.name))
	strings.write_string(&codegen.sb, " = ")
	strings.write_string(&codegen.sb, value)
	strings.write_string(&codegen.sb, ";\n")
}