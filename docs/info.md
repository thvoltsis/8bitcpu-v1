<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

This project is an **8-bit Von Neumann CPU** (inspired by the SAP-1 architecture) with **16 bytes of shared RAM** (16x8-bit), a **signed 8-bit ALU** (two's complement), a 2-state FSM (`FETCH` and `EXECUTE`), and an integrated **TinyVGA output controller**.

### Operating Modes (`uio_in[0]`)

1. **Live Mode (`uio_in[0] = 1`):** Direct, single-cycle ALU control via external pins (`uio_in[6:3]` for the 4-bit opcode and `ui_in[7:0]` for the 8-bit signed operand). This mode is also used to load instructions and data into the internal 16-byte RAM using `LOAD` followed by `STORE`.
2. **Program Mode (`uio_in[0] = 0`):** Autonomous execution from internal RAM starting at `PC = 0`. Each instruction takes 2 clock cycles:
   - **FETCH:** Reads the 8-bit instruction at `RAM[PC]` into the Instruction Register (`IR`).
   - **EXECUTE:** Decodes `IR[7:4]` as the opcode and `IR[3:0]` as the 4-bit memory address/operand, updates the Accumulator (`A`), overflow flag (`uio_out[7]`), and Program Counter (`PC`).

### Output Modes (`uio_in[1]`)

- **LED / Accumulator Mode (`uio_in[1] = 0`):** Outputs the 8-bit Accumulator value directly on `uo_out[7:0]`.
- **TinyVGA Mode (`uio_in[1] = 1`):** Switches `uo_out[7:0]` to a standard 640x480 @ 60 Hz TinyVGA RGB222 video signal (25.175 MHz pixel clock). The screen displays the 8 bits of the Accumulator (`A[7]` to `A[0]`) as eight 48x48 px squares (white = `1`, grey = `0`). The background is dark blue during normal operation and turns red when the signed `overflow` flag is asserted.

### Instruction Set Architecture (ISA)

Each instruction in RAM is 8 bits wide: `[7:4] = Opcode`, `[3:0] = Address`.

| Opcode | Mnemonic | Description | Flags / Notes |
| :---: | :---: | :--- | :--- |
| `0000` | `CLR` | `A = 0` | Clears Accumulator and overflow |
| `0001` | `ADD` | `A = A + B` | Signed 8-bit addition, sets `overflow` |
| `0010` | `SUB` | `A = A - B` | Signed 8-bit subtraction, sets `overflow` |
| `0011` | `INC` | `A = A + 1` | Increments `A`, sets `overflow` at `127 -> -128` |
| `0100` | `DEC` | `A = A - 1` | Decrements `A`, sets `overflow` at `-128 -> 127` |
| `0101` | `LOAD` | `A = B` | Loads `ui_in` (Live) or `RAM[addr]` (Program) |
| `0110` | `STORE` | `RAM[addr] = A` | Writes `A` to `RAM[ui_in[3:0]]` (Live) or `RAM[IR[3:0]]` (Program) |
| `0111` | `AND` | `A = A & B` | Bitwise AND |
| `1000` | `OR` | `A = A \| B` | Bitwise OR |
| `1001` | `XOR` | `A = A ^ B` | Bitwise XOR |
| `1010` | `NOT` | `A = ~A` | Bitwise NOT |
| `1011` | `SHL` | `A = A << 1` | Logical shift left by 1 |
| `1100` | `SHR` | `A = A >>> 1` | Arithmetic shift right by 1 (preserves sign) |
| `1101` | `JMP` | `PC = addr` | Unconditional jump (Program mode; NOP in Live mode) |
| `1110` | `JZ` | `if (A == 0) PC = addr` | Jump if Accumulator is zero (Program mode; NOP in Live mode) |
| `1111` | `HALT` | Stop execution | Halts FSM in `EXECUTE` state until reset |

*Note: In Live mode, `B = ui_in[7:0]`. In Program mode, `B = RAM[IR[3:0]]`.*

## How to test

### 1. Live Mode Test
1. Assert reset (`rst_n = 0`) for at least 1 clock cycle, then release (`rst_n = 1`).
2. Set `uio_in[0] = 1` (`live = 1`) and `uio_in[1] = 0` (LED output mode).
3. Apply `opcode = 0101` (`LOAD`) on `uio_in[6:3]` and `ui_in = 12`. Pulse `clk` -> `uo_out` reads `12`.
4. Apply `opcode = 0001` (`ADD`) and `ui_in = 8`. Pulse `clk` -> `uo_out` reads `20`.
5. Test signed overflow by loading `100` and adding `50`: `uo_out` wraps to `-106` (`0x96`) and `uio_out[7]` (`overflow`) goes high (`1`).

### 2. Program Mode Test (Loading & Running from RAM)
To write a byte `VAL` to `RAM[ADDR]` in Live mode (`uio_in[0] = 1`, `uio_in[1] = 0`):
1. `LOAD` `VAL` (`opcode = 0101`, `ui_in = VAL`), pulse `clk`.
2. `STORE` to `ADDR` (`opcode = 0110`, `ui_in = ADDR`), pulse `clk`.

Example program (`25 + 17 = 42`):
- `RAM[0]` = `0x5A` (`LOAD RAM[10]`)
- `RAM[1]` = `0x1B` (`ADD RAM[11]`)
- `RAM[2]` = `0xF0` (`HALT`)
- `RAM[10]` = `25`
- `RAM[11]` = `17`

After loading the bytes above:
1. Issue `CLR` (`opcode = 0000`) in Live mode so `A = 0`.
2. Switch to Program Mode by setting `uio_in[0] = 0` (`live = 0`).
3. Clock the CPU for at least 6 cycles -> `uo_out` outputs `42` (`0x2A`) and remains latched at `HALT`.

### 3. TinyVGA Mode Test
1. Connect a **TinyVGA PMOD** to the `uo_out` port and set the board clock to **25.175 MHz** (or 25 MHz).
2. Set `uio_in[1] = 1` to enable VGA output.
3. The monitor displays eight squares corresponding to the 8 bits of the Accumulator (`A[7:0]`), with a dark blue background (or red when `overflow = 1`).

## External hardware

- **None required** for standard CPU operation: the chip can be driven directly from the Tiny Tapeout demo board's RP2040 microcontroller or manual switches/LEDs.
- **TinyVGA PMOD** (optional): required on `uo_out[7:0]` only when using the TinyVGA display mode (`uio_in[1] = 1`).
