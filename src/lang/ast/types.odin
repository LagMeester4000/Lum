package ast

import lex "../lexer"
import util "../../util"

import "core:mem"

// NOTE: once the parse function is done you can no longer insert
//   elements into any dynamic arrays in the ast
Ast :: struct 
{
	// Should be bound to context.allocator
	//allocator: util.Dynamic_Arena,
	//allocator: mem.Scratch_Allocator,
	allocator: mem.Arena,
	lexer: lex.Lexer,

	root: ^Block,

	current_token: lex.Token,
	current_token_index: int,
}

Ast_Resettable :: struct
{
	current_token: lex.Token,
	current_token_index: int,
}

destroy_ast :: proc(ast: ^Ast)
{
	//util.destroy_dynamic_arena(&ast.allocator);

	delete(ast.allocator.data);
	//mem.scratch_allocator_destroy(&ast.allocator);
}

Node :: struct
{
	start, end: lex.Pos,
	derived: any,
}

make_node :: proc($T: typeid) -> ^T
{
	ret := new(T);
	//ret.derived = ret;
	ret.derived.data = ret;
	ret.derived.id = T;
	return ret;
}

Proc_Argument :: struct
{
	using _: Node,
	name: lex.Token,
	type: ^Type_Sig,
}

Proc_Def :: struct 
{
	using _: Decl,
	name: lex.Token,
	arguments: [dynamic]^Proc_Argument,
	ret: ^Type_Sig,
	block: ^Block,
}

Struct_Def :: struct
{
	using _: Decl,
	name: lex.Token,
	fields: [dynamic]^Proc_Argument,
}

Type_Sig :: struct 
{
	using _: Node,
	name: lex.Token,
}

Block :: struct 
{
	using _: Stmt,
	exprs: [dynamic]^Stmt,
}

Stmt :: struct
{
	using _: Node,
}

Decl :: struct 
{
	using _: Stmt,
}

Expr :: struct 
{
	using _: Node,
}

Var_Decl :: struct 
{
	using _: Stmt,
	name: lex.Token,
	type: ^Type_Sig,
	assignment: ^Expr,
}

Binary_Expr :: struct 
{
	using _: Expr,
	left, right: ^Expr,
	operator: lex.Token,
}

Unary_Expr :: struct
{
	using _: Expr,
	operator: lex.Token,
	right: ^Expr,
}

Literal_Value :: struct
{
	using _: Expr,
	value: lex.Token,
}

Xary_Expr :: struct
{
	using _: Expr,
	//operator: lex.Token,
	operators: [dynamic]lex.Token,
	exprs: [dynamic]^Expr,
}

Call_Expr :: struct 
{
	using _: Expr,
	//function: ^Expr,
	name: lex.Token,
	arguments: [dynamic]^Expr,
}

Access_Identifier :: struct
{
	using _: Expr,
	name: lex.Token,
}

// Anything followed by a dot
Scope_Access :: struct
{
	using _: Expr,
	left: ^Expr,
	right: ^Expr,
}

Array_Access :: struct
{
	using _: Expr,
	expr: ^Expr,
}

If_Type :: enum { If, ElseIf, Else }

If :: struct 
{
	using _: Stmt,
	if_type: If_Type,
	condition: ^Expr,
	block: ^Block,
}

Return :: struct
{
	using _: Stmt,
	expr: ^Expr,
}

Break :: struct
{
	using _: Stmt,
}

Continue :: struct
{
	using _: Stmt,
}

// An expr that is in the spot of a statement
// Can only mean a limited amount of things:
//   - Function call
// This means it shoud be checked in the next phase
Stmt_Expr :: struct
{
	using _: Stmt,	
	expr: ^Expr,
}

Assign :: struct 
{
	using _: Stmt,
	assigned_to: ^Expr,
	value: ^Expr,
}

While_Loop :: struct
{
	using _: Stmt,
	expr: ^Expr,
	block: ^Block,
}

For_Loop :: struct
{
	using _: Stmt,
	init: ^Stmt,
	check: ^Expr,
	post_block: ^Stmt,
	block: ^Stmt,
}

For_Iterator :: struct
{
	using _: Stmt,
	it_name: lex.Token,
	container: ^Expr,
	block: ^Block,
}


