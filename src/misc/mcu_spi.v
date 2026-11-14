/*
    mcu_spi.v
 
    SPI version of MCU interface 
*/

module mcu_spi (
  input        clk,
  input        reset,

  // SPI interface to MCU
  input        spi_io_ss,
  input        spi_io_clk,
  input        spi_io_din,
  output reg   spi_io_dout,

  // byte interface to the various core components
  output       mcu_sys_strobe, // byte strobe for system control target  
  output       mcu_hid_strobe, // byte strobe for HID target  
  output       mcu_osd_strobe, // byte strobe for OSD target
  output       mcu_sdc_strobe, // byte strobe for SD card target
  output       mcu_start,
  input  [7:0] mcu_sys_din,
  input  [7:0] mcu_hid_din,
  input  [7:0] mcu_osd_din,
  input  [7:0] mcu_sdc_din,
  output [7:0] mcu_dout
);
   
// SPI runs in MODE1 
// -> idle state of data is low
// -> data is setup on rising clock edge
// -> data is read on falling clock edge

// bit/byte counter
reg [2:0] spi_cnt;
reg spi_target_pending;
reg spi_first_payload;
reg [7:0] spi_target;

reg [7:0] spi_data_in;
reg [6:0] spi_sr_in;
reg [7:0] spi_data_target;
reg spi_data_first;
reg spi_data_toggle;
wire spi_frame_reset = reset || spi_io_ss;

// read data on falling edge of spi clock
always @(negedge spi_io_clk or posedge spi_frame_reset) begin
    if(spi_frame_reset) begin
        spi_cnt <= 0;
        spi_target_pending <= 1;
        spi_first_payload <= 1;
        spi_sr_in <= 0;
        spi_target <= 0;
    end else begin
        spi_cnt <= spi_cnt + 3'd1;
        spi_sr_in <= { spi_sr_in[5:0], spi_io_din };
        if(spi_cnt == 3'd7) begin
            if(spi_target_pending) begin
                spi_target <= {spi_sr_in, spi_io_din};
                spi_target_pending <= 0;
            end else begin
                spi_first_payload <= 0;
            end
        end
    end
end

// Completed bytes survive CS release until the system clock consumes them.
always @(negedge spi_io_clk or posedge reset) begin
    if(reset) begin
        spi_data_in <= 0;
        spi_data_target <= 0;
        spi_data_first <= 0;
        spi_data_toggle <= 0;
    end else if(!spi_io_ss && spi_cnt == 3'd7 && !spi_target_pending) begin
        spi_data_in <= {spi_sr_in, spi_io_din};
        spi_data_target <= spi_target;
        spi_data_first <= spi_first_payload;
        spi_data_toggle <= ~spi_data_toggle;
    end
end
   
// bring received byte into local clock domain
  
reg spi_in_strobe;
reg [7:0] spi_in_target;
assign mcu_sys_strobe = spi_in_strobe && spi_in_target == 8'd0;
assign mcu_hid_strobe = spi_in_strobe && spi_in_target == 8'd1;
assign mcu_osd_strobe = spi_in_strobe && spi_in_target == 8'd2;
assign mcu_sdc_strobe = spi_in_strobe && spi_in_target == 8'd3;

reg spi_in_first;
reg [1:0] spi_toggle_sync;
reg spi_toggle_seen;
reg [7:0] spi_in_data;
assign mcu_start = spi_in_first;
assign mcu_dout = spi_in_data;
     
always @(posedge clk or posedge reset) begin
    if(reset) begin
        spi_toggle_sync <= 0;
        spi_toggle_seen <= 0;
        spi_in_strobe <= 0;
        spi_in_target <= 0;
        spi_in_first <= 0;
        spi_in_data <= 0;
    end else begin
        spi_toggle_sync <= {spi_toggle_sync[0], spi_data_toggle};
        spi_in_strobe <= 0;
        if(spi_toggle_sync[1] != spi_toggle_seen) begin
            spi_toggle_seen <= spi_toggle_sync[1];
            spi_in_strobe <= 1;
            spi_in_target <= spi_data_target;
            spi_in_first <= spi_data_first;
            spi_in_data <= spi_data_in;
        end
    end
end

wire [7:0] in_byte = 
	   (spi_target == 8'd0)?mcu_sys_din:
	   (spi_target == 8'd1)?mcu_hid_din:
	   (spi_target == 8'd2)?mcu_osd_din:
	   (spi_target == 8'd3)?mcu_sdc_din:
	   8'h00;   
   
// setup data on rising edge of spi clock
always @(posedge spi_io_clk or posedge spi_frame_reset) begin
    if(spi_frame_reset) begin
       spi_io_dout <= 1'b0; // bl616 EN_CHIP fix
    end else begin
       spi_io_dout <= in_byte[~spi_cnt[2:0]];
    end
end

endmodule // osd_u8g2
