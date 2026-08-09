package parser

import "core:fmt"
import tok "../token"

// The error message lives on the Parser so parse functions can return
// (T, bool) and use `or_return`; `parse` surfaces it as its third return.
Parser :: struct {
	tokens:   []tok.Token,
	position: int,
	err:      string,
}

// --- AST ---

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
	Minus
}

Unary :: struct {
	using node: Node,
	operator:   UnaryOperator,
	operand:    ^Expr,
}

String :: struct {
	using node: Node,
	value:      string,
}

Number :: struct {
	using node: Node,

	// @Note: this could be a numeric type, but at this point I
	//        don't think that it would be wise because it would
	//        have to be a float, and there's precision loss there.
	// @Review: resolved — keep raw text, parse to a typed value
	//          in the constant-folding pass.
	value:      string,
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

Const :: struct {
	using node: Node,
	name:       tok.Identifier,
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
	p.err = fmt.tprintf("expected %v at byte %d, got %v", kind, token.offset, token.value)
	return token, false
}

expect_identifier :: proc(p: ^Parser) -> (ident: tok.Identifier, offset: int, ok: bool) {
	token := current(p)
	if name, is_ident := token.value.(tok.Identifier); is_ident {
		advance(p)
		return name, token.offset, true
	}
	p.err = fmt.tprintf("expected Identifier at byte %d, got %v", token.offset, token.value)
	return "", 0, false
}

// --- Pratt (expressions) ---

Binding_Power :: struct {
	left:  int,
	right: int,
}

// Precedence table: Equals (1,1) right; Plus/Minus (10,11); Star/Slash (20,21); LParen (30,30).
binding_power :: proc(token: tok.Token) -> (Binding_Power, bool) {
	panic("todo: binding_power")
}

to_binary_operator :: proc(simple: tok.SimpleToken) -> BinaryOperator {
	#partial switch simple {
	case .Plus:  return .Add
	case .Minus: return .Subtract
	case .Star:  return .Multiply
	case .Slash: return .Divide
	}
	return .Add
}

parse_expression :: proc(p: ^Parser, minimum_binding_power: int, allocator := context.allocator) -> (expr: ^Expr, ok: bool) {
	panic("todo: parse_expression")
}

parse_prefix :: proc(p: ^Parser, allocator := context.allocator) -> (expr: ^Expr, ok: bool) {
	panic("todo: parse_prefix")
}

parse_infix :: proc(p: ^Parser, operator: tok.Token, left: ^Expr, right: ^Expr, allocator := context.allocator) -> (expr: ^Expr, ok: bool) {
	panic("todo: parse_infix")
}

parse_args :: proc(p: ^Parser, allocator := context.allocator) -> (args: [dynamic]^Expr, ok: bool) {
	panic("todo: parse_args")
}

// --- blocks, declarations, program ---

parse_block :: proc(p: ^Parser, allocator := context.allocator) -> (expr: ^Expr, ok: bool) {
	panic("todo: parse_block")
}

parse_decl :: proc(p: ^Parser, allocator := context.allocator) -> (decl: ^Expr, ok: bool) {
	ident, offset := expect_identifier(p) or_return
	expect_simple(p, .Colon) or_return
	expect_simple(p, .Colon) or_return

	if match_simple(p, .LParen) do panic("todo: Procedures/bracketed consts not implemented yet")

	value := parse_expression(p, 0, allocator) or_return

	return new_const(ident, value, offset, allocator), true
}

parse_program :: proc(p: ^Parser, allocator := context.allocator) -> (program: ^Program, ok: bool) {
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

parse :: proc(tokens: []tok.Token, allocator := context.allocator) -> (program: ^Program, ok: bool, err: string) {
	p := Parser { tokens = tokens }
	program, ok = parse_program(&p, allocator)
	return program, ok, p.err
}

// --- node construction ---

new_expr :: proc(variant: Expr, allocator := context.allocator) -> ^Expr {
	expr := new(Expr, allocator)
	expr^ = variant
	return expr
}

new_unit :: proc(offset: int, allocator := context.allocator) -> ^Expr {
	return new_expr(Unit { node = Node { offset = offset } }, allocator)
}

new_number :: proc(value: string, offset: int, allocator := context.allocator) -> ^Expr {
	return new_expr(Number { node = Node { offset = offset }, value = value }, allocator)
}

new_string :: proc(value: string, offset: int, allocator := context.allocator) -> ^Expr {
	return new_expr(String { node = Node { offset = offset }, value = value }, allocator)
}

new_ident :: proc(name: tok.Identifier, offset: int, allocator := context.allocator) -> ^Expr {
	return new_expr(Ident { node = Node { offset = offset }, name = name }, allocator)
}

new_unary :: proc(operator: UnaryOperator, operand: ^Expr, offset: int, allocator := context.allocator) -> ^Expr {
	return new_expr(Unary { node = Node { offset = offset }, operator = operator, operand = operand }, allocator)
}

new_binary :: proc(operator: BinaryOperator, lhs: ^Expr, rhs: ^Expr, offset: int, allocator := context.allocator) -> ^Expr {
	return new_expr(Binary { node = Node { offset = offset }, lhs = lhs, rhs = rhs, operator = operator }, allocator)
}

new_assign :: proc(name: tok.Identifier, value: ^Expr, offset: int, allocator := context.allocator) -> ^Expr {
	return new_expr(Assign { node = Node { offset = offset }, name = name, value = value }, allocator)
}

new_call :: proc(name: tok.Identifier, args: [dynamic]^Expr, offset: int, allocator := context.allocator) -> ^Expr {
	return new_expr(Call { node = Node { offset = offset }, name = name, args = args }, allocator)
}

new_block :: proc(body: [dynamic]^Expr, offset: int, allocator := context.allocator) -> ^Expr {
	return new_expr(Block { node = Node { offset = offset }, body = body }, allocator)
}

new_const :: proc(name: tok.Identifier, value: ^Expr, offset: int, allocator := context.allocator) -> ^Expr {
	return new_expr(Const { node = Node { offset = offset }, name = name, value = value }, allocator)
}

new_proc :: proc(name: tok.Identifier, body: ^Block, offset: int, allocator := context.allocator) -> ^Expr {
	return new_expr(Proc { node = Node { offset = offset }, name = name, body = body }, allocator)
}
