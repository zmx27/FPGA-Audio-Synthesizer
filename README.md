# FPGA Electric Piano Synthesizer

## Overview
This project implements a complete digital audio synthesizer and automated "player piano" on a Xilinx Artix-7 FPGA using VHDL. The system synthesizes precise musical frequencies using custom clock division logic, processes real-time user inputs via physical switches, and utilizes a Finite State Machine (FSM) coupled with Read-Only Memory (ROM) to execute automated sheet music playback.

### **Key Technologies & Skills:**
* **Hardware:** Basys 3 Artix-7 FPGA Board, Piezoelectric Speaker
* **Languages & Tools:** VHDL, Xilinx Vivado
* **Concepts:** RTL Design, Frequency Synthesis, FSMs, ROM Look-Up Tables, Time-Multiplexing, Hardware Simulation/Testbenches

---

## 🎹 Phase 1: Manual Electric Piano & Frequency Synthesis

The foundational phase of the project involved transforming physical switch inputs into precise audio frequencies and displaying the active note on a 7-segment display.

### Frequency Generation Architecture
The core audio generation relies on a custom clock divider circuit. Taking a `1 MHz` internal clock, the output frequency is calculated as a function of the divider value using the formula `FREQ = 500 KHz / DIV`.

#### Clock Divider Mathematical Derivation
To synthesize specific musical notes, the FPGA's base clock must be stepped down to match precise audio frequencies. This is achieved using a custom clock divider (`clk-dvd.vhd`) that generates a 50% duty cycle square wave. 

The hardware counter variable `DIV` represents the integer number of half-periods to divide the clock by. The relationship is defined by the core formula:

$$DIV = \left(\frac{CLK}{FREQ}\right) \times 0.5$$

To find the required frequency output, we can algebraically rearrange this formula:

$$DIV = \frac{CLK}{2 \times FREQ}$$

$$FREQ = \frac{CLK}{2 \times DIV}$$

In this system architecture, the primary input clock (`CLK`) fed into the note generator is driven at `1 MHz` (1,000,000 Hz). Substituting this into the equation gives us the final hardware scaling factor:

$$FREQ = \frac{1,000,000}{2 \times DIV} = \frac{500,000}{DIV}$$ 

By feeding the calculated `DIV` hex values into the loadable counter, the FPGA accurately outputs the corresponding musical pitch.

The table below maps the synthesized natural and sharp/flat notes to their calculated hex divider values:

| Note | Frequency (Hz) | Hex Divider | Decimal Divider |
|------|----------------|-------------|-----------------|
| C3   | 130.822        | 0EEE        | 3822            |
| C3#  | 138.581        | 0E18        | 3608            |
| D3   | 146.800        | 0D4E        | 3406            |
| D3#  | 155.570        | 0C8E        | 3214            |
| E3   | 164.799        | 0BDA        | 3034            |
| F3   | 174.581        | 0B30        | 2864            |
| F3#  | 185.048        | 0A8E        | 2702            |
| G3   | 196.002        | 09F7        | 2551            |
| G3#  | 207.641        | 0968        | 2408            |
| A3   | 219.974        | 08E1        | 2273            |
| A3#  | 233.100        | 0861        | 2145            |
| B3   | 246.914        | 07E9        | 2025            |
| C4   | 261.643        | 0777        | 1911            |

### Hardware Interface & UI
* **Note Selection:** 8 toggle switches are mapped to a priority encoder to select the base natural note. 
* **Modifiers:** Push buttons act as shift registers to dynamically apply sharps (+1 semitone), flats (-1 semitone), and octave jumps (+1 octave).
* **Time-Multiplexed Display:** The active note is rendered on a time multiplexed 4-digit 7-segment display. To prevent flicker, the display controller uses a 10 kHz scan rate to cycle through the active anodes at a fast enough rate that it appears stable.

### Hardware Simulation & Verification
To verify the RTL logic and timing before physical implementation, a comprehensive VHDL testbench was developed to simulate the user interface and frequency generation. 

**Simulation Signal Legend:**
* **`switch_in [7:0]`:** The 8-bit toggle switch input representing the selected base natural note (One-hot encoded).
* **`pb_in [3:0]`:** The 4-bit push-button input acting as shift registers for modifiers. (Bit 3/2 = Sharp, Bit 1 = Flat, Bit 0 = Octave Jump).
* **`SPK_N` / `SPK_P`:** The divided output square wave that drives the physical piezoelectric speaker.
* **`digit_out [3:0]` & `seg_out [7:0]`:** The time-multiplexed outputs driving the 4-digit 7-segment display UI (Active Low).

#### Test Case 1: Base Note Generation (C3)
<img width="1156" height="155" alt="image" src="https://github.com/user-attachments/assets/4dfee940-08d6-49b6-97f8-ebc4b20973a3" />
**Analysis:** `switch_in` is set to `10000000` (Note C) with no push-button modifiers active (`pb_in = 0000`). The UI logic successfully decodes this to drive the 7-segment display (`seg_out = 00001101`), while `SPK_N` outputs the corresponding 130.8 Hz square wave.

#### Test Case 2: Hardware Modifiers & Octave Jumping (A#4)
<img width="1155" height="161" alt="image" src="https://github.com/user-attachments/assets/0ebc0b98-db25-4b08-bc2a-876bc88104bc" />
**Analysis:** `switch_in` is set to `00000100` (Note A), while the user simultaneously applies a sharp modifier and an octave jump via the push buttons (`pb_in = 1100`). The hardware mathematically shifts the base note, updating the display output (`seg_out = 11111111`) and scaling the clock divider to output the correct frequency for A4 Sharp.

---

## 🤖 Phase 2: Automated "Player" Piano

The design was advanced into an automated playback engine capable of reading and executing sheet music sequentially.

### FSM & ROM Implementation
The automatic playback logic replaces manual switch inputs with a sequenced hardware state machine.
* **Tempo Generator:** A precise timing block that counts system clock cycles to generate a `120 BPM` hardware "metronome" (2 beats per second).
* **Sheet Music ROM:** A 32-beat song ("Mary Had a Little Lamb") was encoded into a 5-bit lookup table. 
* **State Machine:** A program counter (`song_index`) advances on every beat tick, fetching the next musical instruction from the ROM and feeding it to the frequency synthesizer.

### Articulation Control (Solving the "Bleeding Notes" Problem)
A significant hardware challenge was distinguishing between repeated notes (e.g., two consecutive E quarter notes) and sustained notes (e.g., one E half note). If identical notes are streamed back-to-back, the output audio merges into an uninterrupted tone. 

**Solution:** I implemented a dynamic articulation control. During the final 20% of a defined beat cycle, the audio output is temporarily muted by routing a `"00000"` signal to the synthesizer. This simulates the physical lifting of a piano key, ensuring crisp, distinct keystrokes while preserving the ability to string together continuous half and whole notes.

---

## 🎥 Demonstration

[Link to a video of the board playing "Mary Had a Little Lamb"](https://drive.google.com/file/d/1qOzsZrcSMNQR5Ob79eCs8f-H7pMcgDhF/view?usp=sharing)

---

## 🛠️ How to Run
1. Clone this repository.
2. Open the project in **Xilinx Vivado**.
3. Run **Synthesis** and **Implementation**.
4. Generate the `.bit` file.
5. Program your **Basys 3** FPGA board and connect a piezoelectric speaker to the `JA` Pmod port (Pin G3 for Signal, Pin H2 for Ground).
