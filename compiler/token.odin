package compiler

Token :: struct {
	offset:  int,
	value:   ValueToken,
}

ValueToken :: union #no_nil {
	SimpleToken,
	IdentifierToken,
	NumberToken,
	StringLiteralToken,
	KeywordToken,
}

KeywordToken :: enum {
	Proc
}

IdentifierToken    :: distinct string
NumberToken        :: distinct string
StringLiteralToken :: distinct string

SimpleToken :: enum {
	Colon,
	LParen,
	RParen,
	LSquirly,
	RSquirly,
	Comma,
	Equals,
	Plus,
	Minus,
	Star,
	Slash,
	Hat,
	NewLine,
	EOF,
}
