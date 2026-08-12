module data_memory #(
    parameter MEM_SIZE = 2048
)(
    input  wire clk,
    input  wire MemWrite,
    input  wire MemRead,
    input wire [2:0]funct3,
    //tells WHAT KIND/SIZE of memory operation shd be done 
    input  wire [31:0] mem_addr,
    input  wire [31:0] rs2_data,
    output reg [31:0] mem_rdata
);

    reg [31:0] memory [0:MEM_SIZE-1];

    wire [31:0]word_index;
    //tells abt which 32-bit word to select
    wire [1:0]byte_offset;
    //tells which byte to select inside tht word 
    assign word_index  = mem_addr >> 2;
    assign byte_offset = mem_addr[1:0];


    initial begin
        $readmemh("hardware/src/core/mem/data.hex", memory);
    end

    // Asynchronous Read
    always @(*) begin
        mem_rdata =32'b0;
        if(MemRead) begin
            case(funct3)
                // LB - Load Byte, sign extended
            3'b000: begin
                case (byte_offset)
                    2'b00: mem_rdata = {{24{memory[word_index][7]}},
                                         memory[word_index][7:0]};

                    2'b01: mem_rdata = {{24{memory[word_index][15]}},
                                         memory[word_index][15:8]};

                    2'b10: mem_rdata = {{24{memory[word_index][23]}},
                                         memory[word_index][23:16]};

                    2'b11: mem_rdata = {{24{memory[word_index][31]}},
                                         memory[word_index][31:24]};
                endcase
            end

            // LH - Load Halfword, sign extended
            3'b001: begin
                case (byte_offset)
                    2'b00: mem_rdata = {{16{memory[word_index][15]}},
                                         memory[word_index][15:0]};

                    2'b10: mem_rdata = {{16{memory[word_index][31]}},
                                         memory[word_index][31:16]};
                endcase
            end

            // LW - Load Word
            3'b010: begin
                mem_rdata = memory[word_index];
            end

            // LBU - Load Byte, zero extended
            3'b100: begin
                case (byte_offset)
                    2'b00: mem_rdata = {24'b0, memory[word_index][7:0]};

                    2'b01: mem_rdata = {24'b0, memory[word_index][15:8]};

                    2'b10: mem_rdata = {24'b0, memory[word_index][23:16]};

                    2'b11: mem_rdata = {24'b0, memory[word_index][31:24]};
                endcase
            end

            // LHU - Load Halfword, zero extended
            3'b101: begin
                case (byte_offset)
                    2'b00: mem_rdata = {16'b0, memory[word_index][15:0]};

                    2'b10: mem_rdata = {16'b0, memory[word_index][31:16]};
                endcase
            end

            default:
                mem_rdata = 32'b0;

        endcase

        end
    end
    

    // Synchronous Write
    always @(posedge clk) begin
            if (MemWrite) begin

        case (funct3)

            // SB - Store Byte
            3'b000: begin
                case (byte_offset)
                    2'b00: memory[word_index][7:0]   <= rs2_data[7:0];
                    2'b01: memory[word_index][15:8]  <= rs2_data[7:0];
                    2'b10: memory[word_index][23:16] <= rs2_data[7:0];
                    2'b11: memory[word_index][31:24] <= rs2_data[7:0];
                endcase
            end

            // SH - Store Halfword
            3'b001: begin
                case (byte_offset)
                    2'b00: memory[word_index][15:0]  <= rs2_data[15:0];
                    2'b10: memory[word_index][31:16] <= rs2_data[15:0];
                endcase
            end

            // SW - Store Word
            3'b010: begin
                memory[word_index] <= rs2_data;
            end

            default: begin
                // No valid store operation
            end

        endcase
    end
end

endmodule