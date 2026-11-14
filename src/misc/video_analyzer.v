//
// video_analyzer.v
//
// try to derive video parameters from hs/vs/de
//

module video_analyzer 
(
 // system interface
 input		  clk,
 input		  hs,
 input		  vs,
 input		  de,
 input		  ntscmode,

 output reg[1:0] mode, // 0=ntsc, 1=pal, 2=mono
 output reg	  vreset
);
   

// Align HDMI with the PDP terminal's 640x480 active area.
reg vsD, hsD;
reg [10:0] hcnt;    // signal ranges 0..1056
reg [10:0] hcntL;
reg [8:0] vcnt;    // signal ranges 0..313
reg [8:0] vcntL;
reg changed;

always @(posedge clk) begin
    // ---- hsync processing -----
    hsD <= hs;
    mode <= {1'b0 , ~ntscmode}; // 0=ntsc, 1=pal, 2=mono

    // begin of hsync, falling edge
    if(!hs && hsD) begin
        // check if line length has changed during last cycle
        hcntL <= hcnt;
        if(hcntL != hcnt)
            changed <= 1'b1;

        hcnt <= 0;
    end else
        hcnt <= hcnt + 11'd1;

    if(!hs && hsD) begin
       // ---- vsync processing -----
       vsD <= vs;
       // begin of vsync, falling edge
       if(!vs && vsD) begin
          // check if image height has changed during last cycle
          vcntL <= vcnt;
          if(vcntL != vcnt) changed <= 1'b1;
          vcnt <= 0;  
       end else
         vcnt <= vcnt + 9'd1;
    end

   // the reset signal is sent to the HDMI generator. On reset the
   // HDMI re-adjusts its counters to the start of the visible screen area
   // 524 total lines minus vsync at line 489 leaves 35 lines to active video.
   // The horizontal offset includes the registered analyzer/OSD/HDMI pipeline.
   vreset <= 1'b0;
   if( 
       (hcnt == 141 && vcnt == 35 && changed && mode == 2'd1) ||
       (hcnt == 141 && vcnt == 35 && changed && mode == 2'd0) ) begin
       vreset <= 1'b1;
       changed <= 1'b0;
   end
end

endmodule
