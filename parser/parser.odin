package parser

import "core:fmt"
import "core:mem"
import tok "../token"

// The error message lives on the Parser so parse functions can return
// (T, bool) and use `or_return`; `parse` surfaces it as its third return.
Parser :: struct {
	tokens:   []tok.Token,
	position: int,
	err:      string,
}

// --- AST ---

// A node's offset is the byte of the token that created it — the
// operator for Binary/Assign, the `(` for Call, the token itself
// for atoms and Const. Never the start of the whole span: pulling
// a span start out of the Expr union would need a variant switch,
// and the creating token is the more precise diagnostic target.
Node :: struct {
	offset: int
}

Expr :: union #no_nil {
	Unit,
	Binary,
	Unary,
	String,
	Number,
	Ident,
	Call,
	Assign,
	Block,
	Const,
	Proc,
}

Unit :: struct {
	using node: Node,
}

BinaryOperator :: enum {
	Add, Subtract, Multiply, Divide
}

Binary :: struct {
	using node: Node,
	lhs:        ^Expr,
	rhs:        ^Expr,
	operator:   BinaryOperator,
}

UnaryOperator :: enum {
	Minus, Plus
}

Unary :: struct {
	using node: Node,
	operator:   UnaryOperator,
	operand:    ^Expr,
}

String :: struct {
	using node: Node,
	value:      tok.StringLiteral,
}

Number :: struct {
	using node: Node,

	// @Note: this could be a numeric type, but at this point I
	//        don't think that it would be wise because it would
	//        have to be a float, and there's precision loss there.
	// @Review: resolved — keep raw text, typed as tok.Number at the
	//          boundary so only a Number token can fill this field;
	//          parse to a typed value in the constant-folding pass.
	value:      tok.Number,
}

Ident :: struct {
	using node: Node,
	name:       tok.Identifier,
}

Call :: struct {
	using node: Node,
	name:       tok.Identifier,
	args:       [dynamic]^Expr,
}

Assign :: struct {
	using node: Node,
	name:       tok.Identifier,
	value:      ^Expr,
}

Block :: struct {
	using node: Node,
	body:       [dynamic]^Expr,
}

TypeName :: struct {
	using node: Node,
	name:       tok.Identifier
}

TypePointer :: struct {
	using node: Node,
	pointee:    ^Type
}

Type :: union #no_nil {
	TypeName, TypePointer
}

Const :: struct {
	using node: Node,
	name:       tok.Identifier,
	type:       ^Type,
	value:      ^Expr,
}

Proc :: struct {
	using node: Node,
	name:       tok.Identifier,
	body:       ^Block,
}

Program :: struct {
	decls:      [dynamic]^Expr,
}

// --- token helpers ---

current :: proc(p: ^Parser) -> tok.Token {
	return p.tokens[p.position]
}

advance :: proc(p: ^Parser) -> tok.Token {
	token := p.tokens[p.position]
	p.position += 1
	return token
}

peek :: proc(p: ^Parser, ahead: int) -> tok.Token {
	pos := p.position + ahead
	if pos >= len(p.tokens) {
		return p.tokens[len(p.tokens) - 1]
	}
	return p.tokens[pos]
}

is_eof :: proc(p: ^Parser) -> bool {
	if simple, ok := current(p).value.(tok.SimpleToken); ok && simple == .EOF {
		return true
	}
	return false
}

skip_newlines :: proc(p: ^Parser) {
	for match_simple(p, .NewLine) {}
}

match_simple :: proc(p: ^Parser, kind: tok.SimpleToken) -> bool {
	if simple, ok := current(p).value.(tok.SimpleToken); ok && simple == kind {
		advance(p)
		return true
	}
	return false
}

expect_simple :: proc(p: ^Parser, kind: tok.SimpleToken) -> (token: tok.Token, ok: bool) {
	token = current(p)
	simple, is_simple := token.value.(tok.SimpleToken)
	if is_simple && simple == kind {
		advance(p)
		return token, true
	}
	p.err = fmt.tprintf("Expected %v at byte %d, got %v", kind, token.offset, token.value)
	return token, false
}

match_keyword :: proc(p: ^Parser, kind: tok.Keyword) -> bool {
	if keyword, ok := current(p).value.(tok.Keyword); ok && keyword == kind {
		advance(p)
		return true
	}
	return false
}

expect_keyword :: proc(p: ^Parser, kind: tok.Keyword) -> (token: tok.Token, ok: bool) {
	token = current(p)
	keyword, is_keyword := token.value.(tok.Keyword)
	if is_keyword && keyword == kind {
		advance(p)
		return token, true
	}
	p.err = fmt.tprintf("Expected %v at byte %d, got %v", kind, token.offset, token.value)
	return token, false
}

expect_identifier :: proc(p: ^Parser) -> (ident: tok.Identifier, offset: int, ok: bool) {
	token := current(p)
	if name, is_ident := token.value.(tok.Identifier); is_ident {
		advance(p)
		return name, token.offset, true
	}
	p.err = fmt.tprintf("Expected Identifier at byte %d, got %v", token.offset, token.value)
	return "", 0, false
}

// --- Pratt (expressions) ---

BindingPower :: struct {
	left:  int,
	right: int,
}

// Precedence table: Equals (2,1) right; Plus/Minus (10,11); Star/Slash (20,21); LParen (30,30).
// Left-assoc: left < right. Right-assoc: left > right. See docs/pratt_parsing.md.
binding_power :: proc(token: tok.Token) -> (BindingPower, bool) {
	simple, is_simple := token.value.(tok.SimpleToken)
	if !is_simple do return BindingPower { left = 0, right = 0 }, false

	#partial switch simple {
	case .Equals:
		return BindingPower { left = 2, right = 1 }, true
	case .Plus, .Minus:
		return BindingPower { left = 10, right = 11 }, true
	case .Star, .Slash:
		return BindingPower { left = 20, right = 21 }, true
	case .LParen:
		return BindingPower { left = 30, right = 30 }, true
	}
	return BindingPower { left = 0, right = 0 }, false
}

unary_binding_power :: proc(token: tok.Token) -> (int, bool) {
	simple, is_simple := token.value.(tok.SimpleToken)
	if !is_simple do return 0, false

	#partial switch simple {
	case .Minus, .Plus: return 25, true
	}

	return 0, false
}

to_binary_operator :: proc(simple: tok.SimpleToken) -> BinaryOperator {
	#partial switch simple {
	case .Plus:  return .Add
	case .Minus: return .Subtract
	case .Star:  return .Multiply
	case .Slash: return .Divide
	}
	panic(fmt.tprintf("Someone passed %v to us and that's not a binary operator", simple))
}

to_unary_operator :: proc(simple: tok.SimpleToken) -> UnaryOperator {
	#partial switch simple {
	case .Plus:  return .Plus
	case .Minus: return .Minus
	}
	panic(fmt.tprintf("Someone passed %v to us and that's not a unary operator", simple))
}

parse_expression :: proc(p: ^Parser, minimum_binding_power: int, allocator: mem.Allocator) -> (expr: ^Expr, ok: bool) {
	lhs := parse_prefix(p, allocator) or_return

	for {
		bp, ok := binding_power(current(p))
		if bp.left < minimum_binding_power || !ok do return lhs, true
		operator := advance(p)
		rhs := parse_expression(p, bp.right, allocator) or_return
		lhs = parse_infix(p, operator, lhs, rhs, allocator) or_return
	}
}

parse_prefix :: proc(p: ^Parser, allocator: mem.Allocator) -> (expr: ^Expr, ok: bool) {
	token := current(p)
	#partial switch v in token.value {
	case tok.Number:
		advance(p)
		return new_number(v, token.offset, allocator), true

	case tok.Identifier:
		advance(p)
		return new_ident(v, token.offset, allocator), true

	case tok.StringLiteral:
		advance(p)
		return new_string(v, token.offset, allocator), true

	case tok.SimpleToken:
		if v == .LParen {
			// @Note: No need to expect anything, the if condition checked
			//        it all for us.
			// @Review: resolved — the `if v == .LParen` guard makes
			//          advance() exactly equivalent to expect_simple; keep
			//          it, the guard is the authority.
			advance(p)
			expr := parse_expression(p, 0, allocator) or_return
			expect_simple(p, .RParen) or_return
			return expr, true
		} else if v == .Minus || v == .Plus {
			advance(p)
			bp := unary_binding_power(token) or_return
			expr := parse_expression(p, bp, allocator) or_return
			return new_unary(to_unary_operator(v), expr, token.offset, allocator), true
		}
		p.err = fmt.tprintf("Expected an expression at byte %d, got %v", token.offset, token.value)

	case:
		p.err = fmt.tprintf("Expected an expression at byte %d, got %v", token.offset, token.value)
	}

	return nil, false
}

parse_infix :: proc(p: ^Parser, operator: tok.Token, left: ^Expr, right: ^Expr, allocator: mem.Allocator) -> (expr: ^Expr, ok: bool) {
	return new_binary(to_binary_operator(operator.value.(tok.SimpleToken)), left, right, operator.offset, allocator), true
}

parse_args :: proc(p: ^Parser, allocator: mem.Allocator) -> (args: [dynamic]^Expr, ok: bool) {
	panic("todo: parse_args")
}

// --- blocks, declarations, program ---

parse_block :: proc(p: ^Parser, allocator: mem.Allocator) -> (expr: ^Expr, ok: bool) {
	panic("todo: parse_block")
}

parse_type :: proc(p: ^Parser, allocator: mem.Allocator) -> (type: ^Type, ok: bool) {
	token := current(p)
	if match_simple(p, .Hat) {
		pointee := parse_type(p, allocator) or_return
		return new_pointer(pointee, token.offset, allocator), true
	} else {
		name, offset := expect_identifier(p) or_return
		return new_type_name(name, token.offset, allocator), true
	}
}

parse_decl :: proc(p: ^Parser, allocator: mem.Allocator) -> (decl: ^Expr, ok: bool) {
	ident, offset := expect_identifier(p) or_return
	expect_simple(p, .Colon) or_return
	type: ^Type
	if !match_simple(p, .Colon) {
		type = parse_type(p, allocator) or_return
		expect_simple(p, .Colon) or_return
	}

	if match_keyword(p, .Proc) do panic("todo: Procedures not implemented yet")

	value := parse_expression(p, 0, allocator) or_return

	return new_const(ident, type, value, offset, allocator), true
}

parse_program :: proc(p: ^Parser, allocator: mem.Allocator) -> (program: ^Program, ok: bool) {
	program = new(Program, allocator)
	program.decls = make([dynamic]^Expr, allocator)

	skip_newlines(p)
	for !is_eof(p) {
		decl := parse_decl(p, allocator) or_return
		append(&program.decls, decl)
		skip_newlines(p)
	}
	expect_simple(p, .EOF) or_return

	return program, true
}

parse :: proc(tokens: []tok.Token, allocator: mem.Allocator) -> (program: ^Program, ok: bool, err: string) {
	p := Parser { tokens = tokens }
	program, ok = parse_program(&p, allocator)
	return program, ok, p.err
}

// --- node construction ---

new_expr :: proc(variant: Expr, allocator: mem.Allocator) -> ^Expr {
	expr := new(Expr, allocator)
	expr^ = variant
	return expr
}

new_unit :: proc(offset: int, allocator: mem.Allocator) -> ^Expr {
	return new_expr(Unit { node = Node { offset = offset } }, allocator)
}

new_number :: proc(value: tok.Number, offset: int, allocator: mem.Allocator) -> ^Expr {
	return new_expr(Number { node = Node { offset = offset }, value = value }, allocator)
}

new_string :: proc(value: tok.StringLiteral, offset: int, allocator: mem.Allocator) -> ^Expr {
	return new_expr(String { node = Node { offset = offset }, value = value }, allocator)
}

new_ident :: proc(name: tok.Identifier, offset: int, allocator: mem.Allocator) -> ^Expr {
	return new_expr(Ident { node = Node { offset = offset }, name = name }, allocator)
}

new_unary :: proc(operator: UnaryOperator, operand: ^Expr, offset: int, allocator: mem.Allocator) -> ^Expr {
	if operand == nil do return nil
	return new_expr(Unary { node = Node { offset = offset }, operator = operator, operand = operand }, allocator)
}

new_binary :: proc(operator: BinaryOperator, lhs: ^Expr, rhs: ^Expr, offset: int, allocator: mem.Allocator) -> ^Expr {
	if lhs == nil || rhs == nil do return nil
	return new_expr(Binary { node = Node { offset = offset }, lhs = lhs, rhs = rhs, operator = operator }, allocator)
}

new_assign :: proc(name: tok.Identifier, value: ^Expr, offset: int, allocator: mem.Allocator) -> ^Expr {
	if value == nil do return nil
	return new_expr(Assign { node = Node { offset = offset }, name = name, value = value }, allocator)
}

new_call :: proc(name: tok.Identifier, args: [dynamic]^Expr, offset: int, allocator: mem.Allocator) -> ^Expr {
	return new_expr(Call { node = Node { offset = offset }, name = name, args = args }, allocator)
}

new_block :: proc(body: [dynamic]^Expr, offset: int, allocator: mem.Allocator) -> ^Expr {
	return new_expr(Block { node = Node { offset = offset }, body = body }, allocator)
}

new_const :: proc(name: tok.Identifier, type: ^Type, value: ^Expr, offset: int, allocator: mem.Allocator) -> ^Expr {
	if value == nil do return nil
	return new_expr(Const { node = Node { offset = offset }, name = name, type = type, value = value }, allocator)
}

new_proc :: proc(name: tok.Identifier, body: ^Block, offset: int, allocator: mem.Allocator) -> ^Expr {
	if body == nil do return nil
	return new_expr(Proc { node = Node { offset = offset }, name = name, body = body }, allocator)
}

new_type :: proc(variant: Type, allocator: mem.Allocator) -> ^Type {
	type := new(Type, allocator)
	type^ = variant
	return type
}

new_pointer :: proc(pointee: ^Type, offset: int, allocator: mem.Allocator) -> ^Type {
	if pointee == nil do return nil
	return new_type(TypePointer { node = Node { offset = offset }, pointee = pointee }, allocator)
}

new_type_name :: proc(name: tok.Identifier, offset: int, allocator: mem.Allocator) -> ^Type {
	return new_type(TypeName { node = Node { offset = offset }, name = name }, allocator)
}
