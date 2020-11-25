package vm

Vm :: struct
{
	bytecode: Bytecode,
	// Instruction pointer is stored on the odin stack

	// Expression stack
	stack: []Raw_Value,
	stack_ptr: i32,

	// Member stack
	// First x number of locals are reserved for function arguments
	locals_stack: []Raw_Value,
	locals_stack_frame: i32,

	call_stack: [dynamic]Call_Frame,

	// Allocator
	heap: []Raw_Value,
	// Temporary linear allocator
	heap_used: int,
}

make_vm :: proc(bytecode: Bytecode) -> Vm
{
	ret: Vm;
	ret.bytecode = bytecode;
	ret.stack = make([]Raw_Value, 1000);
	ret.locals_stack = make([]Raw_Value, 1000);
	ret.call_stack = make([dynamic]Call_Frame);
	ret.heap = make([]Raw_Value, 250000);
	return ret;
}

destroy_vm :: proc(vm: ^Vm)
{
	delete(vm.stack);
	delete(vm.locals_stack);
	delete(vm.call_stack);
	delete(vm.heap);
}

Call_Frame :: struct
{
	instruction: i32,
	// Points to the start of the stack frame
	locals_stack_frame: i32,
}

push_stack :: inline proc(vm: ^Vm, val: Raw_Value)
{
	vm.stack[vm.stack_ptr] = val;
	vm.stack_ptr += 1;
}

pop_stack :: inline proc(vm: ^Vm) -> Raw_Value
{
	vm.stack_ptr -= 1;
	return vm.stack[vm.stack_ptr];
}

run :: proc(vm: ^Vm)
{
	for i := 0; i < len(vm.bytecode.bytecode); i += 1
	{
		#partial switch cast(Opcode)vm.bytecode.bytecode[i]
		{
		case .No_Op:
			// Empty on purpose

		case .End:
			return;

		case .Return:
			// When a return instruction is called, a return value should be
			//   on the stack if the procedure returns something

			call_ind := len(vm.call_stack) - 1;
			if call_ind < 0 do return; // End of program

			call := vm.call_stack[call_ind];
			pop(&vm.call_stack);

			i = int(call.instruction);
			vm.locals_stack_frame = call.locals_stack_frame;

		case .Call:
			// Call instruction
			// 2 arguments: arg_count, current_locals_stack
			// x + 1 expression values: arg_values..., procedure_id
			//
			// current_locals_stack = amount of values used in the current 
			//   stack frame

			// Get argument count
			i += 1;
			//arg_count := vm.bytecode.consts[vm.bytecode.bytecode[i]];
			arg_count := vm.bytecode.bytecode[i];

			// Get current amount of locals used in the current proc
			i += 1;
			locals_index_byte := vm.bytecode.bytecode[i];
			//current_locals_stack := vm.bytecode.consts[locals_index_byte];
			//new_locals_stack_frame := vm.locals_stack_frame + current_locals_stack.as_int;
			new_locals_stack_frame := vm.locals_stack_frame + i32(locals_index_byte);

			// Procedure Id
			proc_id := pop_stack(vm);

			// Push call stack
			call: Call_Frame;
			call.instruction = i32(i);
			call.locals_stack_frame = vm.locals_stack_frame;
			append(&vm.call_stack, call);

			// Set new stack frame
			vm.locals_stack_frame = new_locals_stack_frame;

			// Copy over function arguments
			for arg := 0; arg < int(arg_count); arg += 1
			{
				// Reverse order because that's how they were pushed on the stack
				real_ind := int(arg_count) - arg - 1;
				arg_val := pop_stack(vm);
				vm.locals_stack[int(vm.locals_stack_frame) + real_ind] = arg_val;
			}

			// Set instruction
			i = int(vm.bytecode.procs[proc_id.as_int]);
			i -= 1;

		case .Cond_Jmp:
			cond := pop_stack(vm);
			i += 1;
			jmp_len := vm.bytecode.consts[vm.bytecode.bytecode[i]];

			if cond.as_bool
			{
				i += int(jmp_len.as_int);
				i -= 1; // Avoid for loop increment
			}

		case .Jump_If_False:
			expr := pop_stack(vm);
			ar: [2]u8;
			ar[0] = vm.bytecode.bytecode[i + 1];
			ar[1] = vm.bytecode.bytecode[i + 2];
			jump_val := transmute(u16)ar;
			i += 2;
			if !expr.as_bool
			{
				i += int(jump_val);
				i -= 1; // Avoid loop increment
			}

		case .Jump_Back_If_True:
			expr := pop_stack(vm);
			ar: [2]u8;
			ar[0] = vm.bytecode.bytecode[i + 1];
			ar[1] = vm.bytecode.bytecode[i + 2];
			jump_val := transmute(u16)ar;
			i += 2;
			if !expr.as_bool
			{
				i -= int(jump_val);
				i -= 1; // Avoid loop increment
			}

		case .Jump_Back:
			expr := pop_stack(vm);
			ar: [2]u8;
			ar[0] = vm.bytecode.bytecode[i + 1];
			ar[1] = vm.bytecode.bytecode[i + 2];
			jump_val := transmute(u16)ar;
			i += 2;
			i -= int(jump_val);
			i -= 1; // Avoid loop increment

		case .Literal:
			i += 1;
			lit := vm.bytecode.consts[vm.bytecode.bytecode[i]];
			push_stack(vm, lit);

		case .Load:
			ind := pop_stack(vm);
			push_stack(vm, vm.heap[ind.as_int]);

		case .Store:
			// TODO: how wil this work with values of multiple words?
			ind := pop_stack(vm);
			val := pop_stack(vm);
			vm.heap[ind.as_int] = val;

		case .Load_Stack:
			//ind := pop_stack(vm);
			i += 1;
			//ind := vm.bytecode.consts[vm.bytecode.bytecode[i]];
			ind := vm.bytecode.bytecode[i];
			push_stack(vm, vm.locals_stack
				[vm.locals_stack_frame + i32(ind)]);

		case .Store_Stack:
			//ind := pop_stack(vm);
			i += 1;
			//ind := vm.bytecode.consts[vm.bytecode.bytecode[i]];
			ind := vm.bytecode.bytecode[i];
			val := pop_stack(vm);
			vm.locals_stack[vm.locals_stack_frame + i32(ind)] = val;

		case .Allocate:
			i += 1;
			//word_count := vm.bytecode.consts[vm.bytecode.bytecode[i]];
			word_count := vm.bytecode.bytecode[i];
			ind := vm.heap_used;
			vm.heap_used += int(word_count);

			push: Raw_Value;
			push.as_int = i32(ind);
			push_stack(vm, push);

		case .Add_Int:
			left := pop_stack(vm);
			right := pop_stack(vm);
			val: Raw_Value;
			val.as_int = left.as_int + right.as_int;
			push_stack(vm, val);

		case .Sub_Int:
			left := pop_stack(vm);
			right := pop_stack(vm);
			val: Raw_Value;
			val.as_int = left.as_int - right.as_int;
			push_stack(vm, val);

		case .Mul_Int:
			left := pop_stack(vm);
			right := pop_stack(vm);
			val: Raw_Value;
			val.as_int = left.as_int * right.as_int;
			push_stack(vm, val);

		case .Div_Int:
			left := pop_stack(vm);
			right := pop_stack(vm);
			val: Raw_Value;
			val.as_int = left.as_int / right.as_int;
			push_stack(vm, val);

		case .Not:
			val := pop_stack(vm);
			val.as_bool = !val.as_bool;
			push_stack(vm, val);

		case .Inv_Int:
			val := pop_stack(vm);
			val.as_int = -val.as_int;
			push_stack(vm, val);

		case .Inv_Num:
			val := pop_stack(vm);
			val.as_num = -val.as_num;
			push_stack(vm, val);

		case .And:
			left := pop_stack(vm);
			right := pop_stack(vm);
			push: Raw_Value;
			push.as_bool = left.as_bool && right.as_bool;
			push_stack(vm, push);

		case .Or:
			left := pop_stack(vm);
			right := pop_stack(vm);
			push: Raw_Value;
			push.as_bool = left.as_bool || right.as_bool;
			push_stack(vm, push);

		case .Xor:
			// TODO:
			left := pop_stack(vm);
			right := pop_stack(vm);
			push: Raw_Value;
			push.as_bool = left.as_bool && right.as_bool;
			push_stack(vm, push);

		case .Print_Int:
			val := pop_stack(vm);
			fmt.println(val.as_int);

		case .Print_Num:
			val := pop_stack(vm);
			fmt.println(val.as_num);

		case .Print_Bool:
			val := pop_stack(vm);
			fmt.println(val.as_bool);

		}
	}
}

import "core:fmt"
print_bytecode :: proc(bc: ^Bytecode)
{
	i := 0;
	for i < len(bc.bytecode)
	{
		as_opcode := cast(Opcode)bc.bytecode[i];
		i += 1;

		fmt.print(i - 1, "");
		fmt.print(as_opcode);
		defer fmt.print("\n");

		print_bytes :: proc(bc: ^Bytecode, it: ^int, length: int)
		{
			for j := 0; j < length; j += 1
			{
				fmt.print("", bc.bytecode[it^]);
				it^ += 1;
			}
		}

		#partial switch as_opcode
		{
		case .Call: print_bytes(bc, &i, 2);
		case .Cond_Jmp: print_bytes(bc, &i, 1);
		case .Jump_If_False: print_bytes(bc, &i, 2);
		case .Jump_Back_If_True: print_bytes(bc, &i, 2);
		case .Jump_Back: print_bytes(bc, &i, 2);
		case .Literal: print_bytes(bc, &i, 1);
		case .Load: print_bytes(bc, &i, 1);
		case .Store: print_bytes(bc, &i, 1);
		case .Load_Stack: print_bytes(bc, &i, 1);
		case .Store_Stack: print_bytes(bc, &i, 1);
		case .Allocate: print_bytes(bc, &i, 1);
		//case .Cond_Jmp: print_bytes(bc, &i, 1);
		}
	}

	fmt.println("consts:");
	for con, con_i in bc.consts
	{
		fmt.println(con_i, "=", con.as_int);
	}
}