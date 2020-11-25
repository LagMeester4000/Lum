package semantic

import vm "../vm"
import lex "../lexer"
import ast "../ast"

import "core:fmt"
import "core:strconv"
import "core:math/bits"


// A new body builder is made for each procedure being built
Body_Builder :: struct
{
	// Deps
	proc_id: Proc_Id,
	lexer: ^lex.Lexer,
	decl: ^Proc_Decl,
	glob_scope: ^Global_Scope,

	bytecode: ^vm.Bytecode,
	scope_stack: [dynamic]^Scope, // The Scope values live on the actual stack
	errors: [dynamic]Error,

	// Updated when entering and exiting scopes
	// Should encount for the procedure arguments that are placed on the stack
	stack_ind: int,
}

destroy_body_builder :: proc(builder: ^Body_Builder)
{
	for s in &builder.scope_stack do destroy_scope(s);
	delete(builder.scope_stack);
	for e in &builder.errors do destroy_error(&e);
	delete(builder.errors);
}

Scope :: struct
{
	decls: [dynamic]Scope_Var_Decl,
}

destroy_scope :: proc(scope: ^Scope)
{
	delete(scope.decls);
}

// Position on the vm stack (in stack frame)
Var_Id :: distinct i32;

Scope_Var_Decl :: struct
{
	var: Var_Decl,
	index: Var_Id,
}

Var_Decl :: struct
{
	name: string,
	type: Type_Id,
}

Error :: struct
{
	token: lex.Token,
	message: string,
}

destroy_error :: proc(error: ^Error)
{
	delete(error.message);
}

error :: proc(builder: ^Body_Builder, tok: lex.Token, args: ..any)
{
	push: Error;
	push.token = tok;
	push.message = fmt.aprint(args = { args }, sep = "");
	append(&builder.errors, push);

	// TEMP
	fmt.print(args = { "(", tok.begin.line, ",", tok.begin.char, ") " }, 
		sep = "");
	fmt.print(args = args, sep = "");
	fmt.print("\n");
}

// Finds local variables, which includes function arguments
find_local_decl :: proc(builder: ^Body_Builder, name: string) 
	-> (val: Scope_Var_Decl, ok: bool)
{
	// Try to find variable in scope
	scope_len := len(builder.scope_stack);
	for i in scope_len-1..0
	{
		scope := builder.scope_stack[i];
		for decl in &scope.decls
		{
			if decl.var.name == name
			{
				return decl, true;
			}
		}
	}

	// Try to find variable in arguments
	// TODO: this needs to be changed when variables longer than 1 word are used
	for arg, arg_i in builder.decl.arguments
	{
		if arg.name == name
		{
			ret: Scope_Var_Decl;
			ret.var = arg;
			ret.index = Var_Id(arg_i);
			return ret, true;
		}
	}

	return {}, false;
}

build_proc :: proc(builder: ^Body_Builder)
{
	vm.start_new_procedure(builder.bytecode, int(builder.proc_id));

	// Allocate space for arguments on the stack
	builder.stack_ind = len(builder.decl.arguments);

	proc_node := builder.decl.body_node;
	build_scope(builder, proc_node.block);

	vm.add_simple_opcode(builder.bytecode, 0, .Return);
}

build_scope :: proc(builder: ^Body_Builder, scope_node: ^ast.Block)
{
	// Stack index should be reset when exiting the scope
	stack_mark := builder.stack_ind;
	defer builder.stack_ind = stack_mark;

	// Make new scope
	scope: Scope;
	append(&builder.scope_stack, &scope);
	defer {
		destroy_scope(&scope);
		pop(&builder.scope_stack);
	}

	for stmt in &scope_node.exprs
	{
		switch s in &stmt.derived
		{
		case ast.Var_Decl:
			name := lex.get_token_string(s.name, builder.lexer);

			// Check if it already exists
			_, decl_ok := find_local_decl(builder, name);
			if decl_ok
			{
				error(builder, s.name, "variable declaration with name \"", name,
					"\" already exists, use another name");
				// Still continue, overrides the declaration and keeps future
				//   code from failing, possibly
			}

			// Make space on stack
			var_ind := builder.stack_ind;
			builder.stack_ind += 1;

			type: Type_Id = 0;
			if s.type != nil
			{
				type = find_type_from_node(builder.glob_scope, 
					s.type, builder.lexer);
			}

			if s.assignment != nil
			{
				// Writes expression stack
				expr_type := build_expr(builder, s.assignment);

				if type != 0 && expr_type != 0 && expr_type != type
				{
					error(builder, s.name, "given and inferred type are not equal");
				}
				else
				{
					type = expr_type;
				}

				// Save resulting expression to stack
				vm.add_store_stack(builder.bytecode, 
					s.name.begin.line, u8(var_ind));
			}
			
			if s.assignment == nil && s.type == nil
			{
				error(builder, s.name, 
					"variable declaration has no set type or inferred type");
			}

			new_var: Scope_Var_Decl;
			new_var.var.name = name;
			new_var.var.type = type;
			new_var.index = Var_Id(var_ind);
			append(&scope.decls, new_var);

		case ast.If:
			// TODO: check for the if types
			bool_type := find_type(builder.glob_scope, "bool");

			expr := build_expr(builder, s.condition);
			if expr != bool_type
			{
				error(builder, {}, "expression in if does not result in boolean");
			}

			needle := vm.add_jump_if_false(builder.bytecode, -1, 0);
			jump_start := vm.get_current_instruction_index(builder.bytecode);

			build_scope(builder, s.block);

			jump_end := vm.get_current_instruction_index(builder.bytecode);
			jump := jump_end - jump_start;
			assert(jump <= bits.U16_MAX);
			vm.inject_value_short(builder.bytecode, needle, u16(jump));

		case ast.While_Loop:
			jump_start := vm.get_current_instruction_index(builder.bytecode);

			bool_type := find_type(builder.glob_scope, "bool");
			expr := build_expr(builder, s.expr);
			if expr != bool_type
			{
				error(builder, {}, "expression in if does not result in boolean");
			}

			needle := vm.add_jump_if_false(builder.bytecode, -1, 0);

			// Scope
			build_scope(builder, s.block);
			jump_middle := vm.get_current_instruction_index(builder.bytecode);
			back_jump := jump_middle - jump_start;
			assert(back_jump <= bits.U16_MAX);
			vm.add_jump_back(builder.bytecode, -1, u16(back_jump));

			jump_end := vm.get_current_instruction_index(builder.bytecode);

			// Set the if statement jump
			vm.inject_value_short(builder.bytecode, needle, u16(jump_end - jump_start));

		case ast.For_Loop:
			unimplemented("TODO");

		case ast.For_Iterator:
			unimplemented("Arrays do not exist yet");

		case ast.Assign:
			// First do the expression, then do the store/assignment
			expr_type := build_expr(builder, s.value);

			switch as in s.assigned_to.derived
			{
			case ast.Access_Identifier:	
				name := lex.get_token_string(as.name, builder.lexer);
				decl, decl_ok := find_local_decl(builder, name);

				if !decl_ok
				{
					error(builder, as.name, "no variable of name\"", 
						name, "\" exists");
				}
				
				if decl.var.type == expr_type
				{
					error(builder, as.name, "expression type does not match", 
						" variable type");
				}

				vm.add_store_stack(builder.bytecode, as.name.begin.line, 
					u8(decl.index));
			}

		case ast.Return:
			// TODO: add line values to error and line buffer
			expr_type := build_expr(builder, s.expr);
			if builder.decl.ret != expr_type
			{
				error(builder, {}, "Returned value does not have the same type as",
					" set return type");
			}

			vm.add_simple_opcode(builder.bytecode, 0, .Return);

		case ast.Stmt_Expr:
			// TODO: eliminate non-allowed expressions
			build_expr(builder, s.expr);

		case:
			fmt.println("Unhandled statement:", stmt.derived);
		}
	}
}

// TODO: add handling for type conversion
build_expr :: proc(builder: ^Body_Builder, expr: ^ast.Expr) -> Type_Id
{
	switch e in &expr.derived
	{
	case ast.Literal_Value:
		str := lex.get_token_string(e.value, builder.lexer);
		#partial switch e.value.type
		{
		case .Int_Number:
			// TODO: choose another parse_i64 function, this one has e and other
			//   characters
			num, ok := strconv.parse_i64(str, 10);
			val: vm.Raw_Value;
			val.as_int = i32(num);
			vm.add_push_literal(builder.bytecode, e.value.begin.line, val);
			return find_type(builder.glob_scope, "int");

		case .False:
			val: vm.Raw_Value;
			val.as_bool = false;
			vm.add_push_literal(builder.bytecode, e.value.begin.line, val);
			return find_type(builder.glob_scope, "bool");

		case .True:
			val: vm.Raw_Value;
			val.as_bool = true;
			vm.add_push_literal(builder.bytecode, e.value.begin.line, val);
			return find_type(builder.glob_scope, "bool");

		case .Float_Number:
			unimplemented("Floating point parsing unimplemented");

		case .String_Literal:
			unimplemented("String parsing unimplemented");
		}

	case ast.Xary_Expr:
		// TODO: implement operators for num type

		// Parse the first expr and then do the others with operators
		root_type := build_expr(builder, e.exprs[0]);

		for o, i in e.operators
		{
			new_type := build_expr(builder, e.exprs[i + 1]);

			if root_type != new_type
			{
				error(builder, o, "new type is not the same as old type");
			}

			#partial switch o.type
			{
			case .Plus:
				vm.add_simple_opcode(builder.bytecode, o.begin.line, .Add_Int);

			case .Minus:
				vm.add_simple_opcode(builder.bytecode, o.begin.line, .Sub_Int);

			case .Mul:
				vm.add_simple_opcode(builder.bytecode, o.begin.line, .Mul_Int);

			case .Div:
				vm.add_simple_opcode(builder.bytecode, o.begin.line, .Div_Int);

			case .Key_And:
				vm.add_simple_opcode(builder.bytecode, o.begin.line, .And);

			case .Key_Or:
				vm.add_simple_opcode(builder.bytecode, o.begin.line, .Or);
			}
		}

		return root_type;

	case ast.Unary_Expr:
		unimplemented("Unary exprs not implemented");

	case ast.Call_Expr:
		name := lex.get_token_string(e.name, builder.lexer);
		proc_id := find_proc(builder.glob_scope, name);

		if proc_id == 0
		{
			// NOTE: builtin procedures
			if name == "print"
			{
				int_type := find_type(builder.glob_scope, "int");
				num_type := find_type(builder.glob_scope, "num");
				bool_type := find_type(builder.glob_scope, "bool");
				string_type := find_type(builder.glob_scope, "string");

				for arg in &e.arguments
				{
					eval_type := build_expr(builder, arg);
					if eval_type == int_type
					{
						vm.add_simple_opcode(builder.bytecode, 0, .Print_Int);
					}
					else if eval_type == num_type
					{
						vm.add_simple_opcode(builder.bytecode, 0, .Print_Num);
					}
					else if eval_type == bool_type
					{
						vm.add_simple_opcode(builder.bytecode, 0, .Print_Bool);
					}
					else if eval_type == string_type
					{
						vm.add_simple_opcode(builder.bytecode, 0, .Print_String);
					}
				}

				return 0;
			}
			else
			{
				error(builder, e.name, "procedure ", name, " does not exist");
				return 0;
			}
		}
		else
		{
			proc_ref := &builder.glob_scope.proc_table[proc_id];
			proc_arg_len := len(proc_ref.arguments);
			called_proc_arguments := len(e.arguments);

			if proc_arg_len != called_proc_arguments
			{
				error(builder, e.name, "procedure call argument count (",
					called_proc_arguments, 
					") does not match actual procedure count (",
					proc_arg_len, ")");
				return proc_ref.ret;
			}

			// Push procedure arguments
			for real_arg, arg_i in &proc_ref.arguments
			{
				call_arg := e.arguments[arg_i];
				real_arg_type := real_arg.type;
				call_arg_type := build_expr(builder, call_arg);

				if real_arg_type != call_arg_type
				{
					// TODO: update error token
					// TODO: give error the string of the type instead of ID
					error(builder, e.name, "procedure call argument ", arg_i,
						" does not equal requested type ", real_arg_type);
				}
			}

			// Push procedure id
			proc_id_lit: vm.Raw_Value;
			proc_id_lit.as_int = i32(proc_id);
			vm.add_push_literal(builder.bytecode, e.name.begin.line, 
				proc_id_lit);

			assert(builder.stack_ind <= 255);
			vm.add_call(builder.bytecode, e.name.begin.line, 
				u8(proc_arg_len), u8(builder.stack_ind));

			return proc_ref.ret;
		}


	case ast.Scope_Access:
		unimplemented("Scope access not implemented");

	case ast.Access_Identifier:
		name := lex.get_token_string(e.name, builder.lexer);
		decl, decl_ok := find_local_decl(builder, name);

		if !decl_ok
		{
			error(builder, e.name, "no variable of name\"", name, "\" exists");
			return 0;
		}
		else
		{
			assert(decl.index <= 255);
			vm.add_load_stack(builder.bytecode, e.name.begin.line, 
				u8(decl.index));
			return decl.var.type;
		}
	}

	//unreachable("How did we get here?");
	assert(false);
	return 0;
}
