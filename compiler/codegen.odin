package compiler

import "core:fmt"
import "core:mem"
import "core:slice"
import "core:strings"

TypeMap     :: map[IdentifierToken]string
ConstRefs   :: map[IdentifierToken]([dynamic]IdentifierToken)
ConstValues :: map[IdentifierToken]string

Codegen :: struct {
	sb:     strings.Builder,
	types:  TypeMap,
	values: ConstValues,
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
		sb     = strings.builder_make(allocator = allocator),
		types  = make(TypeMap, allocator = allocator),
		values = make(ConstValues, allocator = allocator),
	}

	const_references := make(ConstRefs, allocator)
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
	//
	// The `values` map is the same seam seen from the value side: the
	// checker's fold pass (§11.20, type_system.md §3) owns constant
	// evaluation, and until it lands the emitter folds references
	// itself — the provisional fold the C output depends on. `resolved`
	// reports whether every leaf resolved to a stored value; an
	// unresolved (undeclared or cyclic) const never enters the map, so
	// later consts cannot substitute its fallback name.
	resolve_expr :: proc(name: IdentifierToken, expr: ^Expr, types: ^TypeMap, values: ^ConstValues, allocator: mem.Allocator) -> (type: string, value: string, resolved: bool) {
		#partial switch rhs in expr {
		case Number:
			value = string(rhs.value)
			type = get_type(types, name)
			resolved = true

		case Identifier:
			// C consts are not constant expressions — MSVC rejects
			// `static const int y = x;` with C2099 while gcc/clang
			// accept it as an extension. Substitute the referenced
			// const's already-emitted value so initialisers stay true
			// C constant expressions on every compiler. The value is
			// known because emission is dependency-ordered; an
			// undeclared or cyclic reference has no entry and falls
			// back to the name, which cc then reports (§11.20).
			value = string(rhs.name)
			if stored, ok := values[rhs.name]; ok {
				value = stored
				resolved = true
			}
			type = get_type(types, rhs.name)

		case Unary:
			inner_type, inner_value, inner_resolved := resolve_expr(name, rhs.operand, types, values, allocator)
			value = fmt.aprintf("(%v%v)", unary_to_string(rhs.operator), inner_value, allocator = allocator)
			type = inner_type
			resolved = inner_resolved


		case Binary:
			lhs_type, lhs_value, lhs_resolved := resolve_expr(name, rhs.lhs, types, values, allocator)
			rhs_type, rhs_value, rhs_resolved := resolve_expr(name, rhs.rhs, types, values, allocator)
			value = fmt.aprintf("(%v %v %v)", lhs_value, binary_to_string(rhs.operator), rhs_value, allocator = allocator)
			type = lhs_type
			resolved = lhs_resolved && rhs_resolved
		}

		return
	}

	type, value, resolved := resolve_expr(const.name, const.value, &codegen.types, &codegen.values, allocator)
	if resolved {
		codegen.values[const.name] = value
	}

	strings.write_string(&codegen.sb, "static const ")
	strings.write_string(&codegen.sb, type)
	strings.write_string(&codegen.sb, " ")
	strings.write_string(&codegen.sb, string(const.name))
	strings.write_string(&codegen.sb, " = ")
	strings.write_string(&codegen.sb, value)
	strings.write_string(&codegen.sb, ";\n")
}