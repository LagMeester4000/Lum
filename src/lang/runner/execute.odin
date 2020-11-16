package runner

import sem "../semantic"

run :: proc(runner: ^Runner, procedure_name := "main")
{
	proc_index := sem.find_proc(&runner.scope, procedure_name);
	if proc_index == 0 do return;

	procedure := runner.scope.proc_table[proc_index];


}

push_stack :: proc(runner: ^Runner)
{
	if runner.current_stack >= len(runner.stacks)
	{
		new_stack := new(Stack_Frame);
		// TODO: make stackframe values array dynamic
		new_stack.values = make([dynamic]Value, 100);
		append(&runner.stack, new_stack);
		runner.current_stack += 1;
	}
	else
	{
		runner.current_stack += 1;
		new_stack := get_current_stack(runner);
		new_stack.top = 0;
		// TODO: is this needed?
		for v in &new_stack.values
		{
			v = i32(0);
		}
		new_stack.return_val = i32(0);
	}
}

pop_stack :: proc(runner: ^Runner)
{
	runner.current_stack -= 1;
	assert(runner.current_stack >= 0, "Current stack is negative, there is a push_stack missing somewhere");
}

get_current_stack :: proc(runner: ^Runner) -> ^Stack_Frame
{
	return runner.stack[runner.current_stack];
}

get_last_returned_val :: proc(runner: ^Runner) -> Value
{
	if runner.current_stack + 1 >= len(runner.stack)
	{
		unreachable("There is no returned value");
	}
	return runner.stack[runner.current_stack + 1].return_val;
}

get_frame_top :: proc(stack: ^Stack_Frame) -> int
{
	if len(stack.top) == 0
	{
		return 0;
	}
	return stack.top[len(stack.top) - 1];
}

push_frame_top :: proc(stack: ^Stack_Frame, size: int)
{
	new_top := get_frame_top(stack) + size;
	append(&stack.top, new_top);
}

pop_frame_top :: proc(stack: ^Stack_Frame, size: int)
{
	pop(&stack.top);
}

// Counts back from the top of the current stack frame
// TODO: might want to reverse this ^
get_var_location :: proc(stack: ^Stack_Frame, handle: sem.Var_Handle) -> int
{
	// Last indexable position in the top stack
	top_stack_ind := len(stack.top) - 1;

	// TODO: support parameters and other accessors
	// My idea is to put the .Param values at the start of the value stack
	// That way they can be accessed by an index relative to the first value in
	//   the "top" stack
	assert(handle.reg_type == .Scope);

	// Calculate the index of the variable
	scope_depth_top := stack.top[top_stack_ind - scope_depth];
	return scope_depth_top - index;
}

Action_Code :: enum
{
	None,
	Break,
	Continue,
	Return,
}

run_symbol :: proc(runner: ^Runner, symbol: ^sem.Symbol) -> Action_Code
{
	switch s in symbol
	{
	case Scope:
	case Var_Decl:
	case Var_Decl_Assign:
	case Condition_Branch:
	case Loop:
	case Assignment:
	case Function_Call:
	case Return:
	case Break:
	case Continue:
	}
}

// NOTE: Does not create a new stackframe, but pushes the current stackframe top
run_scope :: proc(runner: ^Runner, scope: ^Scope) -> Action_Code
{
	decl_size := len(scope.decls);
	push_frame_top(runner, decl_size);
	defer pop_frame_top(runner, decl_size);

	// Initialize declarations


	// Run symbols
	for s, i in scope.symbols
	{
		switch v in s
		{
		case Var_Decl:
			// Empty on purpose

		case Scope:
			run_scope(runner, &v);

		case Var_Decl_Assign:

		case Condition_Branch:
		case Loop:
		case Assignment:
		case Function_Call:
		case Return:
			return .Return;
			
		case Break:
			return .Break;

		case Continue:
			return .Continue;
		}
	}

}