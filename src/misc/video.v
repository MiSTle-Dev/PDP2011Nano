// video.v

module video (
          input	   clk,
          input    clk_pixel_x5,
          input    pll_lock,
          input [8:0] audio_div,
          input    ntscmode,
          input    vb_in,
          input    hb_in,
	      input	   vs_in_n,
	      input	   hs_in_n,

	      input [3:0]  r_in,
	      input [3:0]  g_in,
	      input [3:0]  b_in,

          input [17:0] audio_l,
          input [17:0] audio_r,

          output osd_status,

          // (spi) interface from MCU
          input	   mcu_start,
          input	   mcu_osd_strobe,
          input [7:0]  mcu_data,

          // values that can be configure by the user via osd          
          input [1:0]  system_scanlines,
          input [1:0]  system_volume,
          input	       system_wide_screen,

	      // hdmi/tdms
	      output	   tmds_clk_n,
	      output	   tmds_clk_p,
	      output [2:0] tmds_d_n,
	      output [2:0] tmds_d_p  
	      );
   
/* -------------------- HDMI video (no audio) -------------------- */

reg vresetD;

wire vreset;
wire [1:0] vmode;

video_analyzer video_analyzer (
   .clk(clk),
   .vs(vs_in_n),
   .hs(hs_in_n),
   .de(1'b1),
   .ntscmode(ntscmode),
   .mode(vmode),
   .vreset(vreset)
);  


wire [5:0] osd_r;
wire [5:0] osd_g;
wire [5:0] osd_b;

osd_u8g2 osd_u8g2 (
        .clk(clk),
        .reset(!pll_lock),

        .data_in_strobe(mcu_osd_strobe),
        .data_in_start(mcu_start),
        .data_in(mcu_data),

        .hs(hs_in_n),
        .vs(vs_in_n),
		     
        .r_in({r_in,2'b0}),
        .g_in({g_in,2'b0}),
        .b_in({b_in,2'b0}),
		     
        .r_out(osd_r),
        .g_out(osd_g),
        .b_out(osd_b),
        .osd_status(osd_status)
);   

wire [2:0] tmds;
wire tmds_clock;

hdmi #(
   .AUDIO_ENABLE(0),
   .AUDIO_RATE(48000), 
   .AUDIO_BIT_WIDTH(16),
   .VENDOR_NAME( { "MiSTle", 16'd0} ),
   .PRODUCT_DESCRIPTION( {"C64", 64'd0} )
) hdmi(
  .clk_pixel_x5(clk_pixel_x5),
  .clk_pixel(clk),
  .clk_audio(1'b0),
  .audio_sample_word( '{16'd0, 16'd0} ),
  .tmds(tmds),
  .tmds_clock(tmds_clock),

  // video input
  .stmode(vmode),    // current video mode PAL/NTSC/MONO
  .wide(system_wide_screen),       // adopt to wide screen video
  .reset(vreset),    // signal to synchronize HDMI
  // Atari STE outputs 4 bits per color. Scandoubler outputs 6 bits (to be
  // able to implement dark scanlines) and HDMI expects 8 bits per color
  .rgb( { osd_r, 2'b00, osd_g, 2'b00, osd_b, 2'b00 } )
);

// differential output
ELVDS_OBUF tmds_bufds [3:0] (
        .I({tmds_clock, tmds}),
        .O({tmds_clk_p, tmds_d_p}),
        .OB({tmds_clk_n, tmds_d_n})
);

endmodule
