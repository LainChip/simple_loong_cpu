`ifndef _FORWARDING_TYPE_HEADER
`define _FORWARDING_TYPE_HEADER

typedef struct packed {
    logic [31:0] data;  // reg data
    logic [4 :0] addr;  // reg addr
    logic valid;        // whether data is valid
} forwarding_data_t;

`define FWD_DATA_SIZE ($bits(forwarding_data_t))

`endif
