/*
    hid.v
 
    hid (keyboard, mouse etc) interface to the IO MCU
  */

module hid (
  input               clk,
  input               reset,

  input               data_in_strobe,
  input               data_in_start,
  input [7:0]         data_in,
  output reg [7:0]    data_out,

  output reg [7:0]    usb_kbd,
  output reg          kbd_strobe
);


reg [3:0] state;
reg [7:0] command;

// process mouse events
always @(posedge clk) begin
   if(reset) begin
      state <= 4'd0;
      usb_kbd <= 8'h00;
      kbd_strobe <= 1'b0;

   end else begin

      if(data_in_strobe) begin      
        if(data_in_start) begin
            state <= 4'd0;
            command <= data_in;
        end else begin
            if(state != 4'd15) state <= state + 4'd1;

            // CMD 0: status data
            if(command == 8'd0) begin
                if(state == 4'd0) data_out <= 8'h01;
                if(state == 4'd1) data_out <= 8'h00;
            end

            // CMD 1: keyboard data
            if(command == 8'd1) begin
            // kbd_column and kbd_row are derived from data_in
               if(state == 4'd0) begin
                    usb_kbd <= data_in;
                    kbd_strobe <= ~kbd_strobe;
                end
            end
            // CMD 4: send digital joystick data to MCU
            if(command == 8'd4) begin
                if(state == 4'd0);
                data_out <= {8'd0 };
            end
        end
      end
   end
end

endmodule
