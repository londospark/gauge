package token

Token :: struct {
	offset:  int,
	value:   Value,
}

Value :: union #no_nil {
	SimpleToken,
	Identifier,
	Number,
	StringLiteral,
	Keyword,
}

Keyword :: enum {
	Proc
}

Identifier    :: distinct string
Number        :: distinct string
StringLiteral :: distinct string

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
