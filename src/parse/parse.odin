package parse

// Returns a slice before the first instance of a char, including said character
slice_before_first :: proc(inp: string, c: rune) -> (val: string, ok: bool)
{
	for r, i in inp	
	{
		if r == c
		{
			return inp[:i+1], true;
		}
	}
	return inp, false;
}

// Returns a slice after the first instance of a char, excluding said char
slice_after_first :: proc(inp: string, c: rune) -> (val: string, ok: bool)
{
	for r, i in inp	
	{
		if r == c
		{
			return inp[i+1:], true;
		}
	}
	return inp, false;
}

slice_at_first :: proc(inp: string, c: rune) -> (before, after: string, ok: bool)
{
	for r, i in inp	
	{
		if r == c
		{
			return inp[:i+1], inp[i+1:], true;
		}
	}
	return inp, {}, false;
}

find_first :: proc(inp: string, c: rune) -> (pos: i64, ok: bool)
{
	for r, i in inp	
	{
		if r == c
		{
			return i64(i), true;
		}
	}
	return -1, false;
}

slice_before_last :: proc(inp: string, c: rune) -> (val: string, ok: bool)
{
	l := i32(len(inp));
	if l == 0
	{
		return inp, false;
	}

	for i := l - 1; i >= 0; i -= 1
	{
		if inp[i] == cast(u8)c
		{
			return inp[:i+1], true;
		}
	}	
	return inp, false;
}

slice_after_last :: proc(inp: string, c: rune) -> (val: string, ok: bool)
{
	l := i32(len(inp));
	if l == 0
	{
		return inp, false;
	}

	for i := l - 1; i >= 0; i -= 1
	{
		if inp[i] == cast(u8)c
		{
			return inp[i+1:], true;
		}
	}	
	return inp, false;
}

slice_at_last :: proc(inp: string, c: rune) -> (before, after: string, ok: bool)
{
	l := i32(len(inp));
	if l == 0
	{
		return inp, string {}, false;
	}

	for i := l - 1; i >= 0; i -= 1
	{
		if inp[i] == cast(u8)c
		{
			return inp[:i+1], inp[i+1:], true;
		}
	}	
	return inp, string {}, false;
}

find_last :: proc(inp: string, c: rune) -> (pos: i64, ok: bool)
{
	l := i64(len(inp));
	if l == 0
	{
		return -1, false;
	}

	for i := l - 1; i >= 0; i -= 1
	{
		if inp[i] == cast(u8)c
		{
			return i, true;
		}
	}	
	return -1, false;
}

is_identifier :: proc(c: rune) -> bool
{
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')	|| c == '_';
}

// Identifier after the first character, "value135"
is_identifier_plus :: proc(c: rune) -> bool
{
	return is_identifier(c) || is_digit(c);
}

// Tries to parse a \w+
slice_word :: proc(inp: string, at: i32 = 0) -> (word, after_word: string, ok: bool)
{
	return {}, {}, false;
}

is_digit :: proc(c: rune) -> bool
{
	return c >= '0' && c <= '9';
}

is_digit_pre :: proc(c: rune) -> bool
{
	return c == '-';
}

is_digit_float :: proc(c: rune) -> bool
{
	return is_digit(c) || c == '.';
}

slice_digits :: proc(inp: string, at: i32 = 0) -> (digits, after_digits: string, ok: bool)
{
	return {}, {}, false;
}

match_string_part :: proc(inp, word: string, at: i32 = 0) -> bool
{
	inp_len := i32(len(inp));
	word_len := i32(len(word));
	if at + word_len > inp_len
	{
		return false;	
	}

	for i := i32(0); i < word_len; i += 1
	{
		inp_i := i + at;
		if word[i] != inp[inp_i]
		{
			return false;
		}
	}

	return true;
}



