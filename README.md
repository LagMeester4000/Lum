# Lum
Lum is a simple statically typed scripting language with a very specific domain written in Odin (which is a procedural language like c). Here are the requirements:

* It needs to be simple
  * Garbage collection
  * Not many features
  * No module system
* It needs to not waste memory
  * Static typing
  * Good defragmentation in gc
* The state of the virtual machine must be fully serializable
* It must be deterministic 
  * No floating point values, use fixed point values for decimals instead
* It must be reasonably fast, or optimizable
  * (though I won't be trying to make it as fast as possible right off the bat)

This code was ripped straight from another project, the structure needs to be refactored a bit.

Here is what the language is supposed to look like:

```zig
proc sum_of_vals() int
{
	// Variable declaration with inferred types
	var v = 5;
	var r = 10;
	
	return v + r;
}

// Simple procedure (function)
proc multiple_of_sqrt2(first_argument: num) num
{
	// Explicitly declared type
	var ret: num = sqrt(2) * first_argument;
	return ret;
}

struct Player
{
	x: num,
	y: num,
}

// This could be considered a "constructor"
proc make_player(x: num, y: num) Player
{
	// Create a new Player object (garbage collected object)
	var player = new(Player);
	player.x = x;
	player.y = y;
	return player;
}
```

For a more detailed example, look at `resources/main_example.lum`.