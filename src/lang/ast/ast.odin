package ast

import lex "../lexer"
import util "../../util"

import "core:mem"
import "core:fmt"
import "core:runtime"
import "core:reflect"

parse :: proc(inp: string) -> Ast
{
	ret: Ast;

	//util.init_dynamic_arena(&ret.allocator, mem.kilobytes(4));
	//context.allocator = util.dynamic_arena_allocator(&ret.allocator);

	mem.init_arena(&ret.allocator, make([]byte, mem.megabytes(1)));
	context.allocator = mem.arena_allocator(&ret.allocator);
	//mem.scratch_allocator_init(&ret.allocator, mem.megabytes(1));
	//context.allocator = mem.scratch_allocator(&ret.allocator);

	ret.lexer = lex.lex(inp);
	ret.current_token_index = 0;
	ret.current_token = ret.lexer.tokens[0];
	//ret.root = parse_statement(&ret);
	//ret.root = cast(^Node)parse_block(&ret, true);
	ret.root = parse_block(&ret, true);
	return ret;
}

make_reset :: proc(ast: ^Ast) -> Ast_Resettable
{
	return Ast_Resettable {
		current_token = ast.current_token,
		current_token_index = ast.current_token_index,
	};
}

reset :: proc(ast: ^Ast, r: Ast_Resettable)
{
	ast.current_token = r.current_token;
	ast.current_token_index = r.current_token_index;
}

prev_token :: proc(ast: ^Ast) -> bool
{
	if ast.current_token_index == 0
	{
		return false;
	}
	ast.current_token_index -= 1;
	ast.current_token = ast.lexer.tokens[ast.current_token_index];
	return true;
}

next_token :: proc(ast: ^Ast) -> bool
{
	debug_token := ast.current_token;

	if ast.current_token.type == .EOF
	{
		return false;
	}
	ast.current_token_index += 1;
	ast.current_token = ast.lexer.tokens[ast.current_token_index];
	return true;
}

advance_token :: proc(ast: ^Ast) -> lex.Token
{
	prev := ast.current_token;
	next_token(ast);
	return prev;
}

// TODO: Error reporting
expect_token :: proc(ast: ^Ast, kind: lex.Token_Type, caller := #caller_location) -> lex.Token
{
	ret := advance_token(ast);
	if ret.type != kind
	{
		fmt.println(caller);
		fmt.println("Parse error(", ret.begin.line, ",", ret.begin.char, 
			"): expected", kind, ", got", ret.type);
	}
	return ret;
}

allow_token :: proc(ast: ^Ast, kind: lex.Token_Type) -> bool
{
	if kind == ast.current_token.type
	{
		next_token(ast);
		return true;
	}
	return false;
}

peek_token :: proc(ast: ^Ast, kind: lex.Token_Type, amount: int = 0) -> bool
{
	r := make_reset(ast);
	defer reset(ast, r);

	for i := 0; i <= amount; i += 1
	{
		next_token(ast);
	}

	return ast.current_token.type == kind;
}

// expr = logic
// logic = comp (&& comp)*
// comp = plus (> plus)*
// plus = mul (\+ mul)*
// mul = unary (\* unary)*
// unary = (\-)? content
// content = ( \( expr \) ) | identifier
// TODO: BUG whenever an expression with the same priority but differing
//   operators happen (like 5 * 3 / 2), it is only registered as the first
//   operator (like * in the example)
parse_expr :: proc(ast: ^Ast) -> ^Expr
{
	parse_logic :: proc(ast: ^Ast) -> ^Expr
	{
		parse_func :: parse_comp;
		check_operator :: proc(t: lex.Token_Type) -> bool 
		{ return t == .Key_And || t == .Key_Or; }
		initial := parse_func(ast);

		if check_operator(ast.current_token.type)
		{
			expr := make_node(Xary_Expr);
			//expr.operator = ast.current_token;
			append(&expr.operators, ast.current_token);
			append(&expr.exprs, initial);

			next_token(ast);
			for cond := true; 
				cond;
			{
				next := parse_func(ast);
				append(&expr.exprs, next);

				adv_token := advance_token(ast);
				cond = check_operator(adv_token.type);
				if cond do append(&expr.operators, adv_token);
			}
			prev_token(ast);

			return expr;
		}
		else
		{
			return initial;
		}
	}

	parse_comp :: proc(ast: ^Ast) -> ^Expr
	{
		parse_func :: parse_plus;
		check_operator :: proc(t: lex.Token_Type) -> bool 
		{ return t == .Equals_Equals || 
			t == .Greater_Equals || t == .Greater ||
			t == .Less_Equals || t == .Less; }
		initial := parse_func(ast);

		if check_operator(ast.current_token.type)
		{
			expr := make_node(Xary_Expr);
			//expr.operator = ast.current_token;
			append(&expr.operators, ast.current_token);
			append(&expr.exprs, initial);

			next_token(ast);
			for cond := true; 
				cond;
			{
				next := parse_func(ast);
				append(&expr.exprs, next);

				adv_token := advance_token(ast);
				cond = check_operator(adv_token.type);
				if cond do append(&expr.operators, adv_token);
			}
			prev_token(ast);

			return expr;
		}
		else
		{
			return initial;
		}
	}

	parse_plus :: proc(ast: ^Ast) -> ^Expr
	{
		parse_func :: parse_mul;
		check_operator :: proc(t: lex.Token_Type) -> bool 
		{ return t == .Plus || t == .Minus; }
		initial := parse_func(ast);

		if check_operator(ast.current_token.type)
		{
			expr := make_node(Xary_Expr);
			//expr.operator = ast.current_token;
			append(&expr.operators, ast.current_token);
			append(&expr.exprs, initial);

			next_token(ast);
			for cond := true; 
				cond;
			{
				next := parse_func(ast);
				append(&expr.exprs, next);

				adv_token := advance_token(ast);
				cond = check_operator(adv_token.type);
				if cond do append(&expr.operators, adv_token);
			}
			prev_token(ast);

			return expr;
		}
		else
		{
			return initial;
		}
	}

	parse_mul :: proc(ast: ^Ast) -> ^Expr
	{
		parse_func :: parse_unary;
		check_operator :: proc(t: lex.Token_Type) -> bool 
		{ return t == .Mul || t == .Div; }
		initial := parse_func(ast);

		if check_operator(ast.current_token.type)
		{
			expr := make_node(Xary_Expr);
			//expr.operator = ast.current_token;
			append(&expr.operators, ast.current_token);
			append(&expr.exprs, initial);

			next_token(ast);
			for cond := true; 
				cond;
			{
				next := parse_func(ast);
				append(&expr.exprs, next);

				adv_token := advance_token(ast);
				cond = check_operator(adv_token.type);
				if cond do append(&expr.operators, adv_token);
			}
			prev_token(ast);

			return expr;
		}
		else
		{
			return initial;
		}
	}

	// Dont change after this comment
	parse_unary :: proc(ast: ^Ast) -> ^Expr
	{
		if ast.current_token.type == .Minus
		{
			expr := make_node(Unary_Expr);
			expr.operator = ast.current_token;
			expr.right = parse_content(ast);
			return expr;
		}
		else
		{
			// Not a unary	
			return parse_content(ast);
		}
	}

	parse_content :: proc(ast: ^Ast) -> ^Expr
	{
		if allow_token(ast, .Paren_Open)
		{
			ret := parse_expr(ast);
			expect_token(ast, .Paren_Close);
			// TODO: Maybe this needs to be wrapped?
			return ret;
		}
		else
		{
			return parse_access(ast);
		}
	}

	return parse_logic(ast);
}

parse_access :: proc(ast: ^Ast) -> ^Expr
{
	#partial switch ast.current_token.type
	{
	case .Identifier:
		ident := advance_token(ast);
		// Can be: assignment, array access, function call, struct access

		// Scope
		if allow_token(ast, .Dot)
		{
			scope := make_node(Scope_Access);
			next_token(ast);
			name := make_node(Access_Identifier);
			name.name = ident;
			scope.left = name;
			right := parse_access(ast);
			scope.right = right;
			//expect_token(ast, .Semi_Colon);
			return scope;
		}
		else if allow_token(ast, .Paren_Open)
		{
			// Function call	
			call := make_node(Call_Expr);
			call.name = ident;

			if allow_token(ast, .Paren_Close)
			{
				return call;
			}
			else
			{
				expr := parse_expr(ast);
				if expr != nil
				{
					append(&call.arguments, expr);
					for allow_token(ast, .Comma)
					{
						expr = parse_expr(ast);
						if expr != nil
						{
							append(&call.arguments, expr);
						}
					}
				}

				expect_token(ast, .Paren_Close);
				return call;
			}
		}
		else
		{
			raw_ident := make_node(Access_Identifier);
			raw_ident.name = ident;
			return raw_ident;
		}

	case .Brack_Open:
		next_token(ast);
		access := make_node(Array_Access);
		access.expr = parse_expr(ast);
		expect_token(ast, .Brack_Close);
		return access;

	case .Int_Number,
		.Float_Number:
		lit := make_node(Literal_Value);
		lit.value = advance_token(ast);
		return lit;

	//case 
	}
	return nil;
}

// Parse a block with statements
parse_block :: proc(ast: ^Ast, root := false) -> ^Block
{
	if root == false do expect_token(ast, .Block_Open);
	block := make_node(Block);
	//if ast.current_token.type == .Block_Open
	{
		//next_token(ast);

		for 
		{
			reset_ast := make_reset(ast);
			push := parse_statement(ast);
			if push == nil
			{
				reset(ast, reset_ast);
			}
			else
			{
				append(&block.exprs, push);
			}

			// Do while
			if push == nil do break;
		}

		if root == false do expect_token(ast, .Block_Close);
	}
	return block;
}

parse_proc_argument :: proc(ast: ^Ast) -> ^Proc_Argument
{
	arg := make_node(Proc_Argument);
	arg.name = expect_token(ast, .Identifier);
	expect_token(ast, .Colon);
	arg.type = parse_type_sig(ast);
	return arg;
}

// Returns nil on invalid
parse_statement :: proc(ast: ^Ast) -> ^Stmt
{
	#partial switch ast.current_token.type
	{
	case .Block_Open:
		return parse_block(ast);

	case .Key_Var:
		var := make_node(Var_Decl);
		next_token(ast);
		var.name = expect_token(ast, .Identifier);
		//expect_token(ast, .Colon);
		//var.type = parse_type_sig(ast);

		// Optional specified type
		if allow_token(ast, .Colon)
		{
			var.type = parse_type_sig(ast);
		}

		// Assignment
		if allow_token(ast, .Equals)
		{
			var.assignment = parse_expr(ast);
			expect_token(ast, .Semi_Colon);
			return var;
		}
		else
		{
			expect_token(ast, .Semi_Colon);
			return var;
		}

	case .Key_Proc:
		proc_def := make_node(Proc_Def);
		next_token(ast);
		proc_def.name = expect_token(ast, .Identifier);
		expect_token(ast, .Paren_Open);

		// Arguments
		if allow_token(ast, .Paren_Close) == false
		{
			// Parentheses are not empty
			// param = identifier : identifier
			// arguments = param ( , param )*
			arg := parse_proc_argument(ast);
			append(&proc_def.arguments, arg);
			for allow_token(ast, .Comma)
			{
				arg = parse_proc_argument(ast);
				append(&proc_def.arguments, arg);
			}

			expect_token(ast, .Paren_Close);
		}

		// Return
		//if allow_token(ast, .Block_Open) == false
		if ast.current_token.type != .Block_Open
		{
			// There is a type
			proc_def.ret = parse_type_sig(ast);
		}

		// Parse block
		{
			proc_def.block = parse_block(ast);
		}

		return cast(^Stmt)proc_def;

	case .Key_Struct:
		struct_def := make_node(Struct_Def);
		next_token(ast);
		struct_def.name = expect_token(ast, .Identifier);
		expect_token(ast, .Block_Open);

		// Fields
		if allow_token(ast, .Block_Close) == false
		{
			// Block is not empty
			// param = identifier : identifier
			// arguments = param ( , param )*
			field := parse_proc_argument(ast);
			append(&struct_def.fields, field);
			for allow_token(ast, .Comma)
			{
				field = parse_proc_argument(ast);
				append(&struct_def.fields, field);
			}

			// Allow for optional comma after last field
			allow_token(ast, .Comma);
			expect_token(ast, .Block_Close);
		}

		return cast(^Stmt)struct_def;

	case .Key_If: 
		next_token(ast);
		if_node := make_node(If);
		if_node.if_type = .If;
		if_node.condition = parse_expr(ast);
		if_node.block = parse_block(ast);
		return if_node;

	case .Key_Elif:
		next_token(ast);
		if_node := make_node(If);
		if_node.if_type = .ElseIf;
		if_node.condition = parse_expr(ast);
		if_node.block = parse_block(ast);
		return if_node;

	case .Key_Else:
		next_token(ast);
		if_node := make_node(If);
		if_node.if_type = .Else;
		if_node.condition = nil;
		if_node.block = parse_block(ast);
		return if_node;

	case .Key_Return:
		next_token(ast);
		ret := make_node(Return);
		ret.expr = parse_expr(ast);
		expect_token(ast, .Semi_Colon);
		return ret;

	case .Key_Break:
		next_token(ast);
		br := make_node(Break);
		expect_token(ast, .Semi_Colon);
		return br;

	case .Key_Continue:
		next_token(ast);
		con := make_node(Continue);
		expect_token(ast, .Semi_Colon);
		return con;

	case .Key_While:
		next_token(ast);
		whi := make_node(While_Loop);
		whi.expr = parse_expr(ast);
		whi.block = parse_block(ast);
		return whi;

	case .Key_For:
		next_token(ast);

		// Can be normal (c) for, or iterator for
		//if ast.current_token.type == .Identifier
		if peek_token(ast, .Key_In, 1)
		{
			// Iterator for
			for_it := make_node(For_Iterator);
			for_it.it_name = expect_token(ast, .Identifier);
			expect_token(ast, .Key_In);
			for_it.container = parse_expr(ast);
			for_it.block = parse_block(ast);
			return for_it;
		}
		else
		{
			// C for
			for_c := make_node(For_Loop);
			for_c.init = parse_statement(ast);
			expect_token(ast, .Semi_Colon);
			for_c.check = parse_expr(ast);
			expect_token(ast, .Semi_Colon);
			for_c.post_block = parse_statement(ast);
			for_c.block = parse_block(ast);
			return for_c;
		}


	case .Identifier:
		// Can be eiter function call or assignment
		// No need to get the next token, it is needed for the expr
		// TODO: check for function call can actually be done inside the parser
		first_expr := parse_expr(ast);

		if allow_token(ast, .Equals)
		{
			// Assignment
			assign_expr := parse_expr(ast);
			expect_token(ast, .Semi_Colon);
			assign := make_node(Assign);
			assign.assigned_to = first_expr;
			assign.value = assign_expr;
			return assign;
		}
		else if allow_token(ast, .Semi_Colon)
		{
			// End
			stmt_expr := make_node(Stmt_Expr);
			stmt_expr.expr = first_expr;
			return stmt_expr;
		}
	}

	return nil;
}

parse_type_sig :: proc(ast: ^Ast) -> ^Type_Sig
{
	ret := make_node(Type_Sig);
	ret.name = expect_token(ast, .Identifier);
	return ret;
}

print :: proc(ast: ^Ast)
{
	fmt.println("ast:");
	_print(ast.root^);
	fmt.println();
}

_print :: proc(v: any, scope := 0)
{
	print_scope :: proc(sc: int)
	{
		for i in 0..<sc do fmt.print("    ");
	}

	type := runtime.type_info_base(type_info_of(v.id));
	val := any {
		data = v.data,
		id = type.id,
	};

	#partial switch info in type.variant
	{
	case runtime.Type_Info_Struct:
		names := reflect.struct_field_names(val.id);
		for name, debug_i in names
		{
			debug_i_confirm := debug_i;
			debug_name_confirm := name;

			//if name == "_" do continue;
			if name == "_" && len(names) > 1 do continue;

			field := reflect.struct_field_value_by_name(val, name, false);

			fmt.print(name, "{");
			fmt.println();
			print_scope(scope + 1);
			_print(field, scope + 1);
			fmt.println();
			print_scope(scope);
			fmt.print("} ");
			fmt.println();
			print_scope(scope);
		}

	case runtime.Type_Info_Pointer:
		/*
		point_val := any {
			id = info.elem.id,
			data = val.data,
		};
		_print(point_val, scope);
		*/
		real_val := cast(^rawptr)val.data;
		point_val := any {
			id = info.elem.id,
			data = real_val^,
		};
		if point_val.data == nil
		{
			fmt.print("nil");
		}
		else 
		{
			_print(point_val, scope);
		}

	case runtime.Type_Info_Any:
		any_casted := cast(^any)val.data;
		any_val := any {
			id = any_casted.id,
			data = any_casted.data,
		};
		_print(any_val, scope);

	case runtime.Type_Info_Dynamic_Array:
		raw_array := cast(^mem.Raw_Dynamic_Array)val.data;
		data := raw_array.data;
		len := raw_array.len;
		elem_size := info.elem_size;
		for i := 0; i < len; i += 1
		{
			elem := any {
				data = rawptr(uintptr(data) + uintptr(elem_size * i)),
				id = info.elem.id,
			};
			_print(elem, scope);
		}

	case: 
		fmt.print(val);
	}
}
