# test_golden.py
# Golden model tests — all 8 scenarios
# Run: python3 test_golden.py
# Exports vectors to vectors.json for SV testbench (Week 3-4)

import json
from cache_model import CacheModel, get_index, WORD_SIZE, OFFSET_BITS, INDEX_BITS

def run_tests():
    passed = 0
    failed = 0

    # ── Helper ─────────────────────────────────────────────
    def check(name, condition):
        nonlocal passed, failed
        if condition:
            print(f"  PASS: {name}")
            passed += 1
        else:
            print(f"  FAIL: {name}")
            failed += 1

    # ── Address builder ────────────────────────────────────
    # Build address from tag + index + word offset
    # C: addr = (tag << 10) | (index << 4) | (word_i * 4)
    def make_addr(tag, index, word_i=0):
        return (tag << (OFFSET_BITS + INDEX_BITS)) | (index << OFFSET_BITS) | (word_i * WORD_SIZE)

    print("=== Golden Model Tests ===\n")

    # ──────────────────────────────────────────────────────
    # SCENARIO 1: Read hit, no fault
    # Write a word, read it back → hit, no ECC flags
    # ──────────────────────────────────────────────────────
    print("1. Read hit, no fault")
    c = CacheModel()
    addr = make_addr(tag=5, index=0, word_i=0)
    c.write(addr, 0xDEADBEEF)
    data, hit, sec, ded = c.read(addr)
    check("data correct",  data == 0xDEADBEEF)
    check("hit",           hit  == True)
    check("no SEC",        sec  == 0)
    check("no DED",        ded  == 0)

    # ──────────────────────────────────────────────────────
    # SCENARIO 2: Read miss
    # Read address never written → miss, fill triggered
    # After fill, valid=1, tag matches
    # ──────────────────────────────────────────────────────
    print("\n2. Read miss → allocate + fill")
    c = CacheModel()
    addr = make_addr(tag=7, index=3, word_i=0)
    data, hit, sec, ded = c.read(addr)
    check("miss on cold read",    hit == False)
    check("line valid after fill", c.lines[3]['valid'] == 1)
    check("tag stored correctly",  c.lines[3]['tag']   == 7)

    # ──────────────────────────────────────────────────────
    # SCENARIO 3: Write hit — dirty bit set, no writeback yet
    # Write twice to same line → second write is a hit
    # dirty bit must be 1, memory must NOT be updated yet
    # ──────────────────────────────────────────────────────
    print("\n3. Write hit → dirty bit set, no writeback")
    c = CacheModel()
    addr = make_addr(tag=2, index=1, word_i=0)
    c.write(addr, 0xAAAAAAAA)          # miss → allocate
    hit = c.write(addr, 0xBBBBBBBB)   # hit → update in place
    check("second write is hit",  hit == True)
    check("dirty bit set",        c.lines[1]['dirty'] == 1)
    # memory should still have old value (0x0 since never explicitly written to mem)
    check("memory NOT updated yet", c.memory.get(addr & ~0xF, 0) == 0)

    # ──────────────────────────────────────────────────────
    # SCENARIO 4: Write miss → allocate first, then write
    # ──────────────────────────────────────────────────────
    print("\n4. Write miss → allocate then write")
    c = CacheModel()
    addr = make_addr(tag=9, index=2, word_i=1)
    hit = c.write(addr, 0x12345678)
    check("write miss",           hit == False)
    check("line valid after alloc", c.lines[2]['valid'] == 1)
    check("data written",         c.lines[2]['data'][1] == 0x12345678)
    check("dirty bit set",        c.lines[2]['dirty'] == 1)

    # ──────────────────────────────────────────────────────
    # SCENARIO 5: Dirty eviction
    # Fill index=0 with tag=1, write (dirty=1)
    # Access index=0 with tag=2 → conflict miss → writeback first
    # ──────────────────────────────────────────────────────
    print("\n5. Dirty eviction → writeback triggered")
    c = CacheModel()
    addr1 = make_addr(tag=1, index=0, word_i=0)
    addr2 = make_addr(tag=2, index=0, word_i=0)   # same index, different tag

    c.write(addr1, 0xCAFEBABE)         # fills index=0, tag=1, dirty=1
    check("dirty before eviction", c.lines[0]['dirty'] == 1)

    c.read(addr2)                      # conflict miss → should writeback tag=1 first
    # After eviction: memory at addr1 line should have 0xCAFEBABE
    wb_base = addr1 & ~0xF
    check("writeback happened",    c.memory.get(wb_base, None) == 0xCAFEBABE)
    check("new tag loaded",        c.lines[0]['tag'] == 2)

    # ──────────────────────────────────────────────────────
    # SCENARIO 6: Single-bit fault → SEC corrects it
    # Write word, inject 1-bit flip, read back
    # Expected: corrected data returned, sec=1, ded=0
    # ──────────────────────────────────────────────────────
    print("\n6. Single-bit fault → SEC correction")
    c = CacheModel()
    addr = make_addr(tag=3, index=4, word_i=0)
    c.write(addr, 0xDEADBEEF)
    c.inject_fault(addr, word_idx=0, bit_pos=7)       # flip bit 7 in word 0
    data, hit, sec, ded = c.read(addr)
    check("data corrected",  data == 0xDEADBEEF)
    check("SEC flag set",    sec  == 1)
    check("DED flag clear",  ded  == 0)

    # ──────────────────────────────────────────────────────
    # SCENARIO 7: Double-bit fault → DED detected
    # Inject 2-bit flip → cannot correct, ded=1
    # ──────────────────────────────────────────────────────
    print("\n7. Double-bit fault → DED detected")
    c = CacheModel()
    addr = make_addr(tag=4, index=5, word_i=0)
    c.write(addr, 0x12345678)
    c.inject_fault(addr, word_idx=0, bit_pos=3, double=True)
    data, hit, sec, ded = c.read(addr)
    check("SEC flag clear",  sec == 0)
    check("DED flag set",    ded == 1)

    # ──────────────────────────────────────────────────────
    # SCENARIO 8: Fault then hit → correction transparent
    # Inject fault, read once (corrects + scrubs), read again
    # Second read should be clean (sec=0, ded=0)
    # ──────────────────────────────────────────────────────
    print("\n8. Fault then hit → transparent correction + scrub")
    c = CacheModel()
    addr = make_addr(tag=6, index=6, word_i=2)
    c.write(addr, 0xABCDEF01)
    c.inject_fault(addr, word_idx=2, bit_pos=15)
    _, _, sec1, _ = c.read(addr)      # first read: corrects + scrubs
    _, _, sec2, _ = c.read(addr)      # second read: clean
    check("first read SEC=1",   sec1 == 1)
    check("second read SEC=0",  sec2 == 0)   # scrub worked

    # ──────────────────────────────────────────────────────
    # SUMMARY
    # ──────────────────────────────────────────────────────
    print(f"\n{'='*40}")
    print(f"Results: {passed} passed, {failed} failed")

    # ──────────────────────────────────────────────────────
    # EXPORT VECTORS
    # All logged operations saved to vectors.json
    # Week 3-4: SV testbench reads this and replays
    # ──────────────────────────────────────────────────────
    # Use the last cache instance's log as sample vectors
    # In practice you'd collect across all scenarios
    all_logs = []
    for scenario_log in [c.log]:
        all_logs.extend(scenario_log)

    with open("vectors.json", "w") as f:
        json.dump(all_logs, f, indent=2)
    print("Vectors exported to vectors.json")

if __name__ == "__main__":
    run_tests()
