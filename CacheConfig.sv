//CacheConfig.sv
//Nov 12, 2015
//This package is just so the module and the testbench
// can share the same configuration parameters
package CacheConfig;

  typedef enum logic [2:0] {IDLE,
                            NEW_INPUTS_LATCHED,
                            CHECKING_FOR_HIT,
                            FINDING_LRU,//LRU = least recently used                            
                            WRITING_TO_DRAM,
                            WRITE_RECOVERY,
                            FETCHING_FROM_DRAM,
                            WRITING_TO_CACHE} CacheState;

  parameter int unsigned wordSize = 8,//bits, aka 1 byte dataBus, per assignment spec
                         pageSize = 8,//aka, words per row
                         DRAM_read_latency = 8,//cycles
                         DRAM_write_latency = 9,//cycles
                         addressBusWidth = 16,
                         numSets = 4,//aka, associativity
                         numRows = 16;


endpackage : CacheConfig
