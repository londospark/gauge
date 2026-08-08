package parser

import "../lexer"

Parser :: struct {
	tokens:   []lexer.Token,
	position: int,
}

Node :: struct {
	offset: int
}

Expr :: union #no_nil {
	Unit,
	Binary,
	Unary,
	String,
	Number,
}

Unit :: struct {
	using node: Node,
}

BinaryOperator :: enum {
	Add, Subtract, Multiply, Divide
}

Binary :: struct {
	using node: Node,
	lhs:       ^Expr,
	rhs:       ^Expr,
	operator:  BinaryOperator,
}

UnaryOperator :: enum {
	Minus
}

Unary :: struct {
	using node: Node,
	operator:  UnaryOperator,
	operand:   ^Expr,
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