package semantic

Body_Builder :: struct
{
	ret: Proc_Body,

	// Maintained while building the procedure body
	scope_stack: [dynamic]^Scope,

	// Deps
	global_scope: ^Global_Scope,
	decl: ^Proc_Decl,
}

// Use the scope_stack to find the proper relative handle to a variable
// This handle will no longer be valid once the scope stack is popped below
//   the current scope
get_variable_handle :: proc(body: ^Body_Builder, var_name: string) -> Var_Handle
{ return {}; }

Var_Decl :: struct
{
	name: string,
	type: Type_Id,
}

// Handle to a declared variable
// Meant to be used in expressions
Var_Handle :: struct
{
	reg_type: enum u16 {
		None, // Not set
		Known, // Not pointing to anything in particular
		Param, // Parameter of current function
		Scope, // Resides in scope of current function
		Global, // Resides in global scope
		Field, // Resides in a field of another variable or scope (player.pos.x)
	},
	// Which scope relative to the current scope the var resides in
	scope_depth: u16, 
	// The index within the relative scope
	index: u32,
}

Proc_Body :: struct
{
	//arguments
	body: ^Symbol,
}

// Defines a block scope
// There will be duplicate data between symbols and decls,
//   this is because symbols has all the data in order of declaration
Scope :: struct
{
	decls: [dynamic]Var_Decl,
	symbols: [dynamic]^Symbol,
	in_loop: bool,
}

// Anything that resides in a function body
Symbol :: union
{
	Scope,
	Var_Decl,
	Condition_Chain, // If-elif-else statements
	Loop,

	Assignment, // Assign a variable to a value
	//Expression,
	Function_Call, // Function call or expression that calls multiple functions
	Return,
	Break,
	Continue,
}

Condition_Chain :: struct {}
Loop :: struct {}
Return :: struct {}
Break :: struct {}
Continue :: struct {}

Assignment :: struct
{
	assigned_to: Access_Chain,
	value: ^Expression,
}

Expression :: struct
{
	resulting_type: Type_Id,
	variant: union
	{
		Xary_Expression,
		Unary_Expression,
		Access_Chain,
		Literal,
	},
}

Operator :: enum
{
	Error,

	Plus,
	Minus,
	Multiply,
	Divide,

	And,
	Or,
	Xor,
	Not,

	Equals_Equals,
	Equals,
	Greater_Equals,
	Greater,
	Less_Equals,
	Less,
}

Xary_Expression :: struct
{
	operators: [dynamic]Operator,
	expressions: [dynamic]^Expression,
}

Unary_Expression :: struct
{
	operator: Operator,
	expression: ^Expression,
}

Function_Call :: struct
{
	procedure: Proc_Id,
	arguments: [dynamic]^Expression,
}

Array_Access :: struct
{
	expression: ^Expression,
}

Access :: union
{
	Var_Handle,
	Function_Call,
	Array_Access,
}

Access_Chain :: struct
{
	chain: [dynamic]Access,
}

// TODO: arrays and maps
Literal :: union 
{
	i32, // int
	f32, // num
	string, // string
	bool, // bool
}
