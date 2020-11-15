import math

pi = math.pi
fix_bit_pow = 65536

run = 1
res = fix_bit_pow * 3;
while run:
    if res / fix_bit_pow > pi:
        print(res)
        break
        
    res += 1
    