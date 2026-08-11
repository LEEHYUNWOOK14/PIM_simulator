module logic_result_router_formal(output logic ok);
  (* anyconst *) logic valid,dest,bank_ready,host_ready;
  (* anyconst *) logic [31:0] key,data;
  logic ready,bank_valid,host_valid;logic [31:0] bank_key,host_key,bank_data,host_data;
  logic_result_router #(.KEY_WIDTH(32),.DATA_WIDTH(32)) dut(
    .result_valid_i(valid),.result_ready_o(ready),.destination_bank_i(dest),
    .result_key_i(key),.result_data_i(data),.bank_valid_o(bank_valid),
    .bank_ready_i(bank_ready),.bank_key_o(bank_key),.bank_data_o(bank_data),
    .host_valid_o(host_valid),.host_ready_i(host_ready),.host_key_o(host_key),
    .host_data_o(host_data));
  always @* ok = bank_valid == (valid && dest) &&
                 host_valid == (valid && !dest) &&
                 !(bank_valid && host_valid) &&
                 ready == (dest ? bank_ready : host_ready) &&
                 bank_key==key && host_key==key && bank_data==data && host_data==data;
endmodule
