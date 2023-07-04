`ifndef _FORWARDING_TYPE_HEADER
`define _FORWARDING_TYPE_HEADER

typedef struct packed {
    logic valid;        // whether data is valid
    logic [4 :0] addr;  // reg addr
    logic [31:0] data;  // reg data
} forwarding_data_t;


`endif
