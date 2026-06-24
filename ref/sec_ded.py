# sec_ded.py
# SEC-DED ECC golden model for 32-bit data words
# Week 1 — Cache Controller Project
#
# C brain? Read every comment. Python-isms are marked with [PY]

# ─────────────────────────────────────────────
# BACKGROUND
# ─────────────────────────────────────────────
# For 32-bit data, SEC-DED needs:
#   - 6 Hamming parity bits (positions 1,2,4,8,16,32 in codeword)
#   - 1 overall parity bit (bit position 0, or appended as bit 39)
#   - Total: 32 data bits + 7 ECC bits = 39-bit codeword
#
# Codeword bit layout (1-indexed, Hamming convention):
#   pos:  1  2  3  4  5  6  7  8  9 10 11 ... 38 39
#         p1 p2 d1 p4 d2 d3 d4 p8 d5 d6 d7 ... d32 p_overall
#
# p1,p2,p4,p8,p16,p32 = Hamming check bits (powers of 2)
# d1..d32              = your 32 data bits
# p_overall            = XOR of ALL 39 bits (for DED)

# ─────────────────────────────────────────────
# HELPER: integer → list of bits, LSB firstx
# ─────────────────────────────────────────────
# C equivalent:
#   for(int i=0; i<width; i++) bits[i] = (n >> i) & 1;

def int_to_bits(n, width):
    # [PY] list comprehension = inline for loop that builds a list
    # same as: for i in range(width): result.append((n >> i) & 1)
    return [(n >> i) & 1 for i in range(width)]

def bits_to_int(bits):
    # [PY] enumerate(bits) gives (index, value) pairs
    # same as C: for(int i=0; i<len; i++) result |= bits[i] << i;
    result = 0
    for i, b in enumerate(bits):   # [PY] b = bits[i], i = index
        result |= (b << i)
    return result


# ─────────────────────────────────────────────
# STEP 1: Build the 39-bit codeword from 32-bit data
# ─────────────────────────────────────────────
# Place data bits into non-power-of-2 positions.
# Leave power-of-2 positions (1,2,4,8,16,32) as 0 for now.
# Then compute each parity bit.

def _build_codeword_positions(data_32b):
    """
    Returns a 39-element list (1-indexed via [0..38], pos = index+1).
    Positions 1,2,4,8,16,32 are Hamming check bits (filled later).
    Position 39 is overall parity (filled later).
    Data bits fill the rest.
    """
    # [PY] [0] * 39 = int arr[39] = {0}; in C
    codeword = [0] * 39

    data_bits = int_to_bits(data_32b, 32)

    # Walk codeword positions 1..38, skip powers of 2
    # Place data bits in order into the remaining slots
    data_idx = 0
    for pos in range(1, 39):              # pos = 1 to 38 inclusive
        if (pos & (pos - 1)) != 0:        # not a power of 2
            codeword[pos - 1] = data_bits[data_idx]   # [PY] 0-indexed list
            data_idx += 1

    return codeword   # parity positions still 0


def _compute_hamming_parity(codeword):
    """
    Fill in the 6 Hamming parity bits (positions 1,2,4,8,16,32).
    Each parity bit = XOR of all positions where that bit is set in pos index.

    Example: p1 (pos=1) covers all positions where bit0 of pos == 1
             → positions 1,3,5,7,9,11,...
    """
    codeword = codeword[:]   # [PY] copy the list (like memcpy), don't mutate input

    for r in range(6):                    # r = 0..5 → parity bit positions 1,2,4,8,16,32
        parity_pos = (1 << r)             # 1,2,4,8,16,32
        parity = 0
        for pos in range(1, 39):          # check all positions 1..38
            if pos == parity_pos:
                continue                  # skip the parity bit itself
            if (pos & parity_pos) != 0:   # does this position's index have bit r set?
                parity ^= codeword[pos - 1]
        codeword[parity_pos - 1] = parity

    return codeword


def _compute_overall_parity(codeword):
    """
    Position 39 = XOR of ALL other 38 bits.
    This is the +1 in SEC-DED. Enables distinguishing 1-bit vs 2-bit errors.
    """
    codeword = codeword[:]
    overall = 0
    for b in codeword[:38]:   # [PY] list slice, like codeword[0..37] in C
        overall ^= b
    codeword[38] = overall    # index 38 = position 39
    return codeword


# ─────────────────────────────────────────────
# PUBLIC API: encode
# ─────────────────────────────────────────────

def ecc_encode(data_32b):
    """
    Input : 32-bit integer (data word)
    Output: (data_32b, ecc_7b)
            ecc_7b = 7-bit integer packing [p1,p2,p4,p8,p16,p32,p_overall]

    In the cache: store ecc_7b alongside each 32-bit word.
    On fill from memory → encode. On read to CPU → decode.
    """
    cw = _build_codeword_positions(data_32b)
    cw = _compute_hamming_parity(cw)
    cw = _compute_overall_parity(cw)

    # Extract the 7 ECC bits from their positions in the codeword
    # Positions 1,2,4,8,16,32,39 → indices 0,1,3,7,15,31,38
    ecc_positions = [1, 2, 4, 8, 16, 32, 39]
    ecc_bits = [cw[p - 1] for p in ecc_positions]   # [PY] list comprehension

    ecc_7b = bits_to_int(ecc_bits)   # pack into integer for storage
    return (data_32b, ecc_7b)


# ─────────────────────────────────────────────
# PUBLIC API: decode
# ─────────────────────────────────────────────

def ecc_decode(data_32b, ecc_7b):
    """
    Input : data_32b (possibly corrupted), ecc_7b (stored at encode time)
    Output: (corrected_data, sec_flag, ded_flag)

    sec_flag = 1 → single bit error, was corrected
    ded_flag = 1 → double bit error, data unreliable (don't use)
    both 0      → no error
    """

    # Rebuild codeword from current (possibly corrupted) data + stored ECC
    cw = _build_codeword_positions(data_32b)

    # Re-insert stored ECC bits
    ecc_bits = int_to_bits(ecc_7b, 7)
    ecc_positions = [1, 2, 4, 8, 16, 32, 39]
    for i, pos in enumerate(ecc_positions):
        cw[pos - 1] = ecc_bits[i]

    # ── Compute syndrome ──────────────────────────────────────
    # Recompute each Hamming parity bit from the received codeword.
    # If it matches stored, syndrome bit = 0. Else = 1.
    # Syndrome value = binary address of the flipped bit.
    syndrome = 0
    for r in range(6):
        parity_pos = (1 << r)
        parity = 0
        for pos in range(1, 39):
            if (pos & parity_pos) != 0:
                parity ^= cw[pos - 1]
        if parity != 0:
            syndrome |= parity_pos   # set the r-th syndrome bit

    # ── Check overall parity ──────────────────────────────────
    overall = 0
    for b in cw:
        overall ^= b
    # After including p_overall in cw, overall should be 0 if no error

    # ── Classify ──────────────────────────────────────────────
    # overall==1, syndrome!=0 → odd number of errors → single bit error (SEC)
    # overall==0, syndrome!=0 → even number of errors → double bit error (DED)
    # overall==1, syndrome==0 → error only in overall parity bit itself (benign)
    # overall==0, syndrome==0 → no error

    sec_flag = 0
    ded_flag = 0
    corrected_data = data_32b

    if syndrome == 0 and overall == 0:
        pass   # clean, no action

    elif syndrome != 0 and overall == 1:
        # Single bit error — syndrome points to the flipped position
        sec_flag = 1
        cw[syndrome - 1] ^= 1   # flip the bit back

        # Re-extract corrected data from codeword
        data_bits = []
        for pos in range(1, 39):
            if (pos & (pos - 1)) != 0:   # non power-of-2 = data bit
                data_bits.append(cw[pos - 1])
        corrected_data = bits_to_int(data_bits)

    elif syndrome != 0 and overall == 0:
        # Double bit error — cannot correct, flag it
        ded_flag = 1

    # syndrome==0 and overall==1 → error in p_overall only, data fine
    # (sec_flag=0, ded_flag=0 is correct here — data uncorrupted)

    return (corrected_data, sec_flag, ded_flag)
# ─────────────────────────────────────────────
# UNIT TESTS — run this file directly to check
# ─────────────────────────────────────────────
# [PY] this block runs only when you do: python sec_ded.py
#      not when you import it from another file
#      C equivalent: if you put main() behind a flag

if __name__ == "__main__":

    print("=== SEC-DED Unit Tests ===\n")

    test_words = [0x00000000, 0xFFFFFFFF, 0xDEADBEEF, 0xA5A5A5A5, 0x00000001]

    for data in test_words:
        # ── Test 1: No error ──────────────────────────────────
        _, ecc = ecc_encode(data)
        corrected, sec, ded = ecc_decode(data, ecc)
        assert corrected == data and sec == 0 and ded == 0, \
            f"FAIL no-error test: data={hex(data)}"

        # ── Test 2: Single bit flip in data ───────────────────
        for bit in range(32):
            corrupted = data ^ (1 << bit)
            corrected, sec, ded = ecc_decode(corrupted, ecc)
            assert sec == 1 and ded == 0, \
                f"FAIL SEC test: data={hex(data)} bit={bit}"
            assert corrected == data, \
                f"FAIL correction: data={hex(data)} bit={bit} got={hex(corrected)}"

        # ── Test 3: Double bit flip ───────────────────────────
        corrupted = data ^ (1 << 0) ^ (1 << 1)
        corrected, sec, ded = ecc_decode(corrupted, ecc)
        assert ded == 1 and sec == 0, \
            f"FAIL DED test: data={hex(data)}"

        print(f"PASS: {hex(data)}")

    print("\nAll tests passed.")

