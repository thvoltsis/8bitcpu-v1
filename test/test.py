import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles


def make_uio(opcode: int, vga: int = 0, live: int = 1) -> int:
    """Κωδικοποίηση uio_in: [6:3]=opcode, [1]=vga, [0]=live."""
    return ((opcode & 0xF) << 3) | ((vga & 1) << 1) | (live & 1)


def to_u8(val: int) -> int:
    return val & 0xFF


def get_ovf(dut) -> int:
    return (int(dut.uio_out.value) >> 7) & 1


async def live_op(dut, opcode: int, data: int = 0):
    """Εκτελεί 1 πράξη σε Live Mode (1 κύκλος ρολογιού)."""
    dut.ui_in.value = to_u8(data)
    dut.uio_in.value = make_uio(opcode=opcode, vga=0, live=1)
    await ClockCycles(dut.clk, 1)


async def ram_write_byte(dut, addr: int, value: int):
    """Γράφει ένα byte στη RAM[addr] χρησιμοποιώντας LOAD -> STORE σε Live Mode."""
    await live_op(dut, 0x5, value)  # LOAD value -> acc
    await live_op(dut, 0x6, addr)   # STORE acc -> ram[addr]


@cocotb.test()
async def test_cpu_full(dut):
    dut._log.info("Start tt_um_theovoltsis_cpu full test")

    # 25 MHz clock (40 ns period)
    clock = Clock(dut.clk, 40, unit="ns")
    cocotb.start_soon(clock.start())

    # --- 1. Reset ---
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 1)

    assert int(dut.uio_oe.value) == 0x80, f"Expected uio_oe=0x80, got {int(dut.uio_oe.value):#x}"
    assert int(dut.uo_out.value) == 0, "Expected acc=0 after reset"
    assert get_ovf(dut) == 0, "Expected overflow=0 after reset"
    dut._log.info("1. Reset & uio_oe OK")

    # --- 2. Live Mode: Όλες οι πράξεις της ALU ---
    await live_op(dut, 0x5, 10)   # LOAD 10
    assert int(dut.uo_out.value) == 10 and get_ovf(dut) == 0

    await live_op(dut, 0x1, 5)    # ADD 5 -> 15
    assert int(dut.uo_out.value) == 15 and get_ovf(dut) == 0

    await live_op(dut, 0x2, 3)    # SUB 3 -> 12
    assert int(dut.uo_out.value) == 12 and get_ovf(dut) == 0

    await live_op(dut, 0x3, 0)    # INC -> 13
    assert int(dut.uo_out.value) == 13 and get_ovf(dut) == 0

    await live_op(dut, 0x4, 0)    # DEC -> 12
    assert int(dut.uo_out.value) == 12 and get_ovf(dut) == 0

    await live_op(dut, 0x7, 0x0A) # AND 0b1010 -> 12 & 10 = 8
    assert int(dut.uo_out.value) == 8

    await live_op(dut, 0x8, 0x03) # OR 0b0011 -> 8 | 3 = 11
    assert int(dut.uo_out.value) == 11

    await live_op(dut, 0x9, 0x0F) # XOR 0x0F -> 11 ^ 15 = 4
    assert int(dut.uo_out.value) == 4

    await live_op(dut, 0xB, 0)    # SHL -> 8
    assert int(dut.uo_out.value) == 8

    await live_op(dut, 0xA, 0)    # NOT -> ~8 = 0xF7 (-9)
    assert int(dut.uo_out.value) == 0xF7

    await live_op(dut, 0xC, 0)    # SAR (arithmetic) -> -9 >>> 1 = -5 (0xFB)
    assert int(dut.uo_out.value) == 0xFB

    await live_op(dut, 0x0, 0)    # CLR -> 0
    assert int(dut.uo_out.value) == 0
    dut._log.info("2. Live Mode ALU operations OK")

    # --- 3. Signed Overflow ---
    await live_op(dut, 0x5, 127)  # LOAD +127
    await live_op(dut, 0x3, 0)    # INC -> -128 (0x80), overflow = 1
    assert int(dut.uo_out.value) == 0x80 and get_ovf(dut) == 1, "Expected INC overflow"

    await live_op(dut, 0x4, 0)    # DEC (-128 - 1) -> +127 (0x7F), overflow = 1
    assert int(dut.uo_out.value) == 0x7F and get_ovf(dut) == 1, "Expected DEC overflow"

    await live_op(dut, 0x5, 100)  # LOAD 100
    await live_op(dut, 0x1, 50)   # ADD 50 -> 150 -> signed overflow
    assert get_ovf(dut) == 1, "Expected ADD overflow"
    dut._log.info("3. Signed Overflow OK")

    # --- 4. Εκτέλεση Προγράμματος από RAM (live = 0) ---
    # Reset για να ξεκινήσει καθαρά το PC=0, state=FETCH
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 2)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 1)

    # Πρόγραμμα στη RAM:
    # 0: 0x58 -> LOAD ram[8]  (10)
    # 1: 0x19 -> ADD  ram[9]  (+5 = 15)
    # 2: 0x2A -> SUB  ram[10] (-15 = 0)
    # 3: 0xE5 -> JZ   5       (αφού acc==0, πηδάει στο 5 και προσπερνά το 4)
    # 4: 0x30 -> INC          (δεν πρέπει να εκτελεστεί)
    # 5: 0x5B -> LOAD ram[11] (42)
    # 6: 0xF0 -> HLT
    program = {
        0: 0x58,
        1: 0x19,
        2: 0x2A,
        3: 0xE5,
        4: 0x30,
        5: 0x5B,
        6: 0xF0,
        8: 10,
        9: 5,
        10: 15,
        11: 42,
    }
    for addr, val in program.items():
        await ram_write_byte(dut, addr, val)

    # Καθαρισμός acc πριν τη μετάβαση σε RAM mode
    await live_op(dut, 0x0, 0)

    # Ενεργοποίηση RAM program execution (live = 0, vga = 0)
    dut.ui_in.value = 0
    dut.uio_in.value = make_uio(opcode=0, vga=0, live=0)

    # Κάθε εντολή = 2 κύκλοι (FETCH + EXECUTE)
    await ClockCycles(dut.clk, 2)  # ram[0]: LOAD 10
    assert int(dut.uo_out.value) == 10, f"RAM LOAD failed: got {int(dut.uo_out.value)}"

    await ClockCycles(dut.clk, 2)  # ram[1]: ADD 5 -> 15
    assert int(dut.uo_out.value) == 15, f"RAM ADD failed: got {int(dut.uo_out.value)}"

    await ClockCycles(dut.clk, 2)  # ram[2]: SUB 15 -> 0
    assert int(dut.uo_out.value) == 0, f"RAM SUB failed: got {int(dut.uo_out.value)}"

    await ClockCycles(dut.clk, 2)  # ram[3]: JZ 5
    await ClockCycles(dut.clk, 2)  # ram[5]: LOAD 42
    assert int(dut.uo_out.value) == 42, f"RAM JZ/LOAD failed: got {int(dut.uo_out.value)}"

    await ClockCycles(dut.clk, 6)  # ram[6]: HLT (πρέπει να μείνει 42)
    assert int(dut.uo_out.value) == 42, "RAM HLT failed: acc changed after HLT"
    dut._log.info("4. RAM Program Execution (LOAD/ADD/SUB/JZ/HLT) OK")

    # --- 5. TinyVGA Mode (uio_in[1] = 1) ---
    dut.uio_in.value = make_uio(opcode=0, vga=1, live=0)
    seen_hsync_low = False
    seen_hsync_high = False

    for _ in range(800):
        await ClockCycles(dut.clk, 1)
        hsync = (int(dut.uo_out.value) >> 7) & 1
        if hsync == 0:
            seen_hsync_low = True
        else:
            seen_hsync_high = True

    assert seen_hsync_low and seen_hsync_high, "VGA HSync pulse not detected!"
    dut._log.info("5. TinyVGA HSync OK — All tests passed!")
