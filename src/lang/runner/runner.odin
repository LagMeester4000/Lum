package runner

import sem "../semantic"

Runner :: struct
{
	// Holds all type and procedure information
	metadata: sem.Global_Scope;

	external_procs: map[sem.Proc_Id]External_Proc,

	// Runtime time vars
	stack: [dynamic]^Stack_Frame,
	current_stack: int,
}

make_runner :: proc() -> Runner
{
	ret: Runner;
	ret.metadata = sem.make_global_scope();
	return ret;
}

// This function should be called before the "analyze" proc is actually called
register_external_proc :: proc(runner: ^Runner, name: string, 
	args: [dynamic]sem.Var_decl, ret: sem.Type_Id, procedure: External_Proc)
{
	proc_v: sem.Proc_Decl;
	proc_v.external = true;
	proc_v.name = name;
	proc_v.arguments = args;
	proc_v.ret=  ret;

	new_proc := sem.register_proc(&runner.scope, proc_v);
	runner.external_procs[new_proc] = procedure;
}

External_Proc :: #type proc(runner: ^Runner, args: []Value) -> Value;

Stack_Frame :: struct
{
	values: [dynamic]Value;

	// The end of the current scope
	// Used to calculate the position of variables
	top: [dynamic]int,

	// Value returned by the current stack frame
	// Return value from a function call can be found by going into the next (no 
	//   longer used) stack frame and taking this variable
	return_val: Value,
}

Value :: union
{
	i32,
	f32,
	string,
	bool,
	Ref,
}

value_from_sem_literal :: proc(lit: sem.Literal) -> Value
{
	switch v in lit
	{
	case i32: return v;
	case f32: return v;
	case string: return v;
	case bool: return v;
	}
	return {};
}

// In bytecode a reference would not have a type index inside of it
Ref :: struct
{
	type: int,
	ptr: int,
}
