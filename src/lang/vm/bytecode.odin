package vm

// Used to inject values into bytecode after they have already been added
// Used for injecting the jump values in cond_jump
Needle :: distinct int;
Needle_Big :: distinct int;

Raw_Value :: struct #raw_union 
{
	as_int: i32,
	as_num: f32,
	as_bool: bool,
}

Bytecode :: struct
{
	bytecode: [dynamic]u8,
	consts: [dynamic]Raw_Value,
	procs: [dynamic]i32, // Procedure links, map Proc_Id -> Bytecode_Ind

	// One line value is stored for each byte of written bytecode
	// This is not memory efficient at all, but it is an easy solution for
	//   debugging
	lines: [dynamic]int,
}

Opcode :: enum u8
{
	No_Op,
	End, // End the whole program
	Return, // Pop the call stack and return to the previous address
	Call, // Pops stack for function id, pushes current stack ptr onto call stack
	Cond_Jmp, // Uses condition to determine wether to jump
	Jump_If_False, // jump_size // Jumps forward by jump_size if condition on stack is false
	Jump_Back_If_True, // jump_size // Same as previous, but jumps backwards on false
	Jump_Back, // jump_size // Jump backwards by a set amount
	Literal, // const_ind
	Load, // Load a value from memory onto the stack. Pops address from stack, pushes value on stack
	Store, // Store a variable from the stack to memory
	Load_Stack, // Load variable from locals stack to expr stack
	Store_Stack, // Save variable from expr stack to locals stack

	Allocate, // word_count

	// Debug
	Print_Int,
	Print_Num,
	Print_Bool,
	Print_String,

	Add_Int,
	Sub_Int,
	Mul_Int,
	Div_Int,

	Add_Num,
	Sub_Num,
	Mul_Num,
	Div_Num,
	Sqrt_Num,
	Cos_Num,
	Sin_Num,

	Not, // Flip the bool on the top of the stack
	Inv_Int, // Invert the int on the top of the stack
	Inv_Num, // Invert the num on the top of the stack

	// Compare number operations
	Cmp_Greater_Int_Num,
	Cmp_Greater_Num_Int,
	Cmp_Greater_Int_Int,
	Cmp_Greater_Num_Num,
	Cmp_Greater_Equal_Int_Num,
	Cmp_Greater_Equal_Num_Int,
	Cmp_Greater_Equal_Int_Int,
	Cmp_Greater_Equal_Num_Num,
	Cmp_Less_Int_Num,
	Cmp_Less_Num_Int,
	Cmp_Less_Int_Int,
	Cmp_Less_Num_Num,
	Cmp_Less_Equal_Int_Num,
	Cmp_Less_Equal_Num_Int,
	Cmp_Less_Equal_Int_Int,
	Cmp_Less_Equal_Num_Num,
	Cmp_Equal_Equal_Int_Num,
	Cmp_Equal_Equal_Num_Int,
	Cmp_Equal_Equal_Int_Int,
	Cmp_Equal_Equal_Num_Num,

	And,
	Or,
	Xor,

	// Cast operations
	Cast_Int_To_Num,
	Cast_Num_To_Int,
	Cast_Bool_To_Num,
	Cast_Bool_To_Int,
}

inject_value_byte :: proc(bytecode: ^Bytecode, needle: Needle, value: u8)
{
	bytecode.bytecode[needle] = value;
}

inject_value_short :: proc(bytecode: ^Bytecode, needle: Needle_Big, value: u16)
{
	as_bytes := transmute([2]u8)value;
	bytecode.bytecode[needle] = as_bytes[0];
	bytecode.bytecode[needle + 1] = as_bytes[1];
}

get_current_instruction_index :: proc(bytecode: ^Bytecode) -> int
{
	return len(bytecode.bytecode);
}

// Returns index to spot in consts array
add_const :: proc(bytecode: ^Bytecode, value: Raw_Value) -> int
{
	ind := len(bytecode.consts);
	append(&bytecode.consts, value);
	return ind;
}

//add_return :: proc(bytecode: ^Bytecode, line: int)
//{
//	add_simple_opcode(bytecode, line, .Return);
//}

// Add an opcode that does not have an argument
add_simple_opcode :: proc(bytecode: ^Bytecode, line: int, opcode: Opcode)
{
	append(&bytecode.bytecode, u8(opcode));

	append(&bytecode.lines, line);
}

add_push_literal :: proc(bytecode: ^Bytecode, line: int, val: Raw_Value)
{
	append(&bytecode.bytecode, u8(Opcode.Literal));
	new_const := add_const(bytecode, val);
	// TODO: if this is kept as u8 value, it will cause issues
	append(&bytecode.bytecode, u8(new_const));

	// Needs two
	append(&bytecode.lines, line);
	append(&bytecode.lines, line);
}

// Returns needle to jump value
add_conditional_jump :: proc(bytecode: ^Bytecode, line: int, jump: u8) -> Needle
{
	append(&bytecode.bytecode, u8(Opcode.Cond_Jmp));
	ret := len(bytecode.bytecode);
	append(&bytecode.bytecode, jump);

	append(&bytecode.lines, line);
	append(&bytecode.lines, line);
	return cast(Needle)ret;
}

// TODO: swap bytes if on big endian system
add_jump_if_false :: proc(bytecode: ^Bytecode, line: int, jump: u16) -> Needle_Big
{
	append(&bytecode.bytecode, u8(Opcode.Jump_If_False));
	ret := len(bytecode.bytecode);

	as_bytes := transmute([2]u8)jump;
	append(&bytecode.bytecode, as_bytes[0]);
	append(&bytecode.bytecode, as_bytes[1]);

	append(&bytecode.lines, line);
	append(&bytecode.lines, line);
	append(&bytecode.lines, line);
	return cast(Needle_Big)ret;
}

// TODO: swap bytes if on big endian system
add_jump_back_if_true :: proc(bytecode: ^Bytecode, line: int, jump: u16) 
	-> Needle_Big
{
	append(&bytecode.bytecode, u8(Opcode.Jump_Back_If_True));
	ret := len(bytecode.bytecode);

	as_bytes := transmute([2]u8)jump;
	append(&bytecode.bytecode, as_bytes[0]);
	append(&bytecode.bytecode, as_bytes[1]);

	append(&bytecode.lines, line);
	append(&bytecode.lines, line);
	append(&bytecode.lines, line);
	return cast(Needle_Big)ret;
}

add_jump_back :: proc(bytecode: ^Bytecode, line: int, jump: u16) -> Needle_Big
{
	append(&bytecode.bytecode, u8(Opcode.Jump_Back));
	ret := len(bytecode.bytecode);

	as_bytes := transmute([2]u8)jump;
	append(&bytecode.bytecode, as_bytes[0]);
	append(&bytecode.bytecode, as_bytes[1]);

	append(&bytecode.lines, line);
	append(&bytecode.lines, line);
	append(&bytecode.lines, line);
	return cast(Needle_Big)ret;
}

add_call :: proc(bytecode: ^Bytecode, line: int, arg_count: u8, 
	current_locals_stack: u8)
{
	append(&bytecode.bytecode, u8(Opcode.Call));
	append(&bytecode.bytecode, arg_count);
	append(&bytecode.bytecode, current_locals_stack);

	append(&bytecode.lines, line);
	append(&bytecode.lines, line);
	append(&bytecode.lines, line);
}

add_call_static :: proc(bytecode: ^Bytecode, line: int, proc_id: i32, 
	arg_count: u8, current_locals_stack: u8)
{
	val: Raw_Value;
	val.as_int = proc_id;
	add_push_literal(bytecode, line, val);
	add_call(bytecode, line, arg_count, current_locals_stack);
}

add_return :: proc(bytecode: ^Bytecode, line: int)
{
	add_simple_opcode(bytecode, line, .Return);
}

// Start writing a new procedure
start_new_procedure :: proc(bytecode: ^Bytecode, proc_id: int) -> i32
{
	// 4 x no_op == new procedure
	append(&bytecode.bytecode, u8(Opcode.No_Op));
	append(&bytecode.bytecode, u8(Opcode.No_Op));
	append(&bytecode.bytecode, u8(Opcode.No_Op));
	append(&bytecode.bytecode, u8(Opcode.No_Op));

	append(&bytecode.lines, 0);
	append(&bytecode.lines, 0);
	append(&bytecode.lines, 0);
	append(&bytecode.lines, 0);

	if bytecode.procs == nil
	{
		bytecode.procs = make([dynamic]i32, proc_id + 1);
	}
	else
	{
		// Won't reallocate if it has enough memory
		// TODO: Check if it preallocates, because it should
		resize_dynamic_array(&bytecode.procs, proc_id + 1);
	}

	// Insert the link to the start of the new procedure
	ind := len(bytecode.bytecode);
	bytecode.procs[proc_id] = i32(ind);
	return i32(ind);
}

add_allocate :: proc(bytecode: ^Bytecode, line: int, word_count: u8)
{
	append(&bytecode.bytecode, u8(Opcode.Allocate));
	append(&bytecode.bytecode, word_count);

	append(&bytecode.lines, line);
	append(&bytecode.lines, line);
}

add_load :: proc(bytecode: ^Bytecode, line: int)
{
	add_simple_opcode(bytecode, line, .Load);
}

add_store :: proc(bytecode: ^Bytecode, line: int)
{
	add_simple_opcode(bytecode, line, .Store);
}

add_load_stack :: proc(bytecode: ^Bytecode, line: int, index: u8)
{
	append(&bytecode.bytecode, u8(Opcode.Load_Stack));
	append(&bytecode.bytecode, index);

	append(&bytecode.lines, line);
	append(&bytecode.lines, line);
}

add_store_stack :: proc(bytecode: ^Bytecode, line: int, index: u8)
{
	append(&bytecode.bytecode, u8(Opcode.Store_Stack));
	append(&bytecode.bytecode, index);

	append(&bytecode.lines, line);
	append(&bytecode.lines, line);
}


