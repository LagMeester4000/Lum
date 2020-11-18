package semantic
// This file contains functions that build the body of procedures

import lex "../lexer"
import ast "../ast"

import "core:fmt"
import "core:strconv"

error :: proc(token: lex.Token, message: ..any)
{
	fmt.print(args = { "(", token.begin.line, ":", token.end.char, 
		") Analyzer error: " }, sep = "");
	fmt.print(args = message, sep = "");
	fmt.print("\n");
}

type_name :: proc(id: Type_Id, builder: ^Body_Builder) -> string
{
	t := builder.global_scope.type_table[id];
	switch tv in t
	{
	case Basic_Type_Decl:
		return tv.name;
	case Struct_Decl:
		return tv.name;
	}
	return "";
}

declare_var :: proc(scope: ^Scope, var: Var_Decl) -> Var_Handle
{
	var_ind := len(scope.decls);
	append(&scope.decls, var);
	// Is this really supposed to be here?
	//new_sym := new(Symbol);
	//new_sym^ = var;
	//append(&scope.symbols, new_sym);

	// Make var handle
	ret: Var_Handle;
	ret.reg_type = .Scope;
	ret.scope_depth = 0;
	ret.index = var_ind;
}

// TODO: Improve error handling
//   The function could return an error code if a variable has been declared
//   before, or if it's overriding a parameter.
//   ACTUALLY this should be a problem addressed in the variable declaration,
//   not variable access.
find_var :: proc(builder: ^Body_Builder, name: string) 
	-> (val: Var_Handle, ok: bool)
{
	scope_len := len(builder.scope_stack);
	if scope_len == 0
	{
		// Might need to be changed for global variable expessions
		unreachable("tried to find variable without existance of a scope");
	}

	// Check function scopes
	for normal_i := 0; normal_i < scope_len; normal_i += 1
	{
		i := scope_len - 1 - normal_i;
		scope := builder.scope_stack[i];
		for decl, decl_i in &scope.decls
		{
			if decl.name == name
			{
				// Calculate handle
				ret: Var_Handle;
				ret.reg_type = .Scope;
				ret.scope_depth = u16(normal_i);
				ret.index = u32(decl_i);
				return ret, true;
			}
		}
	}

	// Check parameters
	// Needs to be done after scope because it is before first scope (but after
	//   global scope)
	for param, param_i in &builder.decl.arguments
	{
		if param.name == name
		{
			// Calculate handle
			ret: Var_Handle;
			ret.reg_type = .Param;
			ret.scope_depth = 0;
			ret.index = u32(param_i);
			return ret, true;
		}
	}

	// Check global scope
	// Unimplemented for now

	return {}, false;
}

get_var :: proc(builder: ^Body_Builder, handle: Var_Handle) 
	-> (val: Var_Decl, ok: bool)
{
	switch handle.reg_type
	{
	case .None, .Known:
		return {}, false;

	case .Global, .Field:
		unimplemented("Global and field access not implemented yet");

	case .Scope:
		scope_len := len(builder.scope_stack);
		return builder.scope_stack[scope_len - 1 - int(handle.scope_depth)]
			.decls[handle.index], true;

	case .Param:
		return builder.decl.arguments[handle.index], true;

	}

	return {}, false;
}

build_body :: proc(procedure: ^Proc_Decl, glob_scope: ^Global_Scope, 
	lexer: ^lex.Lexer)
{
	builder: Body_Builder;
	builder.decl = procedure;

	build_block(procedure.body_node.block, &builder, lexer);
}

// Checks the correctness of an if statement just created
// The caller should keep a pointer to the previous symbol, which should not be
//   updated if this function returns false
// old_sym: ^Symbol = nil;
// for true
// {
// 	   sym := build_statement(...);
// 	   if !check_if_correctness(...) do old_sym = sym;
// }
check_if_correctness :: proc(new_sym, prev_sym: ^Symbol, 
	builder: ^Body_Builder, lexer: ^lex.Lexer) -> (ok: bool)
{
	if_error := false;
	as_cond, is_cond := new_sym.(Condition_Branch);
	if is_cond
	{
		if prev_sym != nil
		{
			old_as_cond, old_is_cond := prev_sym.(Condition_Branch);
			if old_is_cond
			{
				if as_cond.if_type == .ElseIf && 
					old_as_cond.if_type == .Else
				{
					error({}, "Cannot have an elif statement after an else statement");
					if_error = true;
				}
			}
		}
		else
		{
			// Cannot be else or elseif
			if as_cond.if_type == .ElseIf ||
				as_cond.if_type == .Else
			{
				error({}, "The first statement cannot be an elif or else statement");
				if_error = true;
			}
		}
	}
	return if_error;
}

build_block :: proc(block: ^ast.Block, builder: ^Body_Builder, lexer: ^lex.Lexer)
	-> ^Symbol
{
	this_scope: Scope;
	append(&builder.scope_stack, &this_scope);
	defer pop(&builder.scope_stack);

	prev_sym: ^Symbol = nil;

	for stmt in &block.exprs
	{
		sym := build_statement(stmt, builder, lexer);
		append(&this_scope.symbols, sym);

		// Special check needs to be performed if it's an if statement
		// This seems like an ugly hack but I could not find any other
		//   way to check for errors in the if statements
		if !check_if_correctness(sym, prev_sym, builder, lexer) do prev_sym = sym;
	}

	ret := new(Symbol);
	ret^ = this_scope;
	return ret;
}

current_scope :: proc(builder: ^Body_Builder) -> ^Scope
{
	return builder.scope_stack[len(builder.scope_stack) - 1];
}

build_statement :: proc(statement: ^ast.Stmt, builder: ^Body_Builder, 
	lexer: ^lex.Lexer) -> ^Symbol
{
	switch s in &statement.derived
	{
	//case Decl:
	case ast.Block:
		return build_block(&s, builder, lexer);

	case ast.Var_Decl:
		dec: Var_Decl;
		dec.name = lex.get_token_string(s.name, lexer);

		if s.type != nil
		{
			// Type is given
			dec.type = find_type_from_node(builder.global_scope, s.type, lexer);
			declare_var(current_scope(builder), dec);
			ret := new(Symbol);
			ret^ = dec;
			return ret;
		}
		else
		{
			// Type is inferred
			if s.assignment == nil 
			{
				unreachable("variable declaration both has no type and no assignment");
			}
			expr := build_expr(s.assignment, builder, lexer, true);
			dec.type = expr.resulting_type;
			decl_var_handle := declare_var(current_scope(builder), dec);

			decl_assign: Var_Decl_Assign;
			decl_assign.decl = dec;
			decl_assign.handle = decl_var_handle;
			decl_assign.expr = expr;
			ret := new(Symbol);
			ret^ = decl_assign;
			return ret;
		}

	case ast.If:
		if s.if_type == .Else
		{
			// No expr
			branch: Condition_Branch;
			branch.if_type = s.if_type;
			branch.block = build_block(s.block, builder, lexer);
			branch.expr = nil;
			ret := new(Symbol);
			ret^ = branch;
			return ret;
		}
		else
		{
			// Common case
			branch: Condition_Branch;
			branch.if_type = s.if_type;
			branch.expr = build_expr(s.condition, builder, lexer);
			branch.block = build_block(s.block, builder, lexer);
			ret := new(Symbol);
			ret^ = branch;
			return ret;
		}

	case ast.Return:
		retur: Return;
		retur.expr = build_expr(s.expr, builder, lexer);
		ret := new(Symbol);
		ret^ = retur;
		return ret;

	case ast.Break:
		ret := new(Symbol);
		ret^ = Break{};
		return ret;

	case ast.Continue:
		ret := new(Symbol);
		ret^ = Continue{};
		return ret;

	case ast.Stmt_Expr:
		// Check for function call
		expr := build_expr(s.expr, builder, lexer);

		// Expect function
		{
			//func: Function_Call;
			as_access, access_ok := expr.variant.(Access_Chain);
			if !access_ok
			{
				error({}, "Loose expression is not a procedure call");
			}
			else
			{
				if len(as_access.chain) > 1
				{
					error({}, "Scoped procedure calls do not exist (yet)");
				}
				else
				{
					ac := as_access.chain[0];
					as_function_call, function_call_ok := ac.(Function_Call);
					if !function_call_ok
					{
						error({}, "Loose access is not a procedure call");
					}
					else
					{
						// Success case
						ret := new(Symbol);
						ret^ = as_function_call;
						return ret;
					}
				}
			}
		}

	case ast.Assign:
		assign: Assignment;

		// Make assignee
		{
			assign.assigned_to = build_expr(s.assigned_to, builder, lexer);
			is_access, access_ok := assign.assigned_to.variant.(Access_Chain);
			if !access_ok
			{
				error({}, "Left hand side of assignment is not a variable");
			}
		}

		// Make expr and check type
		{
			assign.value = build_expr(s.value, builder, lexer);
			if assign.value.resulting_type != assign.assigned_to.resulting_type
			{
				// TODO: type conversion on assignment
				error({}, "Cannot convert type ", 
					type_name(assign.value.resulting_type, builder), 
					" to type", 
					type_name(assign.assigned_to.resulting_type, builder));
			}
		}

		ret := new(Symbol);
		ret^ = assign;
		return ret;

	case ast.While_Loop:
	case ast.For_Loop:
	case ast.For_Iterator:

	}

	return {};
}

build_var_decl :: proc(decl: ^ast.Var_Decl, builder: ^Body_Builder, 
	lexer: ^lex.Lexer) -> ^Symbol
{
	return {};
}

get_expr_type :: proc(expr: ^Expression, builder: ^Body_Builder) -> Type_Id
{
	if expr.resulting_type != 0
	{
		return expr.resulting_type;
	}

	// Calculate the type
	switch v in &expr.variant
	{
	case Access_Chain:
		// For now I will only handle cases where the access is one layer deep
		if len(v.chain) > 1 || len(v.chain) == 0
		{
			error({}, "The access chain is too long, only chains of size 1 are", 
				" allowed at the moment.");
		}

		elem := &v.chain[0];
		// I cannot use &elem here, this might be a problem?
		switch e in elem
		{
		case Var_Handle:
			var, ok := get_var(builder, e);
			if !ok
			{
				return 0;
			}
			expr.resulting_type = var.type;
			return var.type;

		case Function_Call:
			//
			id := e.procedure;
			proc_obj := builder.global_scope.proc_table[id];
			expr.resulting_type = proc_obj.ret;
			return proc_obj.ret;

		case Array_Access:
			// Unimplemented for now
			return 0;
		}

	case Literal:
		switch raw in v
		{
		case i32: 
			expr.resulting_type = find_type(builder.global_scope, "int");
		case f32:
			expr.resulting_type = find_type(builder.global_scope, "num");
		case string: 
			expr.resulting_type = find_type(builder.global_scope, "string");
		case bool: 
			expr.resulting_type = find_type(builder.global_scope, "bool");
		}
		return expr.resulting_type;

	case Xary_Expression:
		// Resulting type may depend on the type of operation used
		// An int can be added to a string, resulting in a string
		// Some rules are applied to avoid loss of data
		// An int can be added to a float, resulting in a float
		// TODO: add compile error when operator is not compatible with type (string)
		ranking_operator := v.operators[0];

		int_type := find_type(builder.global_scope, "int");
		num_type := find_type(builder.global_scope, "num");
		string_type := find_type(builder.global_scope, "string");
		bool_type := find_type(builder.global_scope, "bool");

		i_type := get_expr_type(v.expressions[0], builder);
		for i in 0..<len(v.operators)
		{
			expr_index := i + 1;
			new_type := get_expr_type(v.expressions[expr_index], builder);

			if  (new_type == num_type && i_type == int_type) ||
				(new_type == int_type && i_type == num_type)
			{
				i_type = num_type;
			}
			else if new_type == i_type && (new_type == int_type || 
				new_type == num_type || new_type == bool_type || 
				new_type == string_type)
			{
				// This is ok
			}
			else if (new_type == num_type || new_type == int_type) &&
				i_type == string_type
			{
				// This is ok
				i_type = string_type;
			}
			else if (i_type == num_type || i_type == int_type || 
				i_type == bool_type) &&
				new_type == string_type
			{
				// This is not allowed
				error({}, "When appending numbers or bools to a string in an",
					"expression, the expression must start with a string literal");
			}
			else
			{
				// Not allowed
				error({}, "Type ", i_type, " cannot be operated on with type ", 
					new_type, ".");
			}
		}

	case Unary_Expression:
		break;

	}

	// Error
	return 0;
}


build_expr :: proc(expr: ^ast.Expr, builder: ^Body_Builder, 
	lexer: ^lex.Lexer, is_root := false) -> ^Expression
{
	token_to_operator :: proc(token: lex.Token) -> Operator
	{
		#partial switch token.type
		{
		case .Minus: return .Minus;
		case .Plus: return .Plus;
		case .Mul: return .Multiply;
		case .Div: return .Divide;
		case .Key_And: return .And;
		case .Key_Or: return .Or;
		case .Key_Xor: return .Xor;
		case .Key_Not: return .Not;
		case .Equals_Equals: return .Equals_Equals;
		case .Equals: return .Equals;
		case .Greater_Equals: return .Greater_Equals;
		case .Greater: return .Greater;
		case .Less_Equals: return .Less_Equals;
		case .Less: return .Less;
		}
		return .Error;
	}

	ret := new(Expression);

	switch e in &expr.derived 
	{
	case ast.Binary_Expr:
		unimplemented("This should not exist");

	case ast.Unary_Expr:
		un: Unary_Expression;
		un.operator = token_to_operator(e.operator);
		un.expression = build_expr(e.right, builder, lexer);
		ret.variant = un;

	case ast.Xary_Expr:
		xar: Xary_Expression;
		for op in &e.operators
		{
			append(&xar.operators, token_to_operator(op));
		}
		for ex in &e.exprs
		{
			append(&xar.expressions, build_expr(ex, builder, lexer));
		}

	case ast.Literal_Value:
		token := e.value;
		lit: Literal;

		#partial switch token.type
		{
		case .Int_Number:
			num, ok := strconv.parse_i64(lex.get_token_string(token, lexer));
			lit = i32(num);
			ret.resulting_type = find_type(builder.global_scope, "int");

		case .Float_Number:	
			// TODO: unfinished
			num, ok := strconv.parse_i64(lex.get_token_string(token, lexer));
			lit = f32(num);
			ret.resulting_type = find_type(builder.global_scope, "num");

		case .String_Literal:
			lit = lex.get_token_string(token, lexer);
			ret.resulting_type = find_type(builder.global_scope, "string");

		case .True:
			lit = true;
			ret.resulting_type = find_type(builder.global_scope, "bool");

		case .False:
			lit = false;
			ret.resulting_type = find_type(builder.global_scope, "bool");

		case: 
			unreachable("Should not be possible");
		}

		ret.variant = lit;

	case ast.Call_Expr: 
		// Idk if this acually happens
		//panic("ast.Call_Expr exists here");
		// It does happen
		call: Function_Call;

		// Find proc
		proc_string := lex.get_token_string(e.name, lexer);
		call.procedure = find_proc(builder.global_scope, proc_string);

		// Check if the argument count lines up
		arg_count := len(e.arguments);
		proc_decl := builder.global_scope.proc_table[call.procedure];
		real_arg_count := len(proc_decl.arguments);
		if arg_count != real_arg_count
		{
			error({}, "Function called with incorrect amount of arguments.");
			break;
		}

		for arg, arg_i in e.arguments
		{
			arg_expr := build_expr(arg, builder, lexer);
			append(&call.arguments, arg_expr);

			real_arg_type := proc_decl.arguments[arg_i].type;
			if real_arg_type != arg_expr.resulting_type
			{
				error({}, "Expected type ", real_arg_type, " got type ", 
					arg_expr.resulting_type);
			}
		}

		chain: Access_Chain;
		append(&chain.chain, call);
		ret.variant = chain;

	case ast.Access_Identifier:
		ref_var_name := lex.get_token_string(e.name, lexer);
		ref_var, ok := find_var(builder, ref_var_name);
		if !ok
		{
			error(e.name, "Could not find local variable named ", ref_var_name,
				".");
		}

		chain: Access_Chain;
		append(&chain.chain, ref_var);
		ret.variant = chain;

	case ast.Scope_Access:
		// TODO: unimplemented
		unimplemented("I don't want to do this right now");

	case ast.Array_Access:
		unreachable("raw array access");

	case ast.Assign:
		// TODO: unimplemented
		unimplemented("I don't want to do this right now");
	}

	//if is_root
	if true
	{
		// If this is the root expression, initiate the 
		// ...? the what? finish your sentence
		// TODO: finish the sentence
		// If this is the root expression, find the type for the expression
		// I actually think this should be done either way, since it is cached
		//   in the expression, it doesn't cost anything to call multiple times

		// This will also calculate/cache the type
		get_expr_type(ret, builder);
	}

	return ret;
}