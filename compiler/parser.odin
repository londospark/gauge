package compiler

import "core:fmt"
import "core:mem"

// The error message lives on the Parser so parse functions can return
// (T, bool) and use `or_return`; `parse` surfaces it as its third return.
Parser :: struct {
	tokens:   []Token,
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
	Identifier,
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
	value:      StringLiteralToken,
}

Number :: struct {
	using node: Node,

	// @Note: this could be a numeric type, but at this point I
	//        don't think that it would be wise because it would
	//        have to be a float, and there's precision loss there.
	// @Review: resolved — keep raw text, typed as NumberToken at the
	//          boundary so only a Number token can fill this field;
	//          parse to a typed value in the constant-folding pass.
	value:      NumberToken,
}

Identifier :: struct {
	using node: Node,
	name:       IdentifierToken,
}

Call :: struct {
	using node: Node,
	name:       IdentifierToken,
	args:       [dynamic]^Expr,
}

Assign :: struct {
	using node: Node,
	name:       IdentifierToken,
	value:      ^Expr,
}

Block :: struct {
	using node: Node,
	body:       [dynamic]^Expr,
}

TypeName :: struct {
	using node: Node,
	name:       IdentifierToken
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
	name:       IdentifierToken,
	type:       ^Type,
	value:      ^Expr,
}

Proc :: struct {
	using node: Node,
	name:       IdentifierToken,
	body:       ^Block,
}

Program :: struct {
	decls:      [dynamic]^Expr,
}

// --- token helpers ---

current :: proc(p: ^Parser) -> Token {
	return p.tokens[p.position]
}

advance :: proc(p: ^Parser) -> Token {
	token := p.tokens[p.position]
	p.position += 1
	return token
}

peek :: proc(p: ^Parser, ahead: int) -> Token {
	pos := p.position + ahead
	if pos >= len(p.tokens) {
		return p.tokens[len(p.tokens) - 1]
	}
	return p.tokens[pos]
}

is_simple :: proc(p: ^Parser, t: SimpleToken) -> bool {
	if simple, ok := current(p).value.(SimpleToken); ok && simple == t {
		return true
	}
	return false
}

is_eof :: proc(p: ^Parser) -> bool {
	return is_simple(p, .EOF)
}

skip_newlines :: proc(p: ^Parser) {
	for match_simple(p, .NewLine) {}
}

match_simple :: proc(p: ^Parser, kind: SimpleToken) -> bool {
	if simple, ok := current(p).value.(SimpleToken); ok && simple == kind {
		advance(p)
		return true
	}
	return false
}

expect_simple :: proc(p: ^Parser, kind: SimpleToken) -> (token: Token, ok: bool) {
	token = current(p)
	simple, is_simple := token.value.(SimpleToken)
	if is_simple && simple == kind {
		advance(p)
		return token, true
	}
	p.err = fmt.tprintf("Expected %v at byte %d, got %v", kind, token.offset, token.value)
	return token, false
}

match_keyword :: proc(p: ^Parser, kind: KeywordToken) -> bool {
	if keyword, ok := current(p).value.(KeywordToken); ok && keyword == kind {
		advance(p)
		return true
	}
	return false
}

expect_keyword :: proc(p: ^Parser, kind: KeywordToken) -> (token: Token, ok: bool) {
	token = current(p)
	keyword, is_keyword := token.value.(KeywordToken)
	if is_keyword && keyword == kind {
		advance(p)
		return token, true
	}
	p.err = fmt.tprintf("Expected %v at byte %d, got %v", kind, token.offset, token.value)
	return token, false
}

expect_identifier :: proc(p: ^Parser) -> (ident: IdentifierToken, offset: int, ok: bool) {
	token := current(p)
	if name, is_ident := token.value.(IdentifierToken); is_ident {
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
binding_power :: proc(token: Token) -> (BindingPower, bool) {
	simple, is_simple := token.value.(SimpleToken)
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

unary_binding_power :: proc(token: Token) -> (int, bool) {
	simple, is_simple := token.value.(SimpleToken)
	if !is_simple do return 0, false

	#partial switch simple {
	case .Minus, .Plus: return 25, true
	}

	return 0, false
}

to_binary_operator :: proc(simple: SimpleToken) -> BinaryOperator {
	#partial switch simple {
	case .Plus:  return .Add
	case .Minus: return .Subtract
	case .Star:  return .Multiply
	case .Slash: return .Divide
	}
	panic(fmt.tprintf("Someone passed %v to us and that's not a binary operator", simple))
}

to_unary_operator :: proc(simple: SimpleToken) -> UnaryOperator {
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
	case NumberToken:
		advance(p)
		return new_number(v, token.offset, allocator), true

	case IdentifierToken:
		advance(p)
		return new_ident(v, token.offset, allocator), true

	case StringLiteralToken:
		advance(p)
		return new_string(v, token.offset, allocator), true

	case SimpleToken:
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

parse_infix :: proc(p: ^Parser, operator: Token, left: ^Expr, right: ^Expr, allocator: mem.Allocator) -> (expr: ^Expr, ok: bool) {
	simple, is_simple := operator.value.(SimpleToken)
	if !is_simple {
		p.err = fmt.tprintf("Expected a binary operator at byte %d, got %v", operator.offset, operator.value)
		return nil, false
	}

	// The Pratt loop only reaches here with operators binding_power admits;
	// the rows without arms are the deferred slices, rejected as errors
	// (ARB 0001) so a future `x = 5` fails loudly instead of parsing as
	// `x + 5`.
	#partial switch simple {
	case .Equals:
		p.err = fmt.tprintf("Assignment is not implemented yet (byte %d)", operator.offset)
		return nil, false
	case .LParen:
		p.err = fmt.tprintf("Call expressions are not implemented yet (byte %d)", operator.offset)
		return nil, false
	}

	return new_binary(to_binary_operator(simple), left, right, operator.offset, allocator), true
}

// The signature parens are a different production from call arguments:
// parameters are `name : type` pairs (spec/language.md §5.3), arguments are
// expressions. parse_args lands with the calls slice; until typed params
// land, this only consumes the parens.
parse_params :: proc(p: ^Parser) -> (ok: bool) {
	expect_simple(p, .LParen) or_return
	expect_simple(p, .RParen) or_return
	return true
}

// --- blocks, declarations, program ---

parse_block :: proc(p: ^Parser, allocator: mem.Allocator) -> (block: ^Block, ok: bool) {
	offset := current(p).offset
	expect_simple(p, .LSquirly) or_return
	skip_newlines(p)

	exprs := make([dynamic]^Expr, allocator)
	for !is_simple(p, .RSquirly) {
		expr := parse_expression(p, 0, allocator) or_return
		append(&exprs, expr)

		if !is_simple(p, .NewLine) && !is_simple(p, .RSquirly) {
			p.err = fmt.tprintf("Expected a newline after the expression at byte %d, got %v — one expression per line, this isn't a marshalling yard", current(p).offset, current(p).value)
			return nil, false
		}
		skip_newlines(p)
	}
	expect_simple(p, .RSquirly) or_return
	return new_block(exprs, offset, allocator), true
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

	if token := current(p); match_keyword(p, .Proc) {
		parse_params(p) or_return
		body := parse_block(p, allocator) or_return
		return new_proc(ident, body, offset, allocator), true
	}

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
		
		if !is_eof(p) && !match_simple(p, .NewLine) {
			p.err = fmt.tprintf("Expected a newline after the declaration at byte %d, got %v — one declaration per line, this isn't a marshalling yard", current(p).offset, current(p).value)
			return program, false
		}
		skip_newlines(p)
	}
	expect_simple(p, .EOF) or_return

	return program, true
}

parse :: proc(token_list: []Token, allocator: mem.Allocator) -> (program: ^Program, ok: bool, err: string) {
	tokens := zoning_pre_parse(token_list, allocator)
	p := Parser { tokens = tokens }
	program, ok = parse_program(&p, allocator)
	return program, ok, p.err
}

zoning_pre_parse :: proc(tokens: []Token, allocator: mem.Allocator) -> []Token {
	paren_depth := 0

	// @Note: we know we're allocating enough here (or more than enough)
	//        so the dynamic is just for convenience and to save using
	//        read and write indices.
	// @Review: resolved — capacity is len(tokens) and the output can only
	//          shrink (NewLines are dropped), so no reallocation ever
	//          happens; the pre-sized dynamic is deliberate.
	result := make([dynamic]Token, 0, len(tokens), allocator)
	for token in tokens {
		simple, is_simple := token.value.(SimpleToken)

		if !is_simple {
			append(&result, token)
			continue
		}

		#partial switch simple {
		case .LParen:
			paren_depth += 1
			append(&result, token)

		case .RParen:
			if paren_depth > 0 do paren_depth -= 1
			append(&result, token)

		case .NewLine:
			if paren_depth <= 0 do append(&result, token)

		case: append(&result, token)
		}
	}
	return result[:]
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

new_number :: proc(value: NumberToken, offset: int, allocator: mem.Allocator) -> ^Expr {
	return new_expr(Number { node = Node { offset = offset }, value = value }, allocator)
}

new_string :: proc(value: StringLiteralToken, offset: int, allocator: mem.Allocator) -> ^Expr {
	return new_expr(String { node = Node { offset = offset }, value = value }, allocator)
}

new_ident :: proc(name: IdentifierToken, offset: int, allocator: mem.Allocator) -> ^Expr {
	return new_expr(Identifier { node = Node { offset = offset }, name = name }, allocator)
}

new_unary :: proc(operator: UnaryOperator, operand: ^Expr, offset: int, allocator: mem.Allocator) -> ^Expr {
	if operand == nil do return nil
	return new_expr(Unary { node = Node { offset = offset }, operator = operator, operand = operand }, allocator)
}

new_binary :: proc(operator: BinaryOperator, lhs: ^Expr, rhs: ^Expr, offset: int, allocator: mem.Allocator) -> ^Expr {
	if lhs == nil || rhs == nil do return nil
	return new_expr(Binary { node = Node { offset = offset }, lhs = lhs, rhs = rhs, operator = operator }, allocator)
}

new_assign :: proc(name: IdentifierToken, value: ^Expr, offset: int, allocator: mem.Allocator) -> ^Expr {
	if value == nil do return nil
	return new_expr(Assign { node = Node { offset = offset }, name = name, value = value }, allocator)
}

new_call :: proc(name: IdentifierToken, args: [dynamic]^Expr, offset: int, allocator: mem.Allocator) -> ^Expr {
	return new_expr(Call { node = Node { offset = offset }, name = name, args = args }, allocator)
}

new_block :: proc(body: [dynamic]^Expr, offset: int, allocator: mem.Allocator) -> ^Block {
	block := new(Block, allocator)
	block^ = Block { node = Node { offset = offset }, body = body }
	return block
}

new_const :: proc(name: IdentifierToken, type: ^Type, value: ^Expr, offset: int, allocator: mem.Allocator) -> ^Expr {
	if value == nil do return nil
	return new_expr(Const { node = Node { offset = offset }, name = name, type = type, value = value }, allocator)
}

new_proc :: proc(name: IdentifierToken, body: ^Block, offset: int, allocator: mem.Allocator) -> ^Expr {
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

new_type_name :: proc(name: IdentifierToken, offset: int, allocator: mem.Allocator) -> ^Type {
	return new_type(TypeName { node = Node { offset = offset }, name = name }, allocator)
}
