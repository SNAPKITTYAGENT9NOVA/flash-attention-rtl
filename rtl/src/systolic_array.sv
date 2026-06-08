/**
 * 8x8 Systolic Array for Matrix Multiplication
 * 
 * Computes matrix product: C = A @ B^T
 * - A: 8×8 matrix (Q tile, broadcast row-wise from left)
 * - B: 8×8 matrix (K^T tile, broadcast column-wise from top)
 * - C: 8×8 output matrix (partial products accumulated bottom-wise)
 * 
 * Dataflow (Systolic):
 * - Input A enters from left, shifts right across rows
 * - Input B enters from top, shifts down across columns
 * - Partial sums propagate downward
 * 
 * Pipeline Stages:
 * - Each PE has 3-stage internal pipeline
 * - Systolic latency: 3 + 8 = 11 cycles (first output valid after 11 cycles)
 * 
 * Data Format:
 * - All data: 8-bit signed fixed-point (Q4.4)
 * - Accumulators: 16-bit signed (to handle multiplication overflow)
 * 
 * Example data flow (first output):
 * Cycle 1:   A[0,0], B[0,0] enter top-left PE
 * Cycles 2-3: Pipelined processing in PE
 * Cycle 4-10: Data propagates to neighbors
 * Cycle 11:   First valid output at C[0,0]
 */

module systolic_array #(
    parameter DATA_WIDTH = 8,      // Input/output data width (Q4.4)
    parameter ACC_WIDTH = 16,      // Accumulator width
    parameter PE_ROWS = 8,         // Number of rows
    parameter PE_COLS = 8          // Number of columns
) (
    input  logic                                        clk,
    input  logic                                        rst_n,
    
    // Control
    input  logic                                        valid_in,
    output logic                                        valid_out,
    
    // Input: A matrix data (from left side, feeds all rows)
    // Array shape: [PE_ROWS][1] - one column (left edge)
    input  logic [PE_ROWS-1:0][DATA_WIDTH-1:0]         matrix_A_in,
    
    // Input: B matrix data (from top side, feeds all columns)
    // Array shape: [1][PE_COLS] - one row (top edge)
    input  logic [PE_COLS-1:0][DATA_WIDTH-1:0]         matrix_B_in,
    
    // Output: C matrix data (from bottom side, all accumulators)
    // Array shape: [PE_ROWS][PE_COLS]
    output logic [PE_ROWS-1:0][PE_COLS-1:0][ACC_WIDTH-1:0] matrix_C_out
);

    // =====================================================================
    // Internal Signals: Systolic Mesh Connections
    // =====================================================================
    
    // A dataflow: row-wise propagation (left to right)
    // shape: [PE_ROWS][PE_COLS+1] - extra column for input
    logic [PE_ROWS-1:0][PE_COLS:0][DATA_WIDTH-1:0] A_mesh;
    
    // B dataflow: column-wise propagation (top to bottom)
    // shape: [PE_ROWS+1][PE_COLS] - extra row for input
    logic [PE_ROWS:0][PE_COLS-1:0][DATA_WIDTH-1:0] B_mesh;
    
    // C dataflow: column-wise propagation (top to bottom)
    // shape: [PE_ROWS+1][PE_COLS]
    logic [PE_ROWS:0][PE_COLS-1:0][ACC_WIDTH-1:0] C_mesh;
    
    // Valid signals: one per PE (for pipeline control)
    logic [PE_ROWS-1:0][PE_COLS-1:0] pe_valid_in;
    logic [PE_ROWS-1:0][PE_COLS-1:0] pe_valid_out;
    
    // =====================================================================
    // Input Boundary Conditions
    // =====================================================================
    
    // A enters from left: A_mesh[:][0] = matrix_A_in[:]
    always_comb begin
        for (int i = 0; i < PE_ROWS; i++) begin
            A_mesh[i][0] = matrix_A_in[i];
        end
    end
    
    // B enters from top: B_mesh[0][:] = matrix_B_in[:]
    always_comb begin
        for (int j = 0; j < PE_COLS; j++) begin
            B_mesh[0][j] = matrix_B_in[j];
        end
    end
    
    // C enters as zeros (partial sums start from zero)
    always_comb begin
        for (int j = 0; j < PE_COLS; j++) begin
            C_mesh[0][j] = {ACC_WIDTH{1'b0}};
        end
    end
    
    // Valid signal broadcast to top-left corner
    always_comb begin
        pe_valid_in[0][0] = valid_in;
        for (int i = 1; i < PE_ROWS; i++) begin
            for (int j = 0; j < PE_COLS; j++) begin
                pe_valid_in[i][j] = 1'b0;  // Only top-left gets valid signal
            end
        end
    end
    
    // =====================================================================
    // Systolic Mesh: Generate and Connect PE Array
    // =====================================================================
    
    generate
        for (genvar i = 0; i < PE_ROWS; i++) begin : gen_rows
            for (genvar j = 0; j < PE_COLS; j++) begin : gen_cols
                
                processing_element #(
                    .DATA_WIDTH(DATA_WIDTH),
                    .ACC_WIDTH(ACC_WIDTH),
                    .INIT_VALUE({ACC_WIDTH{1'b0}})
                ) pe_inst (
                    .clk(clk),
                    .rst_n(rst_n),
                    
                    // Input
                    .valid_in(pe_valid_in[i][j]),
                    .matrix_A_in(A_mesh[i][j]),      // From left
                    .matrix_B_in(B_mesh[i][j]),      // From top
                    .matrix_C_in(C_mesh[i][j]),      // From top
                    
                    // Output
                    .valid_out(pe_valid_out[i][j]),
                    .matrix_A_out(A_mesh[i][j+1]),   // To right
                    .matrix_C_out(C_mesh[i+1][j])    // To bottom
                );
                
                // Extract output: C_out[i][j]
                assign matrix_C_out[i][j] = C_mesh[i+1][j];
            end
        end
    endgenerate
    
    // =====================================================================
    // Output Valid Signal
    // =====================================================================
    // The output is valid when data exits bottom-right corner PE
    // Due to 3-stage PE pipeline, this occurs 3 cycles after bottom-right PE
    // processes data. For an 8x8 array, diagonal propagation takes:
    // 3 (PE internal) + 7 (diagonal to bottom-right) + 3 (output from PE) = 13 cycles
    
    // Simpler approach: use a valid propagation counter
    // valid_out pulses when first block of data reaches output
    
    logic [3:0] valid_counter;  // Count cycles (0-15 sufficient for 13-cycle latency)
    logic       output_valid_q;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_counter <= 4'b0;
            output_valid_q <= 1'b0;
        end else begin
            // Count up to 13 (11 for propagation + 2 for pipeline sync)
            if (valid_in && valid_counter == 4'b0) begin
                valid_counter <= 4'd1;
            end else if (valid_counter > 4'b0 && valid_counter < 4'd13) begin
                valid_counter <= valid_counter + 1'b1;
            end else if (valid_counter == 4'd13) begin
                output_valid_q <= 1'b1;
                valid_counter <= 4'b0;  // Reset for next block
            end else begin
                output_valid_q <= 1'b0;
            end
        end
    end
    
    assign valid_out = output_valid_q;

endmodule : systolic_array
