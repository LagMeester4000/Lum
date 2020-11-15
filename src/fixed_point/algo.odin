package fixed_point

sqrt :: proc(v: fp) -> fp
{
    if v <= 0
    {
        return 0;
    }

    num: fp_up = fp_up(v) * FRACTION_BITS_POW;
    res: fp_up = 0;

    for bit: fp_up = fp_up(1) << u64((find_highest_bit(fp_up(v)) + FRACTION_BITS) / 2 * 2); bit != 0; bit >>= 2
    {
        val: fp_up = res + bit;
        res >>= 1;
        if num >= val
        {
            num -= val;
            res += bit;
        }
    }

    if num > res
    {
        res += 1;
    }

    return fp(res);
}

// Returs the index of the most significant bit
find_highest_bit :: proc(v: fp_up) -> u64
{
    max_count: u64 = (size_of(fp_up) - 1) * 8;
    max := fp_up(1) << (max_count);

    count: u64 = max_count;
    for i := max; i != 0; i >>= 1
    {
        if (v & i) != 0
        {
            return count;
        }
        
        count -= 1;
    }
    return 0;

}

fmod :: proc(l, r: fp) -> fp
{
    return l % r;
}

sin :: proc(v: fp) -> fp
{
    x: fp = fmod(v, TWO_PI);
    x = div_fp(x, HALF_PI);

    if x < 0
    {
        x += make_fp(4);
    }

    sign: i32 = 1;
    if x > make_fp(2)
    {
        sign = -1;
        x -= make_fp(2);
    }

    if x > make_fp(1)
    {
        x = make_fp(2) - x;
    }

    x2: fp = mul_fp(x, x);
    //return sign * x * (PI - x2 * (TWO_PI - make_fp(5) - x2 * (PI - make_fp(3)))) / make_fp(2);
    return div_fp
        (mul_fp_var
            (make_fp(sign), x, PI - mul_fp(x2, TWO_PI - make_fp(5) - mul_fp(x2, PI - make_fp(3)) )), 
            make_fp(2));
}

cos :: proc(v: fp) -> fp
{
    return sin(HALF_PI + v);
}

// Returns 0 on invalid input
tan :: proc(v: fp)-> fp
{
    cv := cos(v);
    //assert(cx > 1);
    if cv > 1 do return 0;
    return sin(v) / cv;
}

to_float :: proc(v: fp) -> f32
{
    return f32(v) / f32(FRACTION_BITS_POW);
}

abs :: proc(v: fp) -> fp
{
    if v < 0 do return -v;
    return v;
}

len :: proc(v: Vec2) -> fp
{
    return sqrt(add(mul(v.x, v.x), mul(v.y, v.y)));
}

distance :: proc(p1, p2: Vec2) -> fp
{
    return len(sub(p2, p1));
}

import "core:fmt";
test :: proc()
{
    print :: proc(name: string, v: fp) { fmt.println(name); fmt.println(to_float(v)); };
    print_int :: proc(name: string, v: i64) { fmt.println(name); fmt.println(v) };

    // Sqrt
    {
        // Highest bit
        bit_thing := fp_up(5000);
        print_int("highest_bit", cast(i64)find_highest_bit(bit_thing));

        v := make_fp(2);
        print("sqrt of 2", sqrt(v));
    }

    // Sin
    {
        v := make_fp(2);
        print("sin of 2", sin(v));
    }
}
