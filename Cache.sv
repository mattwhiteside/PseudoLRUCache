//Cache.sv

//Nov 12, 2015

//This is the main module


import CacheConfig::*;

module Cache (
    input wire [addressBusWidth-1:0] address,
    
    input wire clk,
               reset_L,
               dataStrobe, 
               we_L,    

    inout wire [pageSize * wordSize - 1:0] mainMemoryBus,
    inout reg [wordSize - 1:0] data,
    output reg hit

);

localparam numTagBits = addressBusWidth - $clog2(numRows) - $clog2(pageSize);
localparam actualRowWidth = pageSize * wordSize + 
                            numTagBits + 3;//+3 is for valid bit, used bit, & dirty bit
localparam validBit = actualRowWidth - 1;
localparam usedBit = actualRowWidth - 2;
localparam dirtyBit = actualRowWidth - 3;
localparam tagMSB = actualRowWidth - 4;
localparam tagLSB = tagMSB - numTagBits + 1;

reg [numSets - 1:0][numRows-1:0][actualRowWidth - 1:0] memArray;
reg [addressBusWidth-1:0] latchedAddress;
reg [wordSize-1:0] latchedDataOut,latchedDataIn;
reg [$clog2(numSets)-1:0] LRU_set_ptr;//points to the least recently used set
reg presentOperation;

wire [numSets - 1:0] muxSelect, preliminaryHitWires;
wire [$clog2(numRows) - 1:0] rowIndex;
wire [wordSize-1:0] outputBus;
wire _hit, LRU_found;
wire [wordSize-1:0] internalDatabus[numSets-1:0];
wire [$clog2(pageSize)-1:0] wordSelect;
wire [numTagBits-1:0] requestedTag;
wire evictionNecessary;
wire [$clog2(numSets)-1:0] hitPtr;

CacheState presentState, nextState;

assign wordSelect = latchedAddress[$clog2(pageSize)-1:0];//selects the which within the page
assign LRU_found = ~memArray[LRU_set_ptr][rowIndex][usedBit];
assign rowIndex = address[$clog2(numRows) + $clog2(pageSize) - 1 : $clog2(pageSize)];
assign requestedTag = latchedAddress[addressBusWidth - 1:addressBusWidth - numTagBits];
assign _hit = (| preliminaryHitWires);
assign data = ~we_L ? 'Z : latchedDataOut;
assign mainMemoryBus = presentState == WRITING_TO_DRAM ? 
                       memArray[LRU_set_ptr][rowIndex][tagLSB-1:0] : 'Z;

assign evictionNecessary = memArray[LRU_set_ptr][rowIndex][validBit] & 
                           memArray[LRU_set_ptr][rowIndex][dirtyBit] & 
                           (memArray[LRU_set_ptr][rowIndex][tagMSB:tagLSB] != requestedTag);
//assign hitPtr = $clog2(preliminaryHitWires);

OneHotMux #( .databusWidth(wordSize), .numInputs(numSets)) 
          mux(.in(internalDatabus),.out(outputBus),.sel(muxSelect)); 

BinaryEncoder #(.n($clog2(numSets)))
          hitDecoder(.in(preliminaryHitWires),.out(hitPtr));

genvar i;

generate
  for (i = 0; i < numSets; i++) begin: mems
    assign internalDatabus[i] = memArray[i][rowIndex][((wordSelect+1)*wordSize - 1) -: wordSize];
    assign preliminaryHitWires[i] = memArray[i][rowIndex][validBit] & 
           (memArray[i][rowIndex][tagMSB:tagLSB] == requestedTag);
    assign muxSelect[i] = preliminaryHitWires[i];
  end
endgenerate


always_comb begin: compute_next_state
  if (reset_L) begin
  
    unique case (presentState) 
      IDLE : 
        if ((address !== latchedAddress) || ((latchedDataIn !== data) & ~we_L)) begin
          nextState = NEW_INPUTS_LATCHED;
        end else begin
          nextState = IDLE;
        end
              
      //need this extra state to provide one extra cycle for
      // the tag comparisons, which lag behind address change by one cycle
      NEW_INPUTS_LATCHED: nextState = CHECKING_FOR_HIT;
      CHECKING_FOR_HIT: 
        if (_hit) begin
          nextState = ~we_L ? WRITING_TO_CACHE : IDLE;
        end else begin
          nextState = FINDING_LRU;
        end
      FINDING_LRU: 
        if (LRU_found) begin
          nextState = evictionNecessary ? WRITING_TO_DRAM : FETCHING_FROM_DRAM;
        end else begin
          nextState = FINDING_LRU;      
        end
      WRITING_TO_DRAM: nextState = dataStrobe ? WRITE_RECOVERY : WRITING_TO_DRAM;
      //wait until dataStrobe falls
      WRITE_RECOVERY: nextState = dataStrobe ? WRITE_RECOVERY : FETCHING_FROM_DRAM;
      FETCHING_FROM_DRAM: 
        if (dataStrobe) begin
          nextState = ~we_L ? WRITING_TO_CACHE : IDLE;
        end else begin
          nextState = FETCHING_FROM_DRAM;
        end          
      WRITING_TO_CACHE: nextState = IDLE;
    endcase 
  end
end 



always_ff @(posedge clk iff reset_L == 1 or negedge reset_L) begin : proc_
  presentOperation <= we_L;
  if(~reset_L) begin
    presentState <= IDLE;
    memArray <= '0; 
    latchedDataOut <= '0;    
    hit <= 1'b0;   
    LRU_set_ptr <= '0; 
    latchedAddress <= '0;    
  end else begin
    presentState <= nextState;
    latchedDataOut <= outputBus;  
    latchedAddress <= address; 
    latchedDataIn <= data;

    //this allows the hit signal the chance to fall, for
    // at least one cycle after a new address is applied.  When the hit
    // output comes back up to high, this indicates to clients of the cache
    // that inputs are allowed to change
    hit <= (presentState == NEW_INPUTS_LATCHED) ? 1'b0 : _hit;

    if (presentState == FINDING_LRU & ~LRU_found & ~_hit) begin
      LRU_set_ptr <= LRU_set_ptr + 1;
      memArray[LRU_set_ptr][rowIndex][usedBit] <= 1'b0;
    end else if ((presentState == FETCHING_FROM_DRAM) & dataStrobe) begin      
      memArray[LRU_set_ptr][rowIndex][validBit] <= 1'b1;
      memArray[LRU_set_ptr][rowIndex][usedBit] <= 1'b1;
      memArray[LRU_set_ptr][rowIndex][tagMSB:tagLSB] <= requestedTag;
      memArray[LRU_set_ptr][rowIndex][dirtyBit] <= 1'b0;      
      memArray[LRU_set_ptr][rowIndex][tagLSB-1:0] <= mainMemoryBus; 
    end else if (presentState == WRITING_TO_CACHE) begin
      memArray[hitPtr][rowIndex][(wordSelect+1)*wordSize - 1 -: wordSize] <= latchedDataIn; 
      memArray[hitPtr][rowIndex][dirtyBit] <= 1'b1;
      memArray[hitPtr][rowIndex][usedBit] <= 1'b1;
    end    

  end
end

endmodule