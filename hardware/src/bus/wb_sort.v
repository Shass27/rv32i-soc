module wb_sort (
    input  wire        i_wb_clk,
    input  wire        i_wb_rst,
    input wire         i_mem_grant,
    input  wire [31:0] i_wb_adr,
    input  wire [31:0] i_wb_dat,
    input  wire        i_wb_we,
    input  wire        i_wb_stb,
    input  wire        i_wb_cyc,

    output reg  [31:0] o_wb_dat,
    output reg         o_wb_ack,
    output reg         o_wb_err,
        // Data memory Port B interface
    output reg         o_mem_we,
    output reg  [31:0] o_mem_addr,
    output reg  [31:0] o_mem_wdata,
    input  wire [31:0] i_mem_rdata
);

  
    // SORT CONTROL REGISTERS
    
    reg [31:0] src_addr;
    reg [31:0] dst_addr;
    reg [31:0] length;

    reg        start;
    reg        busy;
    reg        done;
        // Merge-sort FSM states
localparam IDLE            = 4'd0;
localparam INIT            = 4'd1;
localparam PREPARE         = 4'd2;
localparam MERGE           = 4'd3;
localparam READ_LEFT       = 4'd4;
localparam READ_RIGHT      = 4'd5;
localparam READ_SINGLE_L   = 4'd6;
localparam READ_SINGLE_R   = 4'd7;
localparam WRITE_OUT       = 4'd8;
localparam ADVANCE         = 4'd9;
localparam PASS_DONE       = 4'd10;
localparam COPY_READ       = 4'd11;
localparam COPY_WRITE      = 4'd12;
localparam COPY_NEXT       = 4'd13;
localparam FINISH          = 4'd14;




    reg [3:0] state;

    reg [31:0] left_addr;
    reg [31:0] right_addr;
    reg [31:0] out_addr;

    reg [31:0] left_data;
    reg [31:0] right_data;

    reg [31:0] width;
    reg [31:0] i;
    reg [31:0] j;
    reg [31:0] k;
    reg [31:0] mid;
    reg [31:0] right;
    reg [31:0] p;
    reg [31:0] q;
    reg [31:0] src_base;
    reg [31:0] dst_base;
    reg        copy_back;
    reg [31:0] selected_data;
    reg [31:0] copy_src_base;
   
    // WISHBONE RESPONSE
  

    always @(posedge i_wb_clk) begin

        if (i_wb_rst) begin
            o_wb_ack <= 1'b0;
            o_wb_err <= 1'b0;
            o_wb_dat <= 32'b0;
            o_mem_we    <= 1'b0;
            o_mem_addr  <= 32'b0;
            o_mem_wdata <= 32'b0;

            src_addr <= 32'b0;
            dst_addr <= 32'b0;
            length   <= 32'b0;

            start <= 1'b0;
            busy  <= 1'b0;
            done  <= 1'b0;
            state      <= IDLE;
            width      <= 32'd1;
            i          <= 32'd0;
            j          <= 32'd0;
            k          <= 32'd0;

            left_addr  <= 32'd0;
            right_addr <= 32'd0;
            out_addr   <= 32'd0;
            left_data  <= 32'd0;
            right_data <= 32'd0;
            mid          <= 32'd0;
            right        <= 32'd0;
            p            <= 32'd0;
            q            <= 32'd0;
            src_base     <= 32'd0;
            dst_base     <= 32'd0;
            copy_back    <= 1'b0;
            selected_data <= 32'd0;
            copy_src_base <= 32'd0;
        end else begin

            // Default: no response
            o_wb_ack <= 1'b0;
            o_wb_err <= 1'b0;

            // START is a one-cycle pulse
            start <= 1'b0;

         
            // Wishbone access
            
            if (i_wb_cyc && i_wb_stb) begin

                o_wb_ack <= 1'b1;

                if (i_wb_we) begin

                    case (i_wb_adr[5:2])

                        4'h0: src_addr <= i_wb_dat;   // 0x00
                        4'h1: dst_addr <= i_wb_dat;   // 0x04
                        4'h2: length   <= i_wb_dat;   // 0x08

                        4'h3: begin                   // 0x0C
                            if (i_wb_dat[0])
                                start <= 1'b1;
                        end

                        default: begin
                            // Ignore writes to undefined registers
                        end

                    endcase

                end else begin

                    case (i_wb_adr[5:2])

                        4'h0: o_wb_dat <= src_addr;
                        4'h1: o_wb_dat <= dst_addr;
                        4'h2: o_wb_dat <= length;

                        4'h3: o_wb_dat <= {31'b0, start};

                        4'h4: o_wb_dat <= {30'b0, done, busy};

                        default: o_wb_dat <= 32'b0;

                    endcase

                end
            end
                        // Default: no memory write unless a state requests one
            if (i_mem_grant)
                o_mem_we <= 1'b0;
            if (i_mem_grant ||
            state == IDLE       ||
            state == INIT       ||
            state == PREPARE    ||
            state == ADVANCE    ||
            state == PASS_DONE  ||
            state == FINISH) begin



            case (state)

                IDLE: begin
                    busy <= 1'b0;

                    if (start) begin
                        busy      <= 1'b1;
                        done      <= 1'b0;
                        width     <= 32'd1;
                        i         <= 32'd0;
                        src_base  <= src_addr;
                        dst_base  <= dst_addr;
                        state     <= INIT;
                    end
                end

                INIT: begin
                    if (length == 0) begin
                        state <= FINISH;
                    end
                    else if (length == 1) begin
                        if (src_addr == dst_addr)
                            state <= FINISH;
                        else begin
                            copy_src_base <= src_addr;
                            k <= 0;
                            state <= COPY_READ;
                        end
                    end
                    else begin
                        state <= PREPARE;
                    end
                end

                PREPARE: begin
                    if (i >= length) begin
                        state <= PASS_DONE;
                    end
                    else begin
                        mid <= ((i + width) < length)
                             ? (i + width) : length;

                        right <= ((i + (width << 1)) < length)
                               ? (i + (width << 1)) : length;

                        p <= i;
                        q <= ((i + width) < length)
                           ? (i + width) : length;
                        k <= i;
                        state <= MERGE;
                    end
                end

                MERGE: begin
                    if ((p < mid) && (q < right)) begin
                        o_mem_addr <= src_base + (p << 2);
                        state <= READ_LEFT;
                    end
                    else if (p < mid) begin
                        o_mem_addr <= src_base + (p << 2);
                        state <= READ_SINGLE_L;
                    end
                    else if (q < right) begin
                        o_mem_addr <= src_base + (q << 2);
                        state <= READ_SINGLE_R;
                    end
                    else begin
                        state <= ADVANCE;
                    end
                end

                READ_LEFT: begin
                    left_data <= i_mem_rdata;
                    o_mem_addr <= src_base + (q << 2);
                    state <= READ_RIGHT;
                end

                READ_RIGHT: begin
                    o_mem_addr <= dst_base + (k << 2);

                    if (left_data <= i_mem_rdata) begin
                        o_mem_wdata <= left_data;
                        p <= p + 1;
                    end
                    else begin
                        o_mem_wdata <= i_mem_rdata;
                        q <= q + 1;
                    end

                    o_mem_we <= 1'b1;
                    k <= k + 1;
                    state <= WRITE_OUT;
                end

                READ_SINGLE_L: begin
                    o_mem_addr <= dst_base + (k << 2);
                    o_mem_wdata <= i_mem_rdata;
                    o_mem_we <= 1'b1;
                    p <= p + 1;
                    k <= k + 1;
                    state <= WRITE_OUT;
                end

                READ_SINGLE_R: begin
                    o_mem_addr <= dst_base + (k << 2);
                    o_mem_wdata <= i_mem_rdata;
                    o_mem_we <= 1'b1;
                    q <= q + 1;
                    k <= k + 1;
                    state <= WRITE_OUT;
                end

                WRITE_OUT: begin
                    state <= ADVANCE;
                end

                ADVANCE: begin
                    if (k >= right) begin
                        i <= right;
                        state <= PREPARE;
                    end
                    else begin
                        state <= MERGE;
                    end
                end

                PASS_DONE: begin
                    if ((width << 1) >= length) begin
                        if (dst_base == dst_addr) begin
                            state <= FINISH;
                        end
                        else begin
                            copy_src_base <= dst_base;
                            k <= 0;
                            state <= COPY_READ;
                        end
                    end
                    else begin
                        src_base <= dst_base;
                        dst_base <= src_base;
                        width <= width << 1;
                        i <= 0;
                        state <= PREPARE;
                    end
                end

                COPY_READ: begin
                    o_mem_addr <= copy_src_base + (k << 2);
                    state <= COPY_WRITE;
                end

                COPY_WRITE: begin
                    o_mem_addr <= dst_addr + (k << 2);
                    o_mem_wdata <= i_mem_rdata;
                    o_mem_we <= 1'b1;
                    state <= COPY_NEXT;
                end

                COPY_NEXT: begin
                    if ((k + 1) >= length) begin
                        state <= FINISH;
                    end
                    else begin
                        k <= k + 1;
                        state <= COPY_READ;
                    end
                end

                FINISH: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    state <= IDLE;
                end

                default: begin
                    state <= IDLE;
                    busy <= 1'b0;
                end

            endcase
          end
        end
    end

endmodule