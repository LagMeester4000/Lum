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

declare_var :: proc(scope: ^Scope, var: Var_Decl)
{
	append(&scope.decls, var);
	new_sym := new(Symbol);
	new_sym^ = var;
	append(&scope.symbols, new_sym);
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
}

build_block :: proc(block: ^ast.Block, builder: ^Body_Builder, lexer: ^lex.Lexer)
	-> ^Symbol
{
	this_scope: Scope;
	append(&builder.scope_stack, &this_scope);
	defer pop(&builder.scope_stack);

	for stmt in &block.exprs
	{
		sym := build_statement(stmt, builder, lexer);
		append(&this_scope.symbols, sym);
	}

	ret := new(Symbol);
	ret^ = this_scope;
	return ret;
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


	case ast.Assign: // Actually an expression, but held by something else?
	case ast.If:
	case ast.Return:
	case ast.Break:
	case ast.Continue:
	case ast.Stmt_Expr:
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

	case ast.Access_Identifier:

	case ast.Scope_Access:

	case ast.Array_Access:

	case ast.Assign:

	}

	if is_root
	{
		// If this is the root expression, initiate the 
	}

	return {};
}