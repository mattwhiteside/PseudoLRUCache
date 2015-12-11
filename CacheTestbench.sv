//CacheTestbench.v
//Nov 12, 2015

`ifndef CLOCK_PERIOD
`define CLOCK_PERIOD 10
`define DRAM_CLOCK_PERIOD 100
`endif


module CacheTestbench;
  import CacheConfig::*;
  int unsigned coldCycleCount, warmCycleCount;
  integer clk, dram_clk;
  reg reset_L, we_L;
  reg [addressBusWidth-1:0] address,previousAddress;
  reg dataStrobe;//simulate 

  


  reg [pageSize*wordSize - 1:0] mockMainMemory;
  wire [pageSize*wordSize - 1:0] mainMemoryBus;
  wire hit;
  wire [wordSize-1:0] data;
  reg [wordSize-1:0] firstData, secondData,writeData;

  wire DRAMFetchUnderway,DRAMWriteUnderway;
  assign DRAMFetchUnderway = DUT.presentState == FETCHING_FROM_DRAM;
  assign DRAMWriteUnderway = DUT.presentState == WRITING_TO_DRAM;
  assign mainMemoryBus = DUT.presentState == WRITING_TO_DRAM ? 'Z : mockMainMemory;
  assign data = ~we_L ? writeData : 'Z; 

  always #(`CLOCK_PERIOD/2) clk++;
  always #(`DRAM_CLOCK_PERIOD/2) dram_clk++;

  Cache DUT(.*,.clk(clk[0]));

  //this is asserting that if all the sets in a given row 
  // are occupied, then it will have to write one of them
  // out to DRAM. This is scenario 6 described in the docs
  assert property ( @(posedge clk) 
                  $rose(DUT.presentState == FINDING_LRU) && 
                  ( DUT.memArray[3][DUT.rowIndex][75] &
                    DUT.memArray[3][DUT.rowIndex][74] &
                    DUT.memArray[2][DUT.rowIndex][75] &
                    DUT.memArray[2][DUT.rowIndex][74] &
                    DUT.memArray[1][DUT.rowIndex][75] &
                    DUT.memArray[1][DUT.rowIndex][74] &
                    DUT.memArray[0][DUT.rowIndex][75] &
                    DUT.memArray[0][DUT.rowIndex][74])

                    |-> ##[2:5] (DUT.presentState == WRITING_TO_DRAM) );




  always @(posedge DRAMFetchUnderway) begin
    repeat (DRAM_read_latency) begin
      @ (posedge dram_clk); 
    end
    dataStrobe = 1'b1;
    @(negedge dram_clk);
    dataStrobe = 1'b0;
  end

  always @(posedge DRAMWriteUnderway) begin
    repeat (DRAM_write_latency) begin
      @ (posedge dram_clk); 
    end
    dataStrobe = 1'b1;
    @(negedge dram_clk);
    dataStrobe = 1'b0;
  end



  initial begin
    reset_L = 1'b0;
    we_L = 1'b1;
    clk = 1'b0;
    dram_clk = 1'b0;
    
    dataStrobe = 1'b0;
    address = '0;
    previousAddress = '0;
    
    repeat (2) begin 
      @ (negedge clk); 
    end

    reset_L = 1'b1;
    repeat (2) begin
      @ (negedge clk); 
    end

    // test that subsequent requests to the 
    // same address result in a hit the second time
    $display("Scenario 1: read A1, write A2, read A1");
    for (int i = 0; i < 2; i++) begin
      
      coldCycleCount = 0;
      warmCycleCount = 0;
`ifndef XILINX_VIVADO
      assert(std::randomize(address));  
      assert(std::randomize(mockMainMemory));  
`else
      address = $urandom % 1000;
      mockMainMemory = $urandom;      
`endif
     
      previousAddress = address;

      //first fetch; this one will go to main memory and
      // be slow
      @(posedge hit);
      coldCycleCount = clk;
      

      //change the address, and fetch; this fetch is only to 
      // change the state of the cache so we can go back to the previous
      // address and see that it doesn't have to go to main memory
      // the second time around
      
      @(negedge dataStrobe);
      
      @(negedge clk);
      @(negedge clk);

     
`ifndef XILINX_VIVADO
      assert(std::randomize(address));  
      assert(std::randomize(mockMainMemory));  
`else
      address = $urandom % 1000;
      mockMainMemory = $urandom;      
`endif

      we_L = 1'b0;
      writeData = 8'b10010101;

      @(negedge dataStrobe);
      we_L = 1'b1;
      @(negedge clk);

      address = previousAddress;
      
      @(posedge hit);
      warmCycleCount = clk;
      assert(coldCycleCount - warmCycleCount > DRAM_read_latency);
      
    end

    reset_L = 1'b0;
    repeat (3) begin
      @ (negedge clk); 
    end
    reset_L = 1'b1;

    $display("starting scenario 2");
    //test that subsequent requests that map to the same row in the
    // cache go to the least recently used set
    address = 16'b0001_10100_1111_001;
    mockMainMemory = 64'hdead_beef;
    @(posedge hit);    
    @(negedge dataStrobe);    
    @(negedge clk);
    @(negedge clk);

    address = 16'b0010_10100_1111_010;
    mockMainMemory = 64'hcafe_babe;
    @(posedge hit);    
    @(negedge dataStrobe);    
    @(negedge clk);
    @(negedge clk);

    address = 16'b0100_10100_1111_011;
    mockMainMemory = 64'hdecaf_bad;
    @(posedge hit);    
    @(negedge dataStrobe);    
    @(negedge clk);
    @(negedge clk);


    address = 16'b1000_10100_1111_000;
    mockMainMemory = 64'h8badf00d;
    @(posedge hit);    
    @(negedge dataStrobe);    
    @(negedge clk);
    @(negedge clk);


    assert(DUT.memArray[0][15][31:0] == 32'hdead_beef);
    assert(DUT.memArray[1][15][31:0] == 32'hcafe_babe);
    assert(DUT.memArray[2][15][31:0] == 32'hdecaf_bad);
    assert(DUT.memArray[3][15][31:0] == 32'h8badf00d);

    $display("Starting scenario 3");
    //check that a sequential write goes to the same cache line;
    //also repeat this 4 times to set all the dirty bits, which 
    // we want for scenario 4    
    we_L = 1'b0;

    for (int i = 0; i < 4; i++) begin
      
      writeData = 8'h0d;
      @(negedge clk);
      // the shifting is to touch the different sets
      address = 16'b0000_10100_1111_101 + (1 << (12 + i));
      
      @(posedge hit);    
          
      @(negedge clk);
      @(negedge clk);

      writeData = 8'hef;    
      @(negedge clk);
      address = 16'b0000_10100_1111_100  + (1 << (12 + i));
      @(negedge clk);

      @(posedge hit);
      @(negedge clk);
      
      writeData = 8'hac;    
      @(negedge clk);
      address = 16'b0000_10100_1111_011 + (1 << (12 + i));
      @(posedge hit);
      @(negedge clk);
      
      writeData = 8'hed;    
      @(negedge clk);
      address = 16'b0000_10100_1111_010 + (1 << (12 + i));
      @(posedge hit);
      @(negedge clk);
      @(negedge clk);//one extra cycle needed, since
                     //the machine is in the WRITING_TO_CACHE state
                     //at this point
      

      assert(DUT.memArray[i][15 ][47:16] == 32'h0DEFACED);
    end


    //check that a read to that maps to the previous (full) row, but with 
    // a different tag, results in an eviction 
    $display("Starting scenario 4");

    mockMainMemory = 64'hAAAA_AAAA_AAAA_AAAA;  
    we_L = 1'b1;
    address = 16'b1101_10111_1111_010;
    @(posedge hit);
    @(negedge clk);
    @(negedge clk);
    assert(DUT.memArray[3][15][63:0] == 64'hAAAA_AAAA_AAAA_AAAA);

    address = 16'b1011_10111_1111_010;
    mockMainMemory = 64'hBBBB_BBBB_BBBB_BBBB;
    @(posedge hit);
    @(negedge clk);
    @(negedge clk);
    assert(DUT.memArray[0][15][63:0] == 64'hBBBB_BBBB_BBBB_BBBB);

    address = 16'b1001_10111_1111_010;
    mockMainMemory = 64'hCCCC_CCCC_CCCC_CCCC;
    @(posedge hit);
    @(negedge clk);
    @(negedge clk);
    assert(DUT.memArray[1][15][63:0] == 64'hCCCC_CCCC_CCCC_CCCC);

    address = 16'b1000_10101_1111_010;
    mockMainMemory = 64'hDDDD_DDDD_DDDD_DDDD;
    @(posedge hit);
    @(negedge clk);
    @(negedge clk);
    assert(DUT.memArray[2][15][63:0] == 64'hDDDD_DDDD_DDDD_DDDD );
    @(negedge clk);
    $display("scenario 5");
    assert(DUT.data == 8'hdd);
    while (1) begin
      @(negedge clk);
    end

    
    $finish;
  end
endmodule
