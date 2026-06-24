 # SEC-DED ECC-Hardened L1 Cache Controller

A direct-mapped, write-back, write-allocate L1 cache controller in SystemVerilog with hardware SEC-DED ECC per word and an integrated scrub state. Simulated and verified in Vivado xsim.

---

## Specs

| Parameter | Value |
|-----------|-------|
| Cache size | 1 KB |
| Line size | 16 B (4 × 32-bit words) |
| Sets | 64 (direct-mapped) |
| Write policy | Write-back, write-allocate |
| ECC | SEC-DED per 32-bit word (7-bit Hamming) |
| FSM states | IDLE → COMPARE → WRITEBACK → ALLOCATE → DONE → SCRUB |


Address decode (32-bit):

```
[31:10] tag (22b) | [9:4] index (6b) | [3:2] word_sel (2b) | [1:0] byte (ignored)
```

**Note:** Byte offset bits [1:0] are not used — the controller operates at word granularity only.
Byte-granular access (e.g. `ldrb`/`strb`) is not supported; `cpu_rdata` always returns a full 32-bit word.

---

## FSM

| State | Action |
|-------|--------|
| IDLE | Wait for `cpu_req` |
| COMPARE | Check tag + valid; classify hit / clean miss / dirty miss |
| WRITEBACK | Evict dirty line to main memory |
| ALLOCATE | Fetch new line from main memory; merge CPU write if write-allocate |
| DONE | Release `cpu_stall`; output corrected data |
| SCRUB | Write ECC-corrected word back to SRAM on SEC event |

---

## ECC

- **Encode:** `ecc_encode.sv` — generates 7-bit Hamming code for each 32-bit word on every SRAM write
- **Decode:** `ecc_decode.sv` — corrects single-bit errors (SEC), detects double-bit errors (DED) on every SRAM read
- Single-bit error → `ecc_sec` asserted → FSM enters SCRUB, writes corrected data back
- Double-bit error → `ecc_ded` asserted → flagged to CPU (data invalid)
- `ecc_sec` and `ecc_ded` are mutually exclusive by design and verified by SVA properties

--- 

## Testbench

**Methodology:** directed tests + fault injection, self-checking scoreboard, reference model

| TestCase | Scenario |
|------|----------|
| 1 | Cold read miss -> allocate from memory |
| 2 | Read hit -> same address |
| 3 | Write hit -> mark dirty |
| 4 | Read-back after write |
| 5 | Dirty eviction -> same index, different tag |
| 6 | Write miss -> allocate + merge (write-allocate) |
| 7 | Single-bit fault injection -> SEC flag + corrected data |
| 8 | Double-bit fault injection -> DED flag |
| 9 | 3-step eviction chain -> re-fetch after writeback |

**Results (xsim):**

```
RESULT: 10 PASS / 0 FAIL
FSM coverage:  100.00%
ECC coverage:  100.00%
OPS coverage:  100.00%
OVERALL: PASS
```

<img width="1551" height="622" alt="image" src="https://github.com/user-attachments/assets/d68aec51-99a1-4e18-a7ec-9d70e4a279f1" />
---


## **SVA assertions:**

| No: | Property |
|----|----------|
| 1 | `ecc_sec` and `ecc_ded` mutually exclusive |
| 2 | WRITEBACK → ALLOCATE in exactly one cycle |
| 3 | DONE only reachable from COMPARE or ALLOCATE |
| 4 | `cpu_stall` held during COMPARE / WRITEBACK / ALLOCATE |
| 5 | ALLOCATE resolves to DONE within 8 cycles (deadlock bound) |
| 6 | `cpu_rdata` stable while stalled |
| 7 | One-hot state encoding sanity check |

---

## How to Run (Vivado xsim)

1. Add all `.sv` files to a Vivado project
2. Set `cache_tb_reference` as the top simulation module
3. Run behavioral simulation
4. Check TCL Console for `OVERALL: PASS` and coverage report

---

## Future Work:

- No AXI4-Lite Slave wrapper (planned)
- Constrained-random (CRV) stimulus and **Formal verification** using SymbiYosys
- `sec_ded.py` golden model used during development — authored separately, not part of RTL

---

## Reference Models

Generated reference tools used during verification — not authored by me, not part of synthesisable RTL.

| File | Purpose |
|------|---------|
| cache_model.py | Behavioural cache reference model |
| sec_ded.py | ECC golden model |
| test_golden.py | Golden model regression tests |
| vectors.json | Pre-generated test vectors | 
