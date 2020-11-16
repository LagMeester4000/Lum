package semantic

import ast "../ast"
import lex "../lexer"

import "core:fmt"
import "core:strings"
import "core:mem"

Type_Id :: int;
Proc_Id :: int;

Struct_Field :: struct
{
	name: string,
	type: Type_Id,
	// Possibly some tag data
}

Struct_Decl :: struct 
{
	name: string,
	fields: [dynamic]Struct_Field,
	body_node: ^ast.Struct_Def,
}

Builtin_Type :: enum
{
	NoType, // This type does not exist, used for type_id 0
	Int,
	Num,
	Bool,
	String,
	Array,
	Map,
}

// Used for:
//   - The default basic types
//   - Typedefs of basic types
//   - Specialization of basic types (map and array)
Basic_Type_Decl :: struct
{
	name: string,
	type: Builtin_Type,
	// Used for array/map
	subtype1, subtype2: Type_Id,
}

Type_Decl :: union
{
	Struct_Decl,
	Basic_Type_Decl,
}

Proc_Decl :: struct
{
	name: string,
	arguments: [dynamic]Var_Decl,
	ret: Type_Id,
	is_external: bool,
	body: Proc_Body, 
	body_node: ^ast.Proc_Def,
}

Global_Scope :: struct 
{
	type_table: [dynamic]Type_Decl,
	proc_table: [dynamic]Proc_Decl,
	scope: ^Scope, // For global variables (and eventually execution tree)
}

Analyzer :: struct 
{
	allocator: mem.Arena,
}

// TODO: add custom allocator to prevent leaks
make_global_scope :: proc() -> Global_Scope
{
	scope: Global_Scope;

	// Register baisc types
	register_type(&scope, Basic_Type_Decl {
		name = "__ERROR_TYPE",
		type = .NoType,
	});
	register_type(&scope, Basic_Type_Decl {
		name = "int",
		type = .Int,
	});
	register_type(&scope, Basic_Type_Decl {
		name = "num",
		type = .Num,
	});
	register_type(&scope, Basic_Type_Decl {
		name = "bool",
		type = .Bool,
	});
	register_type(&scope, Basic_Type_Decl {
		name = "string",
		type = .String,
	});

	return scope;
}

// TODO: add custom allocator to prevent leaks
analyze :: proc(glob: ^Global_Scope, root: ^ast.Block, lexer: ^lex.Lexer) 
{
	// What needs to happen:
	//
	// 1. Scan every root node for types (structs).
	// We can't go deeper into the structs because not all other types are known.
	//
	// 2. Go back into every type and link up the type_id's.
	// This will atleast make it so that a signature for each type exists.
	//
	// 3. Scan every root node for procs, and register the signature.
	// We know all the types, so now we can register all procedure declarations 
	//   and their return and argument types.
	// We won't scan the procedure bodies here yet, because not all procedure
	//   signatures are known yet.
	//
	// 4. Go back into every procedure body and make the executable tree.
	//

	scope := glob;
	scan_for_types(scope, root, lexer);
	link_up_types(scope, lexer);
	scan_for_procs(scope, root, lexer);
	build_proc_bodies(scope, lexer);
}

register_type :: proc(scope: ^Global_Scope, type: Type_Decl) -> Type_Id
{
	ind := len(scope.type_table);
	append(&scope.type_table, type);
	return cast(Type_Id)ind;
}

register_proc :: proc(scope: ^Global_Scope, proc_v: Proc_Decl) -> Proc_Id
{
	ind := len(scope.proc_table);
	append(&scope.proc_table, proc_v);
	return cast(Proc_Id)ind;
}

find_proc :: proc(scope: ^Global_Scope, procname: string) -> Proc_Id
{
	for p, i in &scope.proc_table
	{
		if p.name == procname do return Proc_Id(i);
	}
	return 0;
}

find_type :: proc(scope: ^Global_Scope, typename: string, print_error := true,
	loc := #caller_location) -> Type_Id
{
	for type, i in &scope.type_table
	{
		switch t in &type
		{
		case Struct_Decl:
			if t.name == typename
			{
				return i;
			}
		case Basic_Type_Decl:
			if t.name == typename
			{
				return i;
			}
		}
	}
	if print_error
	{
		fmt.println("Analyzer error: type", typename, "does not exist. loc=", loc);
	}
	return 0;
}

find_type_from_node :: proc(scope: ^Global_Scope, node: ^ast.Type_Sig,
	lexer: ^lex.Lexer) -> Type_Id
{
	name := lex.get_token_string(node.name, lexer);
	ret := find_type(scope, name, false);
	if ret == 0
	{
		fmt.println(args = { "Analyzer error (", node.name.begin.line, ":", 
			node.name.begin.char, ") could not find type: ", name }, sep = "");
	}	
	return ret;
}

any_ptr :: proc(any_v: any, $T: typeid) -> (ptr: ^T, ok: bool)
{
	_, any_ok := any_v.(T);
	if any_ok
	{
		return transmute(^T)any_v.data, true;
	}
	return nil, false;
}

// 1. Scan every root node for types (structs).
scan_for_types :: proc(scope: ^Global_Scope, node: ^ast.Block, lexer: ^lex.Lexer)
{
	if node == nil do return;
	block := node;
	//block, ok := &node.derived.(ast.Block);
	//block, ok := any_ptr(node.derived, ast.Block);
	//if !ok 
	//{
		//fmt.println("Analyzer error: root node is not a block");
		//return;
	//}

	for stmt in block.exprs
	{
		//as_struct, struct_ok := &stmt.derived.(ast.Struct_Def);
		as_struct, struct_ok := any_ptr(stmt.derived, ast.Struct_Def);
		if !struct_ok do continue;

		decl: Struct_Decl;
		decl.name = lex.get_token_string(as_struct.name, lexer);
		decl.body_node = as_struct;
		register_type(scope, decl);
	}
}

// 2. Go back into every type and link up the type_id's.
link_up_types :: proc(scope: ^Global_Scope, lexer: ^lex.Lexer)
{
	for type, i in &scope.type_table
	{
		switch v in &type
		{
		case Struct_Decl:
			// Parse the inside of the struct
			node := v.body_node;
			for proc_arg in node.fields
			{
				field: Struct_Field;
				field.name = lex.get_token_string(proc_arg.name, lexer);
				typename := lex.get_token_string(proc_arg.type.name, lexer);
				field.type = find_type(scope, typename);
				append(&v.fields, field);
			}

		case Basic_Type_Decl:
			// Nothing
			break;
		}
	}
}

// 3. Scan every root node for procs, and register the signature.
scan_for_procs :: proc(scope: ^Global_Scope, block: ^ast.Block, lexer: ^lex.Lexer)
{
	//block, ok := &node.derived.(ast.Block);
	//block, ok := any_ptr(node.derived, ast.Block);
	//if !ok
	//{
		//fmt.println("Analyzer error: root node is not a block");
	//}

	for stmt in block.exprs
	{
		//as_proc, proc_ok := &stmt.derived.(ast.Proc_Def);
		as_proc, proc_ok := any_ptr(stmt.derived, ast.Proc_Def);
		if !proc_ok do continue;

		decl: Proc_Decl;
		decl.name = lex.get_token_string(as_proc.name, lexer);
		decl.body_node = as_proc;

		// Parse arguments
		for arg in as_proc.arguments
		{
			push: Var_Decl;
			push.name = lex.get_token_string(arg.name, lexer);
			push.type = find_type_from_node(scope, arg.type, lexer);
			append(&decl.arguments, push);
		}

		// Return
		if as_proc.ret != nil
		{
			decl.ret = find_type_from_node(scope, as_proc.ret, lexer);
		}
		else
		{
			// Does not have a return type
			decl.ret = 0;
		}

		register_proc(scope, decl);
	}
}

// 4. Go back into every procedure body and make the executable tree.
build_proc_bodies :: proc(scope: ^Global_Scope, lexer: ^lex.Lexer)
{
	builder := Body_Builder {
		global_scope = scope,
	};
	
	for p in &scope.proc_table
	{
		if p.is_external do continue;

		builder.decl = &p;
		p.body.body = build_block(p.body_node.block, &builder, lexer);
	}
}
