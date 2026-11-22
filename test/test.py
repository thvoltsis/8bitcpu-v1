import random
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, FallingEdge

# Opcodes της CPU
OP_CLR   = 0b0000
OP_ADD   = 0b0001
OP_SUB   = 0b0010
OP_INC   = 0b0011
OP_DEC   = 0b0100
OP_LOAD  = 0b0101
OP_STORE = 0b0110
OP_AND   = 0b0111
OP_OR    = 0b1000
OP_XOR   = 0b1001
OP_NOT   = 0b1010
OP_SHL   = 0b1011
OP_SHR   = 0b1100
OP_JMP   = 0b1101
OP_JZ    = 0b1110
OP_HALT  = 0b1111


def to_signed8(val: int) -> int:
    val &= 0xFF
    return val - 256 if val >= 128 else val


def to_unsigned8(val: int) -> int:
    return val & 0xFF


def make_uio_in(opcode: int, live: int = 1, extra: int = 0) -> int:
    """uio_in[0] = live, uio_in[6:3] = opcode"""
    return ((opcode & 0xF) << 3) | ((extra & 0x3) << 1) | (live & 0x1)


async def reset_cpu(dut):
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = make_uio_in(OP_JMP, live=1)
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 1)
    await FallingEdge(dut.clk)


async def exec_live(dut, opcode: int, data: int = 0):
    """Εκτελεί 1 εντολή σε Live mode και επιστρέφει (signed_a, overflow)."""
    dut.uio_in.value = make_uio_in(opcode, live=1)
    dut.ui_in.value = to_unsigned8(data)
    await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    a_val = to_signed8(int(dut.uo_out.value))
    ovf = (int(dut.uio_out.value) >> 7) & 1
    return a_val, ovf


async def write_ram_live(dut, addr: int, value: int):
    """Γράφει το value στη RAM[addr] μέσω Live mode (LOAD -> STORE)."""
    await exec_live(dut, OP_LOAD, value)
    await exec_live(dut, OP_STORE, addr & 0xF)


def golden_step(a: int, ovf: int, opcode: int, b: int):
    """Golden reference model για Live mode (alu.sv + controler.sv)."""
    b = to_signed8(b)
    if opcode in (OP_STORE, OP_JMP, OP_JZ):
        # Σε Live mode δεν ενημερώνονται a και overflow
        return a, ovf

    new_ovf = 0
    if opcode == OP_CLR:
        res = 0
    elif opcode == OP_ADD:
        res = to_signed8(a + b)
        if (a >= 0 and b >= 0 and res < 0) or (a < 0 and b < 0 and res >= 0):
            new_ovf = 1
    elif opcode == OP_SUB:
        res = to_signed8(a - b)
        if (a >= 0 and b < 0 and res < 0) or (a < 0 and b >= 0 and res >= 0):
            new_ovf = 1
    elif opcode == OP_INC:
        res = to_signed8(a + 1)
        if a == 127:
            new_ovf = 1
    elif opcode == OP_DEC:
        res = to_signed8(a - 1)
        if a == -128:
            new_ovf = 1
    elif opcode == OP_LOAD:
        res = b
