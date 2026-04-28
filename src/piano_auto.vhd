--
-- piano.vhd - FPGA Piano
--
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
library UNISIM;
use UNISIM.VComponents.all;

entity piano is
    port ( CLK_IN       : in std_logic;
           pb_in        : in std_logic_vector(3 downto 0);
           switch_in    : in std_logic_vector(7 downto 0);
           SPK_N        : out std_logic; 
           SPK_P        : out std_logic;
           led_out      : out std_logic_vector(7 downto 0);
           digit_out    : out std_logic_vector(3 downto 0);
           seg_out      : out std_logic_vector(7 downto 0)
         );
end piano;

architecture Behavioral of piano is
   -- Xilinx Native Components
   component BUFG  port ( I : in std_logic; O : out std_logic); end component;
   component IBUFG port ( I : in std_logic; O : out std_logic); end component;
   component IBUF  port ( I : in std_logic; O : out std_logic); end component;
   component OBUF  port ( I : in std_logic; O : out std_logic); end component;
   component MMCME2_BASE
      generic( CLKFBOUT_MULT_F : real;
                DIVCLK_DIVIDE :  integer;
                CLKOUT0_DIVIDE_F  :  real
              );
      port ( CLKIN1     : in    std_logic; 
             CLKFBIN    : in    std_logic; 
             RST        : in    std_logic; 
             PWRDWN     : in    std_logic; 
             CLKOUT0    : out   std_logic; 
             CLKOUT0B   : out   std_logic;
             CLKOUT1    : out   std_logic;
             CLKOUT1B   : out   std_logic;
             CLKOUT2    : out   std_logic;
             CLKOUT2B   : out   std_logic;
             CLKOUT3    : out   std_logic;
             CLKOUT3B   : out   std_logic;
             CLKOUT4    : out   std_logic;
             CLKOUT5    : out   std_logic;
             CLKOUT6    : out   std_logic;
             CLKFBOUT   : out   std_logic; 
             CLKFBOUTB  : out   std_logic; 
             LOCKED     : out   std_logic);
   end component;

    -- My Components:

    --  Clock Divider
    component clk_dvd
    port (
          CLK     : in std_logic;
          RST     : in std_logic;
          DIV     : in std_logic_vector(15 downto 0);
          EN      : in std_logic;
          CLK_OUT : out std_logic;
          ONE_SHOT: out std_logic
         );
    end component;

    -- Note decoder
    component note_gen
    port (
          CLK       : in  std_logic;
          RST       : in  std_logic;
          NOTE_IN   : in  std_logic_vector(4 downto 0);
          DIV       : out std_logic_vector(15 downto 0)
         );
    end component;
    
    -- 7-Segment Display for Notes
    component seven_seg
        port ( CLK      : in std_logic;
               RST      : in std_logic;
               NOTE_IN  : in std_logic_vector(4 downto 0);
               SCAN_EN  : in std_logic; 
               DIGIT    : out std_logic_vector(3 downto 0);
               SEG      : out std_logic_vector(7 downto 0) 
             );
   end component;

   -- Signals
   signal CLK         : std_logic;                      -- 50MHz clock after DCM and BUFG
   signal CLK0        : std_logic;                      -- 50MHz clock from pad
   signal CLK_BUF     : std_logic;                      -- 50MHz clock after IBUF
   signal GND         : std_logic;                      
   signal RST         : std_logic;              
   signal PB          : std_logic_vector(3 downto 0);   -- Pushbuttons after ibufs
   signal digit_l     : std_logic_vector(3 downto 0);   -- 7-seg digit MUX before obuf
   signal switch      : std_logic_vector(7 downto 0);   -- Toggle switches after ibufs
   signal led         : std_logic_vector(7 downto 0);   -- LEDs after ibufs
   signal seg_l       : std_logic_vector(7 downto 0);   -- 7-seg segment select before obuf.
  
   signal one_mhz     : std_logic;                      -- 1MHz Clock
   signal one_mhz_1   : std_logic;                      -- pulse with f=1 MHz created by divider
   signal clk_10k_1   : std_logic;                      -- pulse with f=10kHz created by divider
   signal div         : std_logic_vector(15 downto 0);  -- variable clock divider for loadable counter
   signal note_in     : std_logic_vector(4 downto 0);   -- output of user interface. Current Note
   signal note_next   : std_logic_vector(4 downto 0);   -- Buffer holding current Note
   signal note_sel    : std_logic_vector(3 downto 0);   -- Encoding of switches.
   signal div_1       : std_logic;                      -- 1MHz pulse
   signal sound       : std_logic;                      -- Output of Loadable Clock Divider. Sent to Speaker if note is playing.
   signal SPK         : std_logic;                      -- Output for Speaker fed to OBUF

   -- Player piano Signals
   signal beat_counter : integer range 0 to 5000 := 0; -- Our beat tempo
   signal playing : std_logic := '0'; -- Whether the piano is currently active
   signal beat_tick : std_logic := '0'; -- Our current beat/position
   signal song_index : integer range 0 to 31 := 0; -- Assuming 32 beat long song
   signal auto_note : std_logic_vector(4 downto 0); -- The note the song is playing
   
begin
    GND    <= '0';     
    RST    <= PB(0);    -- push button one is the reset
    led(1) <= RST;      -- This is just to make sure our design is running.

    -- Combinational logic to turn the sound on and off
    process (div, sound) begin
        if (div = x"0000") then
            SPK <= GND;
        else
            SPK <= sound;
        end if;
    end process;
    
    -- Speaker output
    SPK_OBUF_INST : OBUF port map (I=>SPK, O=>SPK_N);
    SPK_P <= GND; 

    -- Input/Output Buffers
    loop0 : for i in 0 to 3 generate
        pb_ibuf  : IBUF  port map(I => pb_in(i),   O => PB(i));
        dig_obuf : OBUF  port map(I => digit_l(i), O => digit_out(i));
    end generate ;
    loop1 : for i in 0 to 7 generate
        swt_obuf : IBUF  port map(I => switch_in(i), O => switch(i));
        led_obuf : OBUF  port map(I => led(i),   O => led_out(i));
        seg_obuf : OBUF  port map(I => seg_l(i), O => seg_out(i));
    end generate ;

    -- Global Clock Buffers

    -- Pad -> DCM
    CLKIN_IBUFG_INST : IBUFG
      port map (I=>CLK_IN,      
                O=>CLK0);

    -- DCM -> CLK
    CLK0_BUFG_INST : BUFG
      port map (I=>CLK_BUF,      
                O=>CLK);

   
    -- MMCM for Clock deskew and frequency synthesis
    MMCM_INST : MMCME2_BASE
      generic map(
        CLKFBOUT_MULT_F =>10.0,
        DIVCLK_DIVIDE=>1,
        CLKOUT0_DIVIDE_F =>10.0
      )
      port map (CLKIN1=>CLK0,
               CLKFBIN=>CLK, 
               RST=>RST, 
               PWRDWN=>GND, 
               CLKOUT0=>CLK_BUF,
               CLKOUT0B=>open,
               CLKOUT1=>open,
               CLKOUT1B=>open,
               CLKOUT2=>open,
               CLKOUT2B=>open,
               CLKOUT3=>open,
               CLKOUT3B=>open,
               CLKOUT4=>open,
               CLKOUT5=>open,
               CLKOUT6=>open,
               CLKFBOUT=>open, 
               CLKFBOUTB=>open, 
               LOCKED=>led(0)
               );

    -- Divide 100Mhz to 1Mhz clock
    DIV_1M : clk_dvd        
        port map ( CLK      => CLK,
                   RST      => RST,
                   DIV      => x"0032",  -- 50
                   EN       => '1',
                   CLK_OUT  => one_mhz,
                   ONE_SHOT => one_mhz_1
                 );

    -- Divide 1Mhz to Various frequencies for the notes.
    DIV_NOTE : clk_dvd        
        port map ( CLK      => CLK,
                   RST      => RST,
                   DIV      => div,
                   EN       => one_mhz_1,
                   CLK_OUT  => sound,
                   ONE_SHOT => div_1
                 );

    -- Divide 1Mhz to 10k
    DIV_10k : clk_dvd        
        port map ( CLK      => CLK,
                   RST      => RST,
                   DIV      => x"0032", -- 50
                   EN       => one_mhz_1,
                   CLK_OUT  => open,
                   ONE_SHOT => clk_10k_1
                 );

    -- Translate Encoded Note to clock divider for 1MHz clock.
    note_gen_inst : note_gen
        port map ( CLK     => CLK,
                   RST     => RST,
                   NOTE_IN => note_in,
                   DIV     => div
                 );

    -- Wire up seven-seg controller to display current note.
    seven_seg_inst : seven_seg
        port map ( CLK     => CLK,
                   RST     => RST,
                   NOTE_IN => note_in,
                   SCAN_EN => clk_10k_1,
                   DIGIT   => digit_l,
                   SEG     => seg_l
                 );

    -- User Interface
    tempo_gen: 
    process (CLK,RST) begin
        if (RST = '1') then
            beat_counter <= 0;
            playing <= '0';
            beat_tick <= '0';
        elsif (CLK'event and CLK = '1') then
            beat_tick <= '0'; -- Default State

            if (pb(3) = '1') then
                playing <= '1';
            end if;

            -- Tempo counter
            if (playing = '1') then
                if (clk_10k_1 = '1') then
                    if (beat_counter = 4999) then
                        beat_tick <= '1';
                        beat_counter <= 0;
                    else
                        beat_counter <= beat_counter + 1;
                    end if;
                end if;
            else
                beat_counter <= 0; -- Keep counter at 0 if not playing
            end if;
        end if;
    end process;

    index_gen:
    process (CLK,RST) begin
        if (RST = '1') then
            song_index <= 0;
        elsif (CLK'event and CLK = '1') then
            if (playing = '1') then
                if (beat_tick = '1') then -- Move to next note when metronome beats
                    if (song_index = 31) then
                        song_index <= 0 -- Reached the end of the song
                    else
                        song_index <= song_index + 1;
                    end if;
                end if;
            else
                song_index <= 0; -- Keep song index at 0 when not playing
            end if;
        end if;
    end process;

    play_song:
    process (song_index) begin
        case song_index is
            -- Measure 1: E D C D (Quarter notes)
            when 0  => auto_note <= "10101"; -- E4
            when 1  => auto_note <= "10011"; -- D4
            when 2  => auto_note <= "10001"; -- C4
            when 3  => auto_note <= "10011"; -- D4
            
            -- Measure 2: E E E (Quarter, Quarter, Half)
            when 4  => auto_note <= "10101"; -- E4
            when 5  => auto_note <= "10101"; -- E4
            when 6  => auto_note <= "10101"; -- E4 (Half note starts)
            when 7  => auto_note <= "10101"; -- E4 (Half note holds)
            
            -- Measure 3: D D D (Quarter, Quarter, Half)
            when 8  => auto_note <= "10011"; -- D4
            when 9  => auto_note <= "10011"; -- D4
            when 10 => auto_note <= "10011"; -- D4 (Half note starts)
            when 11 => auto_note <= "10011"; -- D4 (Half note holds)
            
            -- Measure 4: E G G (Quarter, Quarter, Half)
            when 12 => auto_note <= "10101"; -- E4
            when 13 => auto_note <= "11000"; -- G4
            when 14 => auto_note <= "11000"; -- G4 (Half note starts)
            when 15 => auto_note <= "11000"; -- G4 (Half note holds)
            
            -- Measure 5: E D C D (Quarter notes)
            when 16 => auto_note <= "10101"; -- E4
            when 17 => auto_note <= "10011"; -- D4
            when 18 => auto_note <= "10001"; -- C4
            when 19 => auto_note <= "10011"; -- D4
            
            -- Measure 6: E E E E (Quarter notes)
            when 20 => auto_note <= "10101"; -- E4
            when 21 => auto_note <= "10101"; -- E4
            when 22 => auto_note <= "10101"; -- E4
            when 23 => auto_note <= "10101"; -- E4
            
            -- Measure 7: D D E D (Quarter notes)
            when 24 => auto_note <= "10011"; -- D4
            when 25 => auto_note <= "10011"; -- D4
            when 26 => auto_note <= "10101"; -- E4
            when 27 => auto_note <= "10011"; -- D4
            
            -- Measure 8: C (Whole note)
            when 28 => auto_note <= "10001"; -- C4
            when 29 => auto_note <= "10001"; -- C4
            when 30 => auto_note <= "10001"; -- C4
            when 31 => auto_note <= "10001"; -- C4
            
            -- Catch-all for safety
            when others => auto_note <= "00000"; -- Silence
        end case;
    end process;
            
    note_in <= note_next;
    audio_output:
    process (CLK,RST) begin
        if (RST = '1') then
            note_next <= (others => '0');
        elsif (CLK'event and CLK = '1') then                        
            if (playing = '1') then
                -- Articulation: Create a small gap of silence between beats
                if (beat_counter > 4000) then
                    note_next <= "00000";   -- Mute for the last 20% of the beat
                else
                    note_next <= auto_note; -- Play the note from the ROM
                end if;
            else
                -- If we haven't pressed Play yet, remain completely silent
                note_next <= "00000"; 
            end if;
        end if;
    end process;
end Behavioral;
