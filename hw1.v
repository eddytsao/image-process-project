module BS(
    input clk1,
    input clk2,  
    input rst_n,
    input [23:0] DPi,
    input pass,
    input [2:0] Sync_720p,
    input [2:0] Sync_1080p,
    output reg [26:0] DPo
);

// 縮放參數計算
// 720p -> 1080p: 1280->1920 (1.5x), 720->1080 (1.5x)
// 反向映射: 1080p座標 -> 720p座標
// scale = 1280/1920 = 2/3, 720/1080 = 2/3
// 使用 16位定點數: 2/3 * 65536 = 43690

parameter SCALE_X = 16'd43690; // 2/3 * 65536
parameter SCALE_Y = 16'd43690; // 2/3 * 65536

// 時序檢測暫存器
reg [2:0] sync_720p_d1, sync_720p_d2;
reg [2:0] sync_1080p_d1, sync_1080p_d2;

// 720p 計數器
reg [11:0] h_cnt_in;
reg [10:0] v_cnt_in;  
reg de_in, vs_in, hs_in;
reg frame_start_in, line_end_in;

// 1080p 計數器
reg [11:0] h_cnt_out;
reg [10:0] v_cnt_out;
reg de_out, vs_out, hs_out;

// Line Buffer 控制
reg [1:0] line_buf_state;
reg line_buf_switch;
reg [10:0] wr_addr, rd_addr1, rd_addr2;
reg wr_en1, wr_en2;
reg [23:0] wr_data;

// 三個記憶體：兩個 line buffer + 一個輔助緩存
wire [23:0] line_data1, line_data2, aux_data;

// Line Buffer 1 (當前行)
MEM2048X24 line_buffer1(
    .CK(clk1),
    .CS(1'b1),
    .WEB(wr_en1),
    .RE(1'b1),
    .R_ADDR(rd_addr1),
    .W_ADDR(wr_addr),
    .D_IN(wr_data),
    .D_OUT(line_data1)
);

// Line Buffer 2 (前一行)
MEM2048X24 line_buffer2(
    .CK(clk1),
    .CS(1'b1),
    .WEB(wr_en2),
    .RE(1'b1),
    .R_ADDR(rd_addr2),
    .W_ADDR(wr_addr),
    .D_IN(wr_data),
    .D_OUT(line_data2)
);

// 輔助緩存 (用於跨時脈域)
MEM2048X24 aux_buffer(
    .CK(clk2),
    .CS(1'b1),
    .WEB(1'b0),
    .RE(1'b1),
    .R_ADDR(rd_addr1),
    .W_ADDR(11'b0),
    .D_IN(24'b0),
    .D_OUT(aux_data)
);

//=================================================================================
// 720p 輸入時脈域處理
//=================================================================================

always @(posedge clk1 or negedge rst_n) begin
    if (!rst_n) begin
        sync_720p_d1 <= 0;
        sync_720p_d2 <= 0;
        h_cnt_in <= 0;
        v_cnt_in <= 0;
        de_in <= 0;
        vs_in <= 0;
        hs_in <= 0;
        frame_start_in <= 0;
        line_end_in <= 0;
        line_buf_state <= 0;
        line_buf_switch <= 0;
        wr_addr <= 0;
        wr_en1 <= 0;
        wr_en2 <= 0;
        wr_data <= 0;
    end else begin
        // 同步訊號延遲鏈
        sync_720p_d2 <= sync_720p_d1;
        sync_720p_d1 <= Sync_720p;
        
        // 提取時序訊號
        vs_in <= Sync_720p[0];
        hs_in <= Sync_720p[1]; 
        de_in <= Sync_720p[2];
        
        // 檢測幀開始
        frame_start_in <= (!sync_720p_d1[0] && Sync_720p[0]);
        
        // 檢測行結束
        line_end_in <= (sync_720p_d1[2] && !Sync_720p[2]);
        
        // 水平計數器
        if (!vs_in) begin
            h_cnt_in <= 0;
        end else if (!hs_in) begin
            h_cnt_in <= 0;
        end else if (de_in && h_cnt_in < 1279) begin
            h_cnt_in <= h_cnt_in + 1;
        end
        
        // 垂直計數器
        if (!vs_in) begin
            v_cnt_in <= 0;
            line_buf_state <= 0;
        end else if (line_end_in && v_cnt_in < 719) begin
            v_cnt_in <= v_cnt_in + 1;
            line_buf_switch <= ~line_buf_switch;
        end
        
        // Line Buffer 寫入控制
        if (de_in && h_cnt_in < 1280 && v_cnt_in < 720) begin
            wr_addr <= h_cnt_in[10:0];
            wr_data <= DPi;
            
            if (line_buf_switch) begin
                wr_en1 <= 1;
                wr_en2 <= 0;
            end else begin
                wr_en1 <= 0;
                wr_en2 <= 1;
            end
        end else begin
            wr_en1 <= 0;
            wr_en2 <= 0;
        end
    end
end

//=================================================================================
// 1080p 輸出時脈域處理
//=================================================================================

// 映射座標計算暫存器
reg [31:0] src_x_fixed, src_y_fixed;
reg [15:0] src_x_int, src_y_int;
reg [15:0] src_x_frac, src_y_frac;
reg [11:0] src_x, src_x_p1;
reg [10:0] src_y, src_y_p1;

// 雙線性插值暫存器
reg [23:0] p00, p01, p10, p11;
reg [7:0] r00, g00, b00, r01, g01, b01;
reg [7:0] r10, g10, b10, r11, g11, b11;
reg [31:0] r_interp, g_interp, b_interp;
reg [23:0] result_pixel;

// Pipeline 暫存器
reg [2:0] sync_pipe [0:3];
reg valid_pipe [0:3];
reg [23:0] pixel_pipe [0:3];

integer i;

always @(posedge clk2 or negedge rst_n) begin
    if (!rst_n) begin
        sync_1080p_d1 <= 0;
        sync_1080p_d2 <= 0;
        h_cnt_out <= 0;
        v_cnt_out <= 0;
        de_out <= 0;
        vs_out <= 0;
        hs_out <= 0;
        DPo <= 0;
        
        src_x_fixed <= 0;
        src_y_fixed <= 0;
        src_x_int <= 0;
        src_y_int <= 0;
        src_x_frac <= 0;
        src_y_frac <= 0;
        
        for (i = 0; i < 4; i = i + 1) begin
            sync_pipe[i] <= 0;
            valid_pipe[i] <= 0;
            pixel_pipe[i] <= 0;
        end
        
        result_pixel <= 0;
    end else begin
        // 同步訊號處理
        sync_1080p_d2 <= sync_1080p_d1;
        sync_1080p_d1 <= Sync_1080p;
        
        vs_out <= Sync_1080p[0];
        hs_out <= Sync_1080p[1];
        de_out <= Sync_1080p[2];
        
        // 1080p 計數器
        if (!vs_out) begin
            h_cnt_out <= 0;
            v_cnt_out <= 0;
        end else if (!hs_out) begin
            h_cnt_out <= 0;
        end else if (de_out && h_cnt_out < 1919) begin
            h_cnt_out <= h_cnt_out + 1;
        end else if (!de_out && sync_1080p_d1[2]) begin
            if (v_cnt_out < 1079)
