# cache_model.py
# Behavioral golden model for direct-mapped L1 cache
# with SEC-DED ECC per 32-bit word
#
# Parameters:
#   CACHE_SIZE = 1024 bytes
#   LINE_SIZE  = 16 bytes (4 x 32-bit words)
#   WAYS       = 1 (direct-mapped)
#   ADDR_WIDTH = 32-bit
#
# Address breakdown:
#   [31:10] TAG  (22 bits)
#   [9:4]   INDEX (6 bits) → 64 lines
#   [3:0]   OFFSET (4 bits) → 16 bytes per line

from sec_ded import ecc_encode, ecc_decode

# ─────────────────────────────────────────────
# PARAMETERS
# ─────────────────────────────────────────────

CACHE_SIZE  = 1024        # bytes
LINE_SIZE   = 16          # bytes per cache line
WORD_SIZE   = 4           # bytes per word (32-bit)
WORDS_PER_LINE = LINE_SIZE // WORD_SIZE   # 4

NUM_LINES   = CACHE_SIZE // LINE_SIZE     # 64

OFFSET_BITS = 4           # log2(16)
INDEX_BITS  = 6           # log2(64)
TAG_BITS    = 22          # 32 - 6 - 4

OFFSET_MASK = (1 << OFFSET_BITS) - 1          # 0x00F
INDEX_MASK  = ((1 << INDEX_BITS) - 1)         # 0x03F
TAG_MASK    = ((1 << TAG_BITS) - 1)           # 0x3FFFFF

# ─────────────────────────────────────────────
# ADDRESS DECOMPOSITION
# ─────────────────────────────────────────────
# C equivalent:
#   int offset = addr & 0xF;
#   int index  = (addr >> 4) & 0x3F;
#   int tag    = (addr >> 10) & 0x3FFFFF;

def get_offset(addr): return (addr >> 0)          & OFFSET_MASK
def get_index(addr):  return (addr >> OFFSET_BITS) & INDEX_MASK
def get_tag(addr):    return (addr >> (OFFSET_BITS + INDEX_BITS)) & TAG_MASK

# ─────────────────────────────────────────────
# CACHE LINE STRUCTURE
# ─────────────────────────────────────────────
# C equivalent:
#   typedef struct {
#       int      valid;
#       int      dirty;
#       uint32_t tag;
#       uint32_t data[4];
#       uint8_t  ecc[4];
#   } CacheLine;

def make_line():
    # [PY] dict = C struct. Keys are field names.
    return {
        'valid': 0,
        'dirty': 0,
        'tag':   0,
        'data':  [0] * WORDS_PER_LINE,   # uint32_t data[4]
        'ecc':   [0] * WORDS_PER_LINE,   # uint8_t  ecc[4]
    }

# ─────────────────────────────────────────────
# CACHE MODEL CLASS
# ─────────────────────────────────────────────
# C equivalent: global array + functions operating on it
#   CacheLine cache[64];

class CacheModel:

    def __init__(self):
        # [PY] list comprehension: builds 64 fresh cache lines
        # C: CacheLine cache[64]; memset(cache, 0, sizeof(cache));
        self.lines = [make_line() for _ in range(NUM_LINES)]

        # Simple flat memory model — "backing DRAM"
        # C: uint32_t memory[1<<30]; (we fake it with a dict)
        # [PY] dict used as sparse array — only stores written addresses
        self.memory = {}

        # Event log — for generating TB vectors later
        self.log = []

    # ── Internal: memory read (backing store) ──────────────
    def _mem_read_line(self, addr):
        """Read full cache line (4 words) from flat memory."""
        base = addr & ~OFFSET_MASK   # align to line boundary
        # C: for(int i=0; i<4; i++) line[i] = memory[base + i*4];
        return [self.memory.get(base + i*WORD_SIZE, 0)
                for i in range(WORDS_PER_LINE)]

    def _mem_write_line(self, addr, data):
        """Write full cache line back to flat memory."""
        base = addr & ~OFFSET_MASK
        for i in range(WORDS_PER_LINE):
            self.memory[base + i*WORD_SIZE] = data[i]

    # ── Internal: fill line from memory, encode ECC ────────
    def _fill(self, index, tag, addr):
        """
        Allocate cache line: read from memory, encode ECC per word.
        Called on miss after any needed writeback.

        C equivalent:
            line->valid = 1; line->dirty = 0; line->tag = tag;
            for(int i=0; i<4; i++) {
                line->data[i] = mem_read(...);
                line->ecc[i]  = ecc_encode(line->data[i]);
            }
        """
        line = self.lines[index]
        data_words = self._mem_read_line(addr)

        line['valid'] = 1
        line['dirty'] = 0
        line['tag']   = tag
        for i in range(WORDS_PER_LINE):
            _, ecc = ecc_encode(data_words[i])
            line['data'][i] = data_words[i]
            line['ecc'][i]  = ecc

    # ── Internal: writeback dirty line to memory ───────────
    def _writeback(self, index):
        """
        Write dirty line back to memory using stored tag to reconstruct addr.
        C: mem_write(reconstruct_addr(line->tag, index), line->data);
        """
        line = self.lines[index]
        # Reconstruct address from tag + index (offset = 0, line-aligned)
        wb_addr = (line['tag'] << (OFFSET_BITS + INDEX_BITS)) | (index << OFFSET_BITS)
        self._mem_write_line(wb_addr, line['data'])
        line['dirty'] = 0

    # ── PUBLIC: READ ────────────────────────────────────────
    def read(self, addr):
        """
        Read one word from cache.

        Returns: (data, hit, sec_flag, ded_flag)

        FSM path:
          IDLE → COMPARE
            hit              → return corrected data
            clean miss       → ALLOCATE → return data
            dirty miss       → WRITEBACK → ALLOCATE → return data
        """
        tag    = get_tag(addr)
        index  = get_index(addr)
        offset = get_offset(addr)
        word_i = offset // WORD_SIZE   # which of the 4 words

        line = self.lines[index]

        # ── COMPARE state ──────────────────────────────────
        hit = line['valid'] and (line['tag'] == tag)

        if not hit:
            # ── WRITEBACK state (if dirty) ─────────────────
            if line['valid'] and line['dirty']:
                self._writeback(index)
            # ── ALLOCATE state ─────────────────────────────
            self._fill(index, tag, addr)

        # ── Read word + ECC decode ─────────────────────────
        raw_data = line['data'][word_i]
        ecc      = line['ecc'][word_i]
        corrected, sec, ded = ecc_decode(raw_data, ecc)

        # If SEC corrected, update stored data (scrubbing)
        if sec:
            line['data'][word_i] = corrected
            _, line['ecc'][word_i] = ecc_encode(corrected)

        self.log.append({
            'op': 'R', 'addr': addr, 'hit': int(hit),
            'data': corrected, 'sec': sec, 'ded': ded
        })

        return (corrected, hit, sec, ded)

    # ── PUBLIC: WRITE ───────────────────────────────────────
    def write(self, addr, data):
        """
        Write one word to cache (write-back, write-allocate).

        Returns: hit (bool)

        FSM path:
          IDLE → COMPARE
            hit        → update data+ECC, set dirty
            clean miss → ALLOCATE → update data+ECC, set dirty
            dirty miss → WRITEBACK → ALLOCATE → update data+ECC, set dirty
        """
        tag    = get_tag(addr)
        index  = get_index(addr)
        offset = get_offset(addr)
        word_i = offset // WORD_SIZE

        line = self.lines[index]

        hit = line['valid'] and (line['tag'] == tag)

        if not hit:
            if line['valid'] and line['dirty']:
                self._writeback(index)
            self._fill(index, tag, addr)

        # Update word + re-encode ECC
        _, new_ecc = ecc_encode(data)
        line['data'][word_i] = data
        line['ecc'][word_i]  = new_ecc
        line['dirty'] = 1

        self.log.append({
            'op': 'W', 'addr': addr, 'hit': int(hit),
            'data': data, 'sec': 0, 'ded': 0
        }) 

        return hit

    # ── PUBLIC: FAULT INJECTION ─────────────────────────────
    def inject_fault(self, addr, word_idx, bit_pos, double=False):
        """
        Flip 1 or 2 bits in stored data, leave ECC unchanged.
        Simulates a DRAM bit-flip or radiation event.

        C: cache[index].data[word_idx] ^= (1 << bit_pos);
        """
        index = get_index(addr)
        line  = self.lines[index]

        line['data'][word_idx] ^= (1 << bit_pos)
        if double:
            next_bit = (bit_pos + 1) % 32
            line['data'][word_idx] ^= (1 << next_bit)

        self.log.append({
            'op': 'FAULT', 'addr': addr, 'word_idx': word_idx,
            'bit_pos': bit_pos, 'double': double
        })