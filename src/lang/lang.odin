package lang

import "lexer"
import "ast"
import "semantic"

import "core:fmt"
import "core:os"

/* syntax:

struct MyStruct
{
	x: int,
	y: int,
}

proc main() int
{
	var v = 5;
	var r = 10;
	return v + r;
}

*/

parse_file_test :: proc(filename: string)
{
	fmt.println(filename, "parsing:");
	file, ok := os.read_entire_file(filename);
	defer if ok do delete(file);
	ast.parse(string(file));
	fmt.println();
}



test_lexer :: proc()
{
	source := 
`
proc myProc() {}
`;

	source2 := 
`
proc myProc() 
{ 
	var my_var: Thing = 5 + 10 + 8; 
}
`;
	
	if false
	{
		tokens := lexer.lex(source);
		defer delete(tokens.tokens);

		fmt.println();
		fmt.println();
		fmt.println("tokens from sauce: ", source);
		fmt.println(tokens);
		fmt.println();
		fmt.println();
	}

	// Test parser
	if false
	{
		ast_v := ast.parse(source2);
		//fmt.println(ast_v.root);

		print_node :: proc(n: ^ast.Node)
		{
			fmt.println(n.derived);
		}

		//print_node(ast_v.root);
		//ast.print(&ast_v);
	}

	if true
	{
		parse_file_test("resources/scripts/basic_proc.lum");
		parse_file_test("resources/scripts/parse_logic.lum");
	}

}
