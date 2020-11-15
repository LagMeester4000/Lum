package lexer

import str "../../parse"

Token_Type :: enum 
{
	None,
	EOF,

	BEGIN_CHECKABLE,

	Key_Proc,
	Key_Struct,
	Key_Return,
	Key_For,
	Key_While,
	Key_Break,
	Key_Continue,
	Key_In,
	Key_If,
	Key_Elif,
	Key_Else,
	Key_And,
	Key_Or,
	Key_Xor,
	Key_Not,
	Key_Var,

	// It's better to just have these as identifiers, since it's annoying
	//   when parsing types
	//Key_Int,
	//Key_Float,

	Block_Open,
	Block_Close,
	Paren_Open,
	Paren_Close,
	Brack_Open,
	Brack_Close,

	Minus,
	Plus,
	Mul,
	Div,

	Equals_Equals,
	Equals,
	Greater_Equals,
	Greater,
	Less_Equals,
	Less,

	Dot,
	Comma,
	Semi_Colon,
	Colon,

	// Literals that can be read directly
	True,
	False,

	END_CHECKABLE,

	Int_Number, // 1523
	Float_Number, // 15.23
	String_Literal,

	Identifier,
}

Token_Type_Strings :: [?]string
{
	"",
	"",

	"", // BEGIN_CHECKABLE

	"proc",
	"struct",
	"return",
	"for",
	"while",
	"break",
	"continue",
	"in",
	"if",
	"elif",
	"else",
	"and",
	"or",
	"xor",
	"not",
	"var",

	//"int",
	//"float",

	"{",
	"}",
	"(",
	")",
	"[",
	"]",

	"-",
	"+",
	"*",
	"/",

	"==",
	"=",
	">=",
	">",
	"<=",
	"<",

	".",
	",",
	";",
	":",

	"true",
	"false",

	"", // END_CHECKABLE

	"",
	"",
};

Pos :: struct
{
	line: int,
	char: int,
	offset: int, // Raw pos in string
}

Token :: struct 
{
	type: Token_Type,
	begin, end: Pos,
}

Lexer :: struct 
{
	tokens: []Token,
	input: string,
}

destroy_lexer :: proc(lexer: ^Lexer, allocator := context.allocator)
{
	delete(lexer.tokens, allocator);
}

// TODO: finish this
make_pos :: proc(inp: string, index: int) -> Pos
{
	str_len := len(inp);
	if index >= str_len
	{
		return Pos {
			offset = index,
		};
	}
	else
	{
		line := 1;
		char := 1;
		for i := 0; i <= index; i += 1
		{
			if inp[i] == '\n'
			{
				char = 1;
				line += 1;
			}
			else
			{
				char += 1;
			}
		}

		return Pos {
			offset = index,
			line = line,
			char = char,
		};
	}
}

lex :: proc(inp: string, allocator := context.allocator) -> Lexer
{
	return Lexer {
		tokens = _lex(inp, allocator),
		input = inp,
	};
}

_lex :: proc(inp: string, allocator := context.allocator) -> []Token
{
	ret := make([dynamic]Token, allocator);

	main_lex_loop: for i: int = 0; i < len(inp); i += 1
	{
		c := inp[i];

		switch c
		{
		case '\n': fallthrough;
		case '\r': fallthrough;
		case ' ': 
			continue;

		case: 
			// Match keywords and known types
			{
				do_continue := false;
				token_type_strings_table := Token_Type_Strings;

				// TODO: this can be optimized A LOT, but i'm lazy
				word_match: for tok_type := int(Token_Type.BEGIN_CHECKABLE) + 1; 
					tok_type < int(Token_Type.END_CHECKABLE);
					tok_type += 1
				{
					tok_str := token_type_strings_table[tok_type];
					if str.match_string_part(inp, tok_str, i32(i))
					{
						push := Token {
							type = Token_Type(tok_type),
							begin = make_pos(inp, i),
							end = make_pos(inp, i + len(tok_str)),
						};
						append(&ret, push);
						i += len(tok_str) - 1;
						do_continue = true;
						break word_match;
					}
				}

				if do_continue do continue;
			}

			// Match identifier
			{
				if str.is_identifier(cast(rune)c)
				{
					push := Token {
						type = .Identifier,
						begin = make_pos(inp, i),
					};

					i += 1;
					for str.is_identifier_plus(cast(rune)inp[i])
					{
						i += 1;
					}

					push.end = make_pos(inp, i);
					append(&ret, push);
					i -= 1;
					continue;
				}
			}

			// Match number
			{
				if str.is_digit(cast(rune)c)
				{
					push := Token {
						type = .Int_Number,
						begin = make_pos(inp, i),
					};

					i += 1;
					for str.is_digit(cast(rune)inp[i])
					{
						i += 1;
					}

					push.end = make_pos(inp, i);
					append(&ret, push);
					i -= 1;
					continue;
				}
			}

		case '"':
			i += 1;
			if i >= len(inp) do break main_lex_loop;
			begin_pos := make_pos(inp, i);
			c = inp[i];
			for c != '"'
			{
				i += 1;
				if i >= len(inp) do break main_lex_loop;
				c = inp[i];
			}

			i -= 1;
			end_pos := make_pos(inp, i);
			push: Token;
			push.begin = begin_pos;
			push.end = end_pos;
			push.type = .String_Literal;
			append(&ret, push);

		}
	}

	// Add end of file
	{
		push := Token {
			type = .EOF
		};
		append(&ret, push);
	}

	return ret[:];
}

get_token_string :: proc(token: Token, lexer: ^Lexer) -> string
{
	return lexer.input[token.begin.offset:token.end.offset];
}

