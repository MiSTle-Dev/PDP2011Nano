/**
 * Character Font ROM (4kx8)
 * This could be a RAM to allow font modifications, but not for now
 * latin-1 subset of Terminus Font 8x16 (http://terminus-font.sourceforge.net)
 * Terminus Font is licensed under the SIL Open Font License, Version 1.1.
 * The license is included as ofl.txt, and is also available with a FAQ
 * at http://scripts.sil.org/OFL
 */
module char_rom
  (input  clk,
   input  [11:0] addr,
   output  [7:0] dout,
   input graphic_character
   );

   reg [7:0] mem [4095:0];
   // Thirty 8x16 graphics glyphs, one byte per row (30 x 16 = 480 entries);
   // these are selected for character codes E1 through FE.
   reg [7:0] graphics_mem [0:479];

   reg [7:0] font_q;
   reg [7:0] graphic_q;
   reg       graphic_sel_q;

   wire       glyph_sel = graphic_character && addr[11:4] >= 8'he1 &&
                          addr[11:4] <= 8'hfe;
   wire [8:0] glyph_index = {addr[8:4] - 5'd1, addr[3:0]};

   initial begin
      $readmemh("terminus_816_latin1.hex", mem) ;
      $readmemh("vt52_graphics_816_bytes.hex", graphics_mem);
//      $readmemh("terminus_816_bold_latin1.hex", mem) ;
   end

   // Synchronous reads with registered outputs so both ROMs map to block RAM.
   always @(posedge clk) begin
      font_q        <= mem[addr];
      graphic_q     <= graphics_mem[glyph_index];
      graphic_sel_q <= glyph_sel;
   end

   assign dout = graphic_sel_q ? graphic_q : font_q;

endmodule
