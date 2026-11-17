module keyboard(
   input clk,
   input reset,
   input [7:0] usb_kbd,
   input kbd_strobe,
   output reg [7:0] data,
   output reg valid,
   input ready
   );

   reg old_kbd_strobe;
   reg [7:0] usb_kbd_d, usb_kbd_d1;

   always @(posedge clk) begin
      old_kbd_strobe <= kbd_strobe;
      if (old_kbd_strobe != kbd_strobe) 
           usb_kbd_d <= usb_kbd;
   end

   // state: one hot encoding
   // idle is the normal state, reading USB keyboard events
   // key up/down are for key events
   // esc_char is for sending ESC- prefixed chars
   localparam state_idle        = 5'b00001;
   localparam state_key_down    = 5'b00100;
   localparam state_key_up      = 5'b01000;
   localparam state_esc_char    = 5'b10000;

   localparam esc = 8'h1b;

   localparam keycode_regular = 2'b0x;
   localparam keycode_modifier = 2'b10;
   localparam keycode_escaped = 2'b11;

   reg [4:0] state;
   reg [6:0] usb_keycode;
   // shift, control & meta key status, bit order:
   // lshift, lcontrol, lmeta, rmeta, rcontrol, rshift
   // alt/meta key status, vt52 doesn't have meta, but I want to use
   // emacs & can't stand that Esc- business, so alt sends esc+keypress
   reg [5:0] modifier_pressed;
   wire shift_pressed = modifier_pressed[5] || modifier_pressed[0];
   wire control_pressed = modifier_pressed[4] || modifier_pressed[1];
   wire meta_pressed = modifier_pressed[3] || modifier_pressed[2];
   // caps lock
   reg caps_lock_active;
   // keymap
   wire [10:0] keymap_address;
   wire [7:0] keymap_data;
   // special char to send after ESC
   reg [7:0] special_data;

   // The USB HID usage is zero-extended to the keymap's 8-bit key field.
   assign keymap_address = { 1'b0, caps_lock_active, shift_pressed, 1'b0, usb_keycode };

   // data is on of
   // 0xxxxxxx: regular ASCII key
   // 10xxxxxx: control/meta/shift or caps lock, each bit is a key, all 0 for caps lock
   // 11xxxxxx: special key, ESC + upper case ASCII (clear msb to get char)
   keymap_rom keymap_rom(.clk(clk),
                         .addr(keymap_address),
                         .dout(keymap_data)
                         );

reg old_kbd_strobe_d;
   // we don't need to do this on the pixel clock, we could use
   // something way slower, but it works
   always @(posedge clk) begin
      if (reset) begin
         state <= state_idle;

         data <= 0;
         valid <= 0;

         usb_keycode <= 0;

         modifier_pressed = 6'h00;
         caps_lock_active <= 1;  // default caps lock active to get capital characters
         special_data <= 0;
      end
      else if (valid) begin
         if (ready)
            valid <= 0;
      end
      else begin
        old_kbd_strobe_d <= old_kbd_strobe;
        usb_kbd_d1 <= usb_kbd_d;
        case (state)
          state_idle: begin
            if (old_kbd_strobe != old_kbd_strobe_d) begin
                  usb_keycode <= usb_kbd_d[6:0];
                  if ( usb_kbd_d1[7] ) begin
                     state <= state_key_up;
                  end
                  else begin
                     state <= state_key_down;
                  end
             end
          end
          state_key_up: begin
             // on key up we only care about released modifiers
             state <= state_idle;
             if (keymap_data[7:6] == keycode_modifier) begin
                // the released modifier is in keymap_data[5:0]
                // or 0 for caps lock
                modifier_pressed <= modifier_pressed & ~keymap_data[5:0];
             end
          end
          state_key_down: begin
             if (keymap_data == 0) begin
                // unrecognized key, just go back to idle
                state <= state_idle;
             end
             else begin
                casex (keymap_data[7:6])
                  keycode_regular: begin
                     // regular key, apply modifiers:
                     // control turns off 7th & 6th bits
                     // meta sends an ESC prefix
                     if (meta_pressed) begin
                        data <= esc;
                        valid <= 1;
                        state <= state_esc_char;
                        special_data <= {
                                         1'b0,
                                         control_pressed? 2'b00 : keymap_data[6:5],
                                         keymap_data[4:0]
                                         };
                     end
                     else begin
                        data <= {
                                 1'b0,
                                 control_pressed? 2'b00 : keymap_data[6:5],
                                 keymap_data[4:0]
                                 };
                        valid <= 1;
                        state <= state_idle;
                     end
                  end
                  keycode_escaped: begin
                     // escaped char, send Esc- and then the ascii value
                     // including the leading 1 (only uppercase and some symbols)
                     data <= esc;
                     valid <= 1;
                     state <= state_esc_char;
                     special_data <= {
                                      1'b0,
                                      control_pressed? 2'b00 : keymap_data[6:5],
                                      keymap_data[4:0]
                                      };
                  end
                  keycode_modifier: begin
                     // the pressed modifier is in keymap_data[5:0], or 0 for caps lock
                     state <= state_idle;
                     modifier_pressed <= modifier_pressed | keymap_data[5:0];
                     caps_lock_active <= caps_lock_active ^ ~|keymap_data[5:0];
                  end
                endcase
             end // else: !if(keymap_data == 0)
          end // case: state_key_down
          state_esc_char: begin
             // only send special char after ESC was successfully sent
             if (valid == 0) begin
                state <= state_idle;
                data <= {
                         1'b0,
                         control_pressed? 2'b00 : special_data[6:5],
                         special_data[4:0]
                         };
                valid <= 1;
             end
          end
            endcase // case (state)
      end // else: !if(valid)
   end // always @ (posedge clk)
endmodule
