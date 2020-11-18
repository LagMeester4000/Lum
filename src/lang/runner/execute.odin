package runner

import sem "../semantic"

import "core:runtime"
import "core:reflect"

union_type_compare :: proc( a, b : any ) -> bool
{
    if a == nil || b == nil do return b == nil && a == nil;
    if a.id != b.id do return reflect.union_variant_typeid(a) == reflect.union_variant_typeid(b);

    ti := runtime.type_info_base(type_info_of(a.id));
    if info, ok := ti.variant.(runtime.Type_Info_Union); ok {
        a_tag := (cast(^u64)(uintptr(a.data) + info.tag_offset))^;
        b_tag := (cast(^u64)(uintptr(b.data) + info.tag_offset))^;
        return a_tag == b_tag;
    }
    return false;
}

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
	//for d in &scope.decls

	// Run symbols
	last_completed_if: int = -2;
	for s, i in scope.symbols
	{
		switch v in s
		{
		case sem.Var_Decl:
			// Empty on purpose

		case sem.Scope:
			run_scope(runner, &v);

		case sem.Var_Decl_Assign:
			assign_value := run_expression(runner, v.expr);
			stack := get_current_stack(runner);
			var_loc := get_var_location(stack, v.handle);
			stack.values[var_loc] = assign_value;

		case sem.Condition_Branch:
			can_check := true;
			if v.if_type == .ElseIf || v.if_type == .Else
			{
				// Check if the previous if statement was completed
				if last_completed_if == i - 1
				{
					can_check = false;
					// Any subsequent else/elif statements cannot continue either
					last_comleted_if = i;
				}
			}

			if can_check
			{
				cond_value := run_expression(runner, v.expr);

				as_bool, bool_ok := cond_value.(bool);
				if !bool_ok
				{
					panic("the expression returned a bool, that should not happen");
				}
				else if as_bool
				{
					// The statement returned true, execute the block
					last_comleted_if = i;

					as_scope, scope_ok := v.block.(sem.Scope);
					if !scope_ok do panic("condition block is not of type scope");

					code := run_scope(runner, &as_scope);
					if code != .None
					{
						return code;
					}
				}
			}

		case sem.Assignment:
			as_access, access_ok := v.value.variant.(sem.Access_Chain);
			if access_ok
			{
				assert(len(as_access.chain) == 1);
				access := as_access.chain[0];
				as_handle, handle_ok := access.(sem.Var_Handle);
				assert(handle_ok);

				stack := get_current_stack(runner);
				stack.values[get_var_location(stack, as_handle)] = 
					run_expression(runner, v.value);
			}

		case sem.Function_Call:
			// Lookup procedure to see if it is external
			proc_ref := &runner.metadata.proc_table[v.procedure];

			if proc_ref.is_external
			{
				ext_proc := runner.external_procs[v.procedure];

				arg_buffer := make([dynamic]Value);
				defer delete(arg_buffer);
				for arg in v.arguments
				{
					append(&arg_buffer, run_expression(runner, arg));
				}

				ext_proc(runner, arg_buffer[:]);
			}
			else
			{
				// TODO: argument values
			}

		case sem.Loop:
		case sem.Return:
			return .Return;

		case sem.Break:
			return .Break;

		case sem.Continue:
			return .Continue;
		}
	}

}

operate_on_value :: proc(left, right: Value, operator: sem.Operator) -> Value
{
	switch operator	
	{
	case .Plus: 
		op_proc :: proc(lhs: $T, rhs: T) -> T { return lhs + rhs; }
		#partial switch l in left
		{
		case i32:
			#partial switch r in right 
			{
			case i32: return op_proc(l, r);
			case f32: return op_proc(f32(l), r);
			}
		case f32:
			#partial switch r in right 
			{
			case i32: return op_proc(l, f32(r));
			case f32: return op_proc(l, r);
			}
		}
	case .Minus: 
		op_proc :: proc(lhs: $T, rhs: T) -> T { return lhs - rhs; }
		#partial switch l in left
		{
		case i32:
			#partial switch r in right 
			{
			case i32: return op_proc(l, r);
			case f32: return op_proc(f32(l), r);
			}
		case f32:
			#partial switch r in right 
			{
			case i32: return op_proc(l, f32(r));
			case f32: return op_proc(l, r);
			}
		}
	case .Multiply: 
		op_proc :: proc(lhs: $T, rhs: T) -> T { return lhs * rhs; }
		#partial switch l in left
		{
		case i32:
			#partial switch r in right 
			{
			case i32: return op_proc(l, r);
			case f32: return op_proc(f32(l), r);
			}
		case f32:
			#partial switch r in right 
			{
			case i32: return op_proc(l, f32(r));
			case f32: return op_proc(l, r);
			}
		}
	case .Divide: 
		op_proc :: proc(lhs: $T, rhs: T) -> T { return lhs / rhs; }
		#partial switch l in left
		{
		case i32:
			#partial switch r in right 
			{
			case i32: return op_proc(l, r);
			case f32: return op_proc(f32(l), r);
			}
		case f32:
			#partial switch r in right 
			{
			case i32: return op_proc(l, f32(r));
			case f32: return op_proc(l, r);
			}
		}

	// LOGIC
	case .And: 
		#partial switch l in left
		{
		case bool:
			#partial switch r in right
			{
			case bool:
				return l && r;
			}
		}
	case .Or: 
		#partial switch l in left
		{
		case bool:
			#partial switch r in right
			{
			case bool:
				return l || r;
			}
		}

	// COMPARE
	case .Equals_Equals:
		op_proc :: proc(lhs: $T, rhs: T) -> T { return lhs == rhs; }
		#partial switch l in left
		{
		case i32:
			#partial switch r in right
			{
			case i32: return op_proc(l, r);
			case f32: return op_proc(f32(l), r);
			}
		case f32:
			#partial switch r in right
			{
			case i32: return op_proc(l, f32(r));
			case f32: return op_proc(l, r);
			}
		case bool:
			#partial switch r in right
			{
			case bool: return op_proc(l, r);
			}
		case string:
			#partial switch r in right
			{
			case string: return op_proc(l, r);
			}
		}
	case .Greater_Equals:
		op_proc :: proc(lhs: $T, rhs: T) -> T { return lhs >= rhs; }
		#partial switch l in left
		{
		case i32:
			#partial switch r in right
			{
			case i32: return op_proc(l, r);
			case f32: return op_proc(f32(l), r);
			}
		case f32:
			#partial switch r in right
			{
			case i32: return op_proc(l, f32(r));
			case f32: return op_proc(l, r);
			}
		}
	case .Greater:
		op_proc :: proc(lhs: $T, rhs: T) -> T { return lhs > rhs; }
		#partial switch l in left
		{
		case i32:
			#partial switch r in right
			{
			case i32: return op_proc(l, r);
			case f32: return op_proc(f32(l), r);
			}
		case f32:
			#partial switch r in right
			{
			case i32: return op_proc(l, f32(r));
			case f32: return op_proc(l, r);
			}
		}
	case .Less_Equals:
		op_proc :: proc(lhs: $T, rhs: T) -> T { return lhs <= rhs; }
		#partial switch l in left
		{
		case i32:
			#partial switch r in right
			{
			case i32: return op_proc(l, r);
			case f32: return op_proc(f32(l), r);
			}
		case f32:
			#partial switch r in right
			{
			case i32: return op_proc(l, f32(r));
			case f32: return op_proc(l, r);
			}
		}
	case .Less:
		op_proc :: proc(lhs: $T, rhs: T) -> T { return lhs < rhs; }
		#partial switch l in left
		{
		case i32:
			#partial switch r in right
			{
			case i32: return op_proc(l, r);
			case f32: return op_proc(f32(l), r);
			}
		case f32:
			#partial switch r in right
			{
			case i32: return op_proc(l, f32(r));
			case f32: return op_proc(l, r);
			}
		}
	}
}

run_expression :: proc(runner: ^Runner, expr: ^sem.Expression) -> Value
{
	ret: Value;
	switch e in expr.variant
	{
	case sem.Xary_Expression:
		ret = run_expression(runner, e.expressions[0]);
		for o, oi in &e.operators
		{
			new_expr := &e.expressions[oi + 1];
			new_val := run_expression(runner, new_expr);
			ret = operate_on_value(ret, new_val, o);
		}

	case sem.Unary_Expression:
		// Unimplemented

	case sem.Access_Chain:
		

	case sem.Literal:
		ret = value_from_sem_literal(e);
	}
	return ret;
}