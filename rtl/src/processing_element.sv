/**
 * Processing Element (PE) for Systolic Array
 * 
 * Implements a single multiply-accumulate (MAC) unit with pipeline registers.
 * 
 * Functionality:
 * - Multiplies 8-bit input A and B (Q4.4 fixed-point)
 * - Accumulates result with incoming partial sum C_in
 * - Broadcasts A to right neighbor (matrix_A_out)
 * - Broadcasts C (accumulation) to bottom neighbor (matrix_C_out)
 * 
 * Pipeline Stages:
 * Stage 1: Input capture (A, B, C_in, valid_in)
 * Stage 2: Multiply (8x8 -> 16-bit product)
 * Stage 3: Accumulate (16-bit + 16-bit -> 16-bit)
 * 
 * Timing: 3-cycle latency from valid_in to valid_out
 */

module processing_element #(
    parameter DATA_WIDTH = 8,      // Input data width (Q4.4 = 8-bit)
    parameter ACC_WIDTH = 16,      // Accumulator width (to avoid overflow)
    parameter INIT_VALUE = 16'b0   // Initial accumulator value
) (
    input  logic                     clk,
    input  logic                     rst_n,
    
    // Input port (from left and top)
    input  logic                     valid_in,
    input  logic [DATA_WIDTH-1:0]    matrix_A_in,      // Data from left (Q)
    input  logic [DATA_WIDTH-1:0]    matrix_B_in,      // Data from top (K^T)
    input  logic [ACC_WIDTH-1:0]     matrix_C_in,      // Partial sum from top
    
    // Output port (to right and bottom)
    output logic                     valid_out,
    output logic [DATA_WIDTH-1:0]    matrix_A_out,     // Forward A to right
    output logic [ACC_WIDTH-1:0]     matrix_C_out      // Forward sum to bottom
);

    // =====================================================================
    // Stage 1: Input Registers (capture A, B, C_in on valid_in)
    // =====================================================================
    logic                     valid_s1;
    logic [DATA_WIDTH-1:0]    A_s1;
    logic [DATA_WIDTH-1:0]    B_s1;
    logic [ACC_WIDTH-1:0]     C_s1;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_s1 <= 1'b0;
            A_s1     <= {DATA_WIDTH{1'b0}};
            B_s1     <= {DATA_WIDTH{1'b0}};
            C_s1     <= {ACC_WIDTH{1'b0}};
        end else begin
            valid_s1 <= valid_in;
            A_s1     <= matrix_A_in;
            B_s1     <= matrix_B_in;
            C_s1     <= matrix_C_in;
        end
    end
    
    // =====================================================================
    // Stage 2: Multiply (8-bit × 8-bit -> 16-bit)
    // =====================================================================
    // Using signed multiplication for Q4.4 fixed-point
    // Result: 16-bit signed product
    
    logic                     valid_s2;
    logic [ACC_WIDTH-1:0]     product_s2;    // 8-bit × 8-bit = 16-bit
    logic [ACC_WIDTH-1:0]     C_s2;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_s2   <= 1'b0;
            product_s2 <= {ACC_WIDTH{1'b0}};
            C_s2       <= {ACC_WIDTH{1'b0}};
        end else begin
            valid_s2   <= valid_s1;
            // Signed multiplication: 8-bit × 8-bit -> 16-bit
            product_s2 <= $signed(A_s1) * $signed(B_s1);
            C_s2       <= C_s1;
        end
    end
    
    // =====================================================================
    // Stage 3: Accumulate (product + C_s2 -> 16-bit result with saturation)
    // =====================================================================
    logic                     valid_s3;
    logic [ACC_WIDTH-1:0]     accumulator;
    
    // Saturation logic: prevent overflow in accumulation
    logic [ACC_WIDTH:0]       sum_with_overflow;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_s3   <= 1'b0;
            accumulator <= INIT_VALUE;
        end else begin
            valid_s3 <= valid_s2;
            
            // Add product to partial sum with overflow detection
            sum_with_overflow = $signed(product_s2) + $signed(C_s2);
            
            // Saturate to 16-bit range if overflow occurs
            if (sum_with_overflow[ACC_WIDTH] != sum_with_overflow[ACC_WIDTH-1]) begin
                // Overflow detected: saturate
                if (sum_with_overflow[ACC_WIDTH]) begin
                    accumulator <= {1'b0, {(ACC_WIDTH-1){1'b1}}};  // Max positive
                end else begin
                    accumulator <= {1'b1, {(ACC_WIDTH-1){1'b0}}};  // Min negative
                end
            end else begin
                // No overflow: store result
                accumulator <= sum_with_overflow[ACC_WIDTH-1:0];
            end
        end
    end
    
    // =====================================================================
    // Output Assignment
    // =====================================================================
    assign valid_out    = valid_s3;
    assign matrix_A_out = A_s1;        // Forward A to right neighbor
    assign matrix_C_out = accumulator;  // Forward accumulation to bottom neighbor

endmodule : processing_element
