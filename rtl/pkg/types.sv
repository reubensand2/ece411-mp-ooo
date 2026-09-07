package rv32i_types;

    // GLOBAL PARAMS
    localparam integer unsigned PRF_SIZE = 48;
    localparam integer unsigned PRF_IDX_WIDTH = $clog2(PRF_SIZE);
    localparam integer unsigned PRF_NUM_READ_PORTS = 10;
    localparam integer unsigned PRF_NUM_WRITE_PORTS = 5;

    localparam integer unsigned ROB_SIZE = 16;
    localparam integer unsigned ROB_IDX_WIDTH = $clog2(ROB_SIZE);
    localparam integer unsigned ROB_NUM_UPDATE_PORTS = 1; // i think this aint used
    localparam integer unsigned ROB_NUM_WRITE_PORTS = 6;

    localparam integer unsigned RAT_NUM_READ_PORTS = 2;
    localparam integer unsigned RAT_NUM_WRITE_PORTS = 1;	// cdb passed in, just for dispatch write
	localparam integer unsigned RAT_NUM_SLOTS = 32;

    localparam integer unsigned RRAT_NUM_READ_PORTS = 2;
    localparam integer unsigned RRAT_NUM_WRITE_PORTS = 2;
	localparam integer unsigned RRAT_NUM_SLOTS = 32;

	// localparam integer unsigned LOAD_QUEUE_SIZE = 8;
	localparam integer unsigned STORE_QUEUE_SIZE = 8;
	localparam integer unsigned STORE_BUF_SIZE = 8;


    localparam integer unsigned IQ_SIZE = 32;
    localparam integer unsigned ALU_RES_STATION_SIZE = 12;
    localparam integer unsigned MUL_RES_STATION_SIZE = 3;
    localparam integer unsigned DIV_RES_STATION_SIZE = 2;
    localparam integer unsigned LD_RES_STATION_SIZE = 8;
    localparam integer unsigned BR_RES_STATION_SIZE = 2;
	localparam integer unsigned RS_NUM_WAKEUP_PORTS = 5;

	localparam integer unsigned RISC_ADDR_SIZE_WIDTH = 5;

	localparam integer unsigned GHR_SIZE = 7;
	localparam integer unsigned PHT_SIZE = 128;
	localparam integer unsigned RAS_DEPTH = 16;
	localparam integer unsigned RAS_P_WIDTH = $clog2(RAS_DEPTH);
	localparam integer unsigned JALR_BTB_DEPTH = 16;
	localparam integer unsigned JALR_BTB_INDEX = $clog2(JALR_BTB_DEPTH);


	typedef enum logic [2:0] {
        arith_f3_add   = 3'b000, // check logic 30 for sub if op_reg op
        arith_f3_sll   = 3'b001,
        arith_f3_slt   = 3'b010,
        arith_f3_sltu  = 3'b011,
        arith_f3_xor   = 3'b100,
        arith_f3_sr    = 3'b101, // check logic 30 for logical/arithmetic
        arith_f3_or    = 3'b110,
        arith_f3_and   = 3'b111
    } arith_f3_t;

    typedef enum logic [2:0] {
        load_f3_lb     = 3'b000,
        load_f3_lh     = 3'b001,
        load_f3_lw     = 3'b010,
        load_f3_lbu    = 3'b100,
        load_f3_lhu    = 3'b101
    } load_f3_t;

    typedef enum logic [2:0] {
        store_f3_sb    = 3'b000,
        store_f3_sh    = 3'b001,
        store_f3_sw    = 3'b010
    } store_f3_t;

    typedef enum logic [2:0] {
        branch_f3_beq  = 3'b000,
        branch_f3_bne  = 3'b001,
        branch_f3_blt  = 3'b100,
        branch_f3_bge  = 3'b101,
        branch_f3_bltu = 3'b110,
        branch_f3_bgeu = 3'b111
    } branch_f3_t;
	
	typedef enum logic [2:0] {
		mul    = 3'b000,
		mulh   = 3'b001,
		mulhsu = 3'b010,
		mulhu  = 3'b011,
		div    = 3'b100,
		divu   = 3'b101,
		rem    = 3'b110,
		remu   = 3'b111
	} mul_funct3_t;
	
    typedef enum logic [6:0] {
        op_b_lui       = 7'b0110111, // load upper immediate (U type)
        op_b_auipc     = 7'b0010111, // add upper immediate PC (U type)
        op_b_jal       = 7'b1101111, // jump and link (J type)
        op_b_jalr      = 7'b1100111, // jump and link register (I type)
        op_b_br        = 7'b1100011, // branch (B type)
        op_b_load      = 7'b0000011, // load (I type)
        op_b_store     = 7'b0100011, // store (S type)
        op_b_imm       = 7'b0010011, // arith ops with register/immediate operands (I type)
        op_b_reg       = 7'b0110011  // arith ops with register operands (R type)
    } rv32i_opcode;

	typedef enum logic [2:0] {
        alu_op_add     = 3'b000,
        alu_op_sll     = 3'b001,
        alu_op_sra     = 3'b010,
        alu_op_sub     = 3'b011,
        alu_op_xor     = 3'b100,
        alu_op_srl     = 3'b101,
        alu_op_or      = 3'b110,
        alu_op_and     = 3'b111
    } alu_ops;

	typedef enum logic [2:0] {
		RS_NONE,
		RS_ALU,
		RS_MUL,
		RS_DIV,
		RS_LD,
		RS_SQ,
		RS_BR
	} rs_type_t;

	typedef struct packed {
        logic [31:0]    ufp_addr;
        logic [3:0]     ufp_rmask; 
        logic [3:0]     ufp_wmask; 
        logic [31:0]    ufp_wdata;
        logic           valid;
    } cache_pp_reg_t;

	typedef enum logic [1:0] {
		rs1_out = 2'b00,
		pc_out  = 2'b01,
		zero    = 2'b10
	} alu_m1_sel_t;

	typedef enum logic {
		rs2_out = 1'b0,
		imm_out = 1'b1
	} alu_m2_sel_t;

	typedef struct packed {
		//RVFI data
        logic 			valid;
        logic 	[23:0]	order;
        logic 	[31:0]	inst;
        logic 	[4:0] 	rs1_addr;
        logic 	[4:0] 	rs2_addr;
        logic 	[31:0]	rs1_rdata;
        logic 	[31:0]	rs2_rdata;
        logic 	[4:0] 	rd_addr;
        logic 	[31:0]	rd_wdata;
        logic 	[31:0]	pc_rdata;
        logic 	[31:0]	pc_wdata;
        logic 	[31:0]	mem_addr;
        logic 	[3:0] 	mem_rmask;
        logic 	[3:0] 	mem_wmask;
        logic 	[31:0]	mem_rdata;
        logic 	[31:0]	mem_wdata;
	} rvfi_packet_t;
	  
	typedef struct packed {
		// common signals
		logic valid;
		logic [ROB_IDX_WIDTH-1:0] rob_idx;
		logic [PRF_IDX_WIDTH-1:0] rd_paddr;
		logic rs1_en;
		logic [PRF_IDX_WIDTH-1:0] rs1_paddr;
		logic rs1_ready;
		logic rs2_en;
		logic [PRF_IDX_WIDTH-1:0] rs2_paddr;
		logic rs2_ready;

		// alu specific
		logic [31:0]	alu_imm;     
		alu_ops         aluop;
		alu_m1_sel_t    alu_m1_sel;
		alu_m2_sel_t    alu_m2_sel;
		branch_f3_t		cmpop;
		logic           ctrl_slt;   // 1 = CMP output, 0 = ALU output 

		// RVFI data
		rvfi_packet_t 	rvfi_packet;
	} alu_res_station_entry_t;

	typedef struct packed {
		// common signals
		logic valid;
		logic [ROB_IDX_WIDTH-1:0] rob_idx;
		logic [PRF_IDX_WIDTH-1:0] rd_paddr;

		logic [PRF_IDX_WIDTH-1:0] rs1_paddr;
		logic rs1_ready;

		logic [PRF_IDX_WIDTH-1:0] rs2_paddr;
		logic rs2_ready;

		// mul specific
		logic			rs1_is_signed;
		logic			rs2_is_signed;
		logic			mul_high_bits;
		
		// RVFI data
		rvfi_packet_t 	rvfi_packet;
	} mul_res_station_entry_t;

	typedef struct packed {
		// common signals
		logic valid;
		logic [ROB_IDX_WIDTH-1:0] rob_idx;
		logic [PRF_IDX_WIDTH-1:0] rd_paddr;

		logic [PRF_IDX_WIDTH-1:0] rs1_paddr;
		logic rs1_ready;

		logic [PRF_IDX_WIDTH-1:0] rs2_paddr;
		logic rs2_ready;

		// div specific
		logic			rs1_is_signed;
		logic			rs2_is_signed;
		logic			div_get_rem;
		
		// RVFI data
		rvfi_packet_t 	rvfi_packet;
	} div_res_station_entry_t;

	typedef struct packed {
		logic valid;
		logic [ROB_IDX_WIDTH-1:0] rob_idx;
		logic [PRF_IDX_WIDTH-1:0] rd_paddr;

		
		logic [PRF_IDX_WIDTH-1:0] rs1_paddr;
		logic rs1_ready;
		//tech don't need these
		
		logic [PRF_IDX_WIDTH-1:0] rs2_paddr;
		logic rs2_ready;

		load_f3_t ld_type;
		logic [31:0] imm;

		rvfi_packet_t rvfi_packet;
	} ld_res_station_entry_t;


	typedef struct packed {
        logic valid;
        logic [ROB_IDX_WIDTH-1:0]  rob_idx; //ready or busy

        logic [PRF_IDX_WIDTH-1:0] rs1_paddr;
        logic [PRF_IDX_WIDTH-1:0] rs2_paddr;

		// these are guaranteed to be ready when store is at ROB head
        // logic rs1_en; // signal to check if rs1 is used
        logic rs1_ready; // signal to check if rs1 already ready when putting into dest station
        // logic rs2_en; //signal to check if rs2 is used
        logic rs2_ready; // signal to check if rs2 already ready when putting into dest station

		store_f3_t st_type;
		logic [31:0]	imm;     

        //RVFI data
		rvfi_packet_t 	rvfi_packet;

	} sq_entry_t;

	typedef struct packed {
        logic valid;
        logic [ROB_IDX_WIDTH-1:0]  rob_idx; //ready or busy
		logic [31:0] dmem_addr;
		logic [31:0] dmem_wdata;
		logic [3:0] dmem_wmask;
        //RVFI data
		rvfi_packet_t 	rvfi_packet;

	} sb_entry_t;

	typedef struct packed {
		// common signals
		logic valid;
		logic [ROB_IDX_WIDTH-1:0] rob_idx;
		logic [PRF_IDX_WIDTH-1:0] rd_paddr;
		logic rs1_en;
		logic [PRF_IDX_WIDTH-1:0] rs1_paddr;
		logic rs1_ready;
		logic rs2_en;
		logic [PRF_IDX_WIDTH-1:0] rs2_paddr;
		logic rs2_ready;

		// branch specific
		logic [31:0]	predicted_pc;
		logic 			br_en;
		logic 			jal_en;
		logic 			jalr_en;
		branch_f3_t		cmpop;
		logic [31:0]	br_imm;     

        //RVFI data
		rvfi_packet_t 	rvfi_packet;
	} branch_res_station_entry_t;

	typedef struct packed {
        logic               ready; //ready or busy
        logic [PRF_IDX_WIDTH-1:0] rd_paddr;
		logic 				reg_load;
		logic mem_write; // if store

		// branch signals
		logic 			branch_mispredict;	// triggers pipeline flush
		logic 			branch_outcome;		// taken/not-taken (for gshare)
		logic 			is_conditional;		// triggers gshare update
		logic 			is_non_return_jalr;	// triggers btb update
		// order and target pc are in rvfi packet

		// gshare state
		logic [1:0]		rob_old_prediction;
    	logic [$clog2(PHT_SIZE)-1:0] rob_pht_index;

		// RAS
	    logic [RAS_P_WIDTH-1:0] ras_top_ptr;

		rvfi_packet_t rvfi_packet;

    } rob_entry_t;

	typedef struct packed {
		// add
		logic alu_en;
		logic [RISC_ADDR_SIZE_WIDTH-1:0] alu_rd_addr;
		logic [PRF_IDX_WIDTH-1:0] alu_rd_paddr;
		logic [31:0] alu_result;
		logic [ROB_IDX_WIDTH-1:0] alu_rob_idx;
		rvfi_packet_t			alu_rvfi_packet;

		// mul
		logic mul_en;
		logic mul_busy;
		logic [RISC_ADDR_SIZE_WIDTH-1:0] mul_rd_addr;
		logic [PRF_IDX_WIDTH-1:0] mul_rd_paddr;
		logic [31:0] mul_result;
		logic [ROB_IDX_WIDTH-1:0] mul_rob_idx;
		rvfi_packet_t			mul_rvfi_packet;

		// div
		logic div_en;
		logic div_busy;
		logic [RISC_ADDR_SIZE_WIDTH-1:0] div_rd_addr;
		logic [PRF_IDX_WIDTH-1:0] div_rd_paddr;
		logic [31:0] div_result;
		logic [ROB_IDX_WIDTH-1:0] div_rob_idx;
		rvfi_packet_t			div_rvfi_packet;

		// branch
		logic branch_en;
		logic [RISC_ADDR_SIZE_WIDTH-1:0] branch_rd_addr;
		logic [PRF_IDX_WIDTH-1:0] branch_rd_paddr;
		logic [31:0] branch_result;		// pc+4 for jumps
		logic [ROB_IDX_WIDTH-1:0] branch_rob_idx;
		rvfi_packet_t			branch_rvfi_packet;
		logic branch_mispredict;
		logic branch_outcome;

		// mem
		logic mem_en;
		logic mem_busy;
		logic mem_pending;
		logic [RISC_ADDR_SIZE_WIDTH-1:0] mem_rd_addr;
		logic [PRF_IDX_WIDTH-1:0] mem_rd_paddr;
		logic [31:0] mem_result; 
		logic [ROB_IDX_WIDTH-1:0] mem_rob_idx;
		rvfi_packet_t			mem_rvfi_packet;

		logic store_en;
		logic [ROB_IDX_WIDTH-1:0] store_rob_idx;
		rvfi_packet_t			store_rvfi_packet;
	} cdb_packet_t;

	// _________FIFO_QUEUE_ENTRY______//

	typedef struct packed {
		logic   [31:0]      pc;
		logic   [31:0]      inst;
		logic               valid;
		logic 	[23:0]      order;

		// gshare
		logic   [31:0]      predicted_pc;
		logic 	[1:0]                     pred_prediction;
    	logic 	[$clog2(PHT_SIZE)-1:0]    pred_pht_index;

		// RAS
	    logic [RAS_P_WIDTH-1:0] ras_top_ptr;

	} inst_queue_packet_t;

	// _________THE STATES__________ //

	typedef struct packed {

    	logic [31:0]	imm;     
		logic [2:0]  	funct3;
		// logic           mem_read;
		logic           mem_write;

		// alu
		alu_ops         aluop;
		alu_m1_sel_t    alu_m1_sel;
		alu_m2_sel_t    alu_m2_sel;
		branch_f3_t		cmpop;
		logic           ctrl_slt;   // 1 = CMP output, 0 = ALU output 

		// mul
		logic			rs1_is_signed;
		logic			rs2_is_signed;
		logic			mul_high_bits;
		logic			div_get_rem;

		// dispatch
		rs_type_t		rs_target;
		logic			rs1_used;
		logic			rs2_used;
		logic           reg_load;

		// branch
		logic           br_en;
		logic           jal_en;
		logic           jalr_en;
		logic 	[31:0]	predicted_pc;
		logic 	[1:0]                     pred_prediction;
    	logic 	[$clog2(PHT_SIZE)-1:0]    pred_pht_index;

		// RAS
	    logic [RAS_P_WIDTH-1:0] ras_top_ptr;

		// RVFI Data
		rvfi_packet_t rvfi_packet;

	} decode_packet_t;

	typedef struct packed {
		logic alu_add_entry_en;
		logic mul_add_entry_en;
		logic div_add_entry_en;
		logic ld_add_entry_en;
		logic store_add_entry_en;
		logic branch_add_entry_en;

		// ask RAT for phys_rs1_addr and phys_rs2_addr
		logic   [4:0]      rat_rs1_addr;
    	logic   [4:0]      rat_rs2_addr;

		// inserting re-named instruction to ROB tail
		rob_entry_t             rob_packet;

		// giving res_station packet to reservation station
    	alu_res_station_entry_t alu_rs_packet;
		mul_res_station_entry_t mul_rs_packet;
		div_res_station_entry_t div_rs_packet;
		branch_res_station_entry_t branch_rs_packet;
    	ld_res_station_entry_t     		ld_rs_packet;

    	sq_entry_t     		sq_packet;

	} dispatch_packet_t;
    
	typedef struct packed {
		logic alu_issue;
		logic mul_issue;
		logic div_issue;
		logic branch_issue;
		logic mem_issue;
		
        logic [ROB_IDX_WIDTH-1:0]  alu_rob_idx;
        logic [ROB_IDX_WIDTH-1:0]  mul_rob_idx;
        logic [ROB_IDX_WIDTH-1:0]  div_rob_idx;
        logic [ROB_IDX_WIDTH-1:0]  branch_rob_idx;
		logic [ROB_IDX_WIDTH-1:0]  mem_rob_idx;


		logic [PRF_IDX_WIDTH-1:0] alu_rd_paddr;
		logic [PRF_IDX_WIDTH-1:0] mul_rd_paddr;
		logic [PRF_IDX_WIDTH-1:0] div_rd_paddr;
		logic [PRF_IDX_WIDTH-1:0] branch_rd_paddr;
		logic [PRF_IDX_WIDTH-1:0] mem_rd_paddr;
		
		
		rvfi_packet_t			alu_rvfi_packet;
		rvfi_packet_t			mul_rvfi_packet;
		rvfi_packet_t			div_rvfi_packet;
		rvfi_packet_t			branch_rvfi_packet;
		rvfi_packet_t			mem_rvfi_packet;
		

		logic [31:0]	alu_rs1_data;
		logic [31:0] 	alu_rs2_data;
    	logic [31:0]	mul_rs1_data; 
		logic [31:0] 	mul_rs2_data;
    	logic [31:0]	div_rs1_data; 
		logic [31:0]  	div_rs2_data;
		logic [31:0]	branch_rs1_data; 
		logic [31:0]  	branch_rs2_data;
		logic [31:0]	mem_rs1_data; 
		logic [31:0]	mem_rs2_data; 

		// alu
		logic [31:0]	alu_imm;     
		alu_ops         aluop;
		alu_m1_sel_t    alu_m1_sel;
		alu_m2_sel_t    alu_m2_sel;
		branch_f3_t		cmpop;
		logic           ctrl_slt;   // 1 = CMP output, 0 = ALU output 

		// mul
		logic			mul_rs1_is_signed;
		logic			mul_rs2_is_signed;
		logic			div_rs1_is_signed;
		logic			div_rs2_is_signed;
		logic			mul_high_bits;
		logic			div_get_rem;

		// branch
		logic [31:0] branch_predicted_pc;
		logic        branch_br_en;
		logic        branch_jal_en;
		logic        branch_jalr_en;
		branch_f3_t  branch_cmpop;
		logic [31:0] branch_imm;

		// mem
		load_f3_t ld_type;
		store_f3_t st_type;
		logic [31:0] mem_imm;
		logic mem_write;




	} issue_packet_t;


	typedef struct packed {
		logic alu_res_station_clear_en;
    	logic mul_res_station_clear_en;
    	logic div_res_station_clear_en;
		logic branch_res_station_clear_en;
		logic ld_res_station_clear_en;

    	logic [($clog2(ALU_RES_STATION_SIZE)-1):0] alu_res_station_clear_idx;
    	logic [($clog2(MUL_RES_STATION_SIZE)-1):0] mul_res_station_clear_idx;
    	logic [($clog2(DIV_RES_STATION_SIZE)-1):0] div_res_station_clear_idx;
    	logic [($clog2(BR_RES_STATION_SIZE)-1):0] branch_res_station_clear_idx;
    	logic [($clog2(LD_RES_STATION_SIZE)-1):0] ld_res_station_clear_idx;
		
	} rs_clear_t;




endpackage