package fixed_point

fp :: distinct i32;
fp_up :: i64;
FRACTION_BITS :: 16;
FRACTION_BITS_POW :: 65_536;

make_fp_whole :: inline proc(val: i32) -> fp
{
    return fp(val) * FRACTION_BITS_POW;
}

// Make an fp fraction out of 100
// make_fp_frac_100(1, 25) == 1.25
make_fp_frac_100 :: inline proc(whole, frac: i32) -> fp
{
    return fp(whole) * FRACTION_BITS_POW + (FRACTION_BITS_POW * fp(frac) / 100);
}

make_fp :: proc{ make_fp_whole, make_fp_frac_100 };

add_fp :: inline proc(l, r: fp) -> fp
{
    return l + r;
}

add_fp_var :: inline proc(v: ..fp) -> fp
{
    ret: fp;
    for val in v
    {
        ret += val;
    }
    return ret;
}

add :: proc { add_fp, add_fp_var, add_vec };

sub_fp :: inline proc(l, r: fp) -> fp
{
    return l + r;
}

sub :: proc { sub_fp, sub_vec };

mul_fp :: inline proc(l, r: fp) -> fp
{
    l_up := fp_up(l);
    r_up := fp_up(r);
    ret := l_up * r_up;
    // I hope this gets optimized into a shift
    ret /= FRACTION_BITS_POW;
    return fp(ret);
}

mul_fp_var :: inline proc(v: ..fp) -> fp
{
    ret: fp = FRACTION_BITS_POW;
    for val in v
    {
        ret = mul_fp(ret, val);
    }
    return ret;
}

mul :: proc { mul_fp, mul_fp_var, mul_vec, mul_vec_fp };

div_fp :: inline proc(l, r: fp) -> fp
{
    l_up := fp_up(l);
    l_up *= FRACTION_BITS_POW;
    r_up := fp_up(r);
    return fp(l_up / r_up);
}

div :: proc { div_fp, div_vec, div_vec_fp };

Vec2 :: struct
{
    x, y: fp,
}

add_vec :: proc(l, r: Vec2) -> Vec2
{
    return { add_fp(l.x, r.x), add_fp(l.y, r.y) };
}

sub_vec :: proc(l, r: Vec2) -> Vec2
{
    return { sub_fp(l.x, r.x), sub_fp(l.y, r.y) };
}

mul_vec :: proc(l, r: Vec2) -> Vec2
{
    return { mul_fp(l.x, r.x), mul_fp(l.y, r.y) };
}

mul_vec_fp :: proc(l: Vec2, r: fp) -> Vec2
{
    return { mul_fp(l.x, r), mul_fp(l.y, r) };
}

div_vec :: proc(l, r: Vec2) -> Vec2
{
    return { div_fp(l.x, r.x), div_fp(l.y, r.y) };
}

div_vec_fp :: proc(l: Vec2, r: fp) -> Vec2
{
    return { div_fp(l.x, r), div_fp(l.y, r) };
}

dot :: proc(l, r: Vec2) -> fp
{
    return add_fp(mul_fp(l.x, r.x), mul_fp(l.y, r.y));
}
