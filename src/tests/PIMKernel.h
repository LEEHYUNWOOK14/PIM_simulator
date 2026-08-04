/***************************************************************************************************
 * Copyright (C) 2021 Samsung Electronics Co. LTD
 *
 * This software is a property of Samsung Electronics.
 * No part of this software, either material or conceptual may be copied or distributed,
 * transmitted, transcribed, stored in a retrieval system, or translated into any human
 * or computer language in any form by any means,electronic, mechanical, manual or otherwise,
 * or disclosed to third parties without the express written permission of Samsung Electronics.
 * (Use of the Software is restricted to non-commercial, personal or academic, research purpose
 * only)
 **************************************************************************************************/

#ifndef __PIM_KERNEL_HPP__
#define __PIM_KERNEL_HPP__

#include <memory>
#include <sstream>
#include <string>
#include <vector>

#include "MultiChannelMemorySystem.h"
#include "PIMCmd.h"
#include "SystemConfiguration.h"
#include "tests/KernelAddrGen.h"

using namespace std;
using namespace DRAMSim;

class PIMKernel
{
  public:
    PIMKernel(shared_ptr<MultiChannelMemorySystem> mem, int num_pim_chan, int num_pim_rank)
        : mem_(mem),
          num_pim_chans_(num_pim_chan),
          num_pim_ranks_(num_pim_rank),
          mode_(PIMConfiguration::getPIMMode()),
          target_(PIMConfiguration::getPIMTarget()),
          num_banks_(getConfigParam(UINT, "NUM_BANKS")),
          num_pim_blocks_(getConfigParam(UINT, "NUM_PIM_BLOCKS")),
          num_bank_groups_(getConfigParam(UINT, "NUM_BANK_GROUPS")),
          srf_bst_(NULL),
          cycle_(0),
          hierarchyTransferCount_(0),
          hierarchyTransferBytes_(0),
          hierarchyTransferCycles_(0),
          lastPointwiseActiveChannels_(num_pim_chan),
          lastPointwisePhysicalOutputDim_(0),
          lastPointwiseSpatialGroups_(1),
          lastPointwiseBatchWaves_(0),
          baselineLogicWeightBytes_(0),
          physicalLogicWeightBytes_(0),
          modeledLogicWeightBytes_(0),
          savedLogicWeightBytes_(0),
          logicWeightFillBarrierCycles_(0),
          logicWeightBufferPortWaitCycles_(0),
          logicPostFillGuardCycles_(0)
    {
        transaction_size_ = getConfigParam(UINT, "BL") *
                            (getConfigParam(UINT, "JEDEC_DATA_BUS_BITS") / 8);  // in byte

        // FIXME: HARDCODED
        num_grf_ = num_grfA_ = num_grfB_ = 8;
        num_total_pim_blocks_ = num_pim_blocks_ * num_pim_chans_ * num_pim_ranks_;

        pim_chans_.clear();
        for (int i = 0; i < num_pim_chans_; i++) pim_chans_.push_back(i);

        pim_ranks_.clear();
        for (int i = 0; i < num_pim_ranks_; i++) pim_ranks_.push_back(i);

        pim_addr_mgr_ = make_shared<PIMAddrManager>(num_pim_chan, num_pim_rank);
    }

    int transaction_size_;
    int num_pim_chans_, num_pim_ranks_;
    int num_grfA_, num_grfB_, num_grf_;
    PIMTarget target_;
    shared_ptr<PIMAddrManager> pim_addr_mgr_;

    void addBarrier();
    void runPIM();
    uint64_t getCycle();
    uint64_t accountHierarchyTransfer(uint64_t bytes, uint64_t bytes_per_cycle);
    uint64_t getHierarchyTransferCount() const;
    uint64_t getHierarchyTransferBytes() const;
    uint64_t getHierarchyTransferCycles() const;
    unsigned getLastPointwiseActiveChannels() const;
    unsigned getLastPointwisePhysicalOutputDim() const;
    unsigned getLastPointwiseSpatialGroups() const;
    unsigned getLastPointwiseBatchWaves() const;
    uint64_t getTotalReads() const;
    uint64_t getTotalWrites() const;
    uint64_t getGlobalLogicCommandCount() const;
    uint64_t getGlobalLogicQueueCycles() const;
    uint64_t getGlobalLogicServiceCycles() const;
    uint64_t getGlobalLogicBusyUntil() const;
    uint64_t getGlobalLogicDispatchCount() const;
    uint64_t getGlobalLogicCoalescedCommandCount() const;
    uint64_t getGlobalLogicDispatchOverheadCycles() const;
    uint64_t getBaselineLogicWeightBytes() const;
    uint64_t getPhysicalLogicWeightBytes() const;
    uint64_t getModeledLogicWeightBytes() const;
    uint64_t getSavedLogicWeightBytes() const;
    uint64_t getModeledTotalWrites() const;
    uint64_t getLogicWeightBufferFillBursts() const;
    uint64_t getLogicWeightBufferReadHits() const;
    uint64_t getLogicWeightBufferReadMisses() const;
    uint64_t getLogicWeightFillActiveChannels() const;
    uint64_t getLogicWeightFillCompletedWrites() const;
    uint64_t getLogicWeightFillMinWritesPerChannel() const;
    uint64_t getLogicWeightFillMaxWritesPerChannel() const;
    uint64_t getLogicWeightFillMinCompletionCycle() const;
    uint64_t getLogicWeightFillMaxCompletionCycle() const;
    uint64_t getLogicWeightFillActivates() const;
    uint64_t getLogicWeightFillPrecharges() const;
    uint64_t getLogicWeightFillBarrierCycles() const;
    uint64_t getLogicWeightBufferPortWaitCycles() const;
    uint64_t getLogicPostFillGuardCycles() const;
    uint64_t getLogicWeightBufferWriteQueueCycles() const;
    uint64_t getTotalRefreshes() const;
    void parkIn();
    void parkOut();
    void changePIMMode(dramMode mode1, dramMode mode2);
    void addTransactionAll(bool isWrite, int bg, int bank, int row, int col, const std::string tag,
                           BurstType* bst, bool use_barrier = false, int num_loop = 1);
    void addTransactionAll(bool isWrite, int bg, int bank, int row, int col, BurstType* bst,
                           bool use_barrier = false, int num_loop = 1);
    /*
    void preprocessBn(NumpyBurstType* mean_npbst, NumpyBurstType* var_npbst,
                      NumpyBurstType* gamma_npbst, NumpyBurstType* beta_npbst,
                      NumpyBurstType* input_npbst, fp16** params, float eps);
    void preprocessSrf(NumpyBurstType* input_npbst, fp16** params, int burst_offset,
                       int num_srf_usage);
    */
    /*
    void programSrf();
    */
    void programCrf(vector<PIMCmd>& cmds);
    void setControl(BurstType* bst, bool op, int crf_toggle_cond, bool grfA_zero, bool grfB_zero);
    unsigned getResultColGemv(int input_dim, int output_dim);
    void changeBank(pimBankType bank_types, int& cidx, int& rank, int& bg, int& bank,
                    unsigned& startingRow, unsigned& startingCol, unsigned& row, unsigned& col);
    void preloadGemv(NumpyBurstType* operand, unsigned starting_row = 0,
                     unsigned starting_col = 0, bool fill_shared_weight_buffer = false);
    void preloadNoReplacement(NumpyBurstType* operand, unsigned startingRow, unsigned startingCol);
    /*
    void preloadEltwise(NumpyBurstType* operand, pimBankType bank_types, unsigned startingRow,
                        unsigned startingCol);
    */
    void executeGemv(NumpyBurstType* w_data, NumpyBurstType* i_data, bool is_tree);
    std::vector<fp16> executePointwiseAndRead(NumpyBurstType* weights, NumpyBurstType* input,
                                              unsigned logical_output_dim);
    std::vector<fp16> executePointwiseBatchAndRead(NumpyBurstType* weights,
                                                   NumpyBurstType* input,
                                                   unsigned logical_output_dim,
                                                   unsigned channel_start = 0);
    std::vector<fp16> executePointwiseSpatialGroupsAndRead(NumpyBurstType* weights,
                                                           NumpyBurstType* input,
                                                           unsigned logical_output_dim);
    void executeEltwise(int dim, pimBankType bank_types, KernelType ktype, int input0_row,
                        int result_row, int input1_row = 0);
    void executeDepthwiseLowered(int dim, unsigned kernel_size, int input_base_row,
                                 int weight_base_row, int product_row, int accumulator_row,
                                 int result_row,
                                 int tap_row_stride = 128);
    void executeLogicDieStub(const std::string& op_name);
    void computeGemv(NumpyBurstType* data, int num_input_tiles, int num_output_tile, int input_tile,
                     int output_tile, int batch_idx, pimBankType bank_types);
    void computeAddOrMul(int numTile, int input0Row, int resultRow, int input1Row);
    void computeRelu(int numTile, int input0Row, int resultRow);
    // void computeBn(int numTile, int input0Row, int resultRow);
    bool usesBankSidePIM() const;
    bool usesLogicDiePIM() const;

    void readResult(BurstType* resultBst, pimBankType bank_types, int output_dim,
                    uint64_t baseAddr = 0, unsigned startingRow = 0, unsigned startingCol = 0);
    void readData(BurstType* bst_data, size_t bst_cnt, unsigned s_row = 0, unsigned s_col = 0);
    void adderTree(BurstType* result, int output_dim, int numTile, int step, fp16* temp);

  private:
    unsigned cycle_;
    uint64_t hierarchyTransferCount_;
    uint64_t hierarchyTransferBytes_;
    uint64_t hierarchyTransferCycles_;
    unsigned lastPointwiseActiveChannels_;
    unsigned lastPointwisePhysicalOutputDim_;
    unsigned lastPointwiseSpatialGroups_;
    unsigned lastPointwiseBatchWaves_;
    uint64_t baselineLogicWeightBytes_;
    uint64_t physicalLogicWeightBytes_;
    uint64_t modeledLogicWeightBytes_;
    uint64_t savedLogicWeightBytes_;
    uint64_t logicWeightFillBarrierCycles_;
    uint64_t logicWeightBufferPortWaitCycles_;
    uint64_t logicPostFillGuardCycles_;
    unsigned num_banks_, num_pim_blocks_, num_bank_groups_, num_total_pim_blocks_;
    BurstType null_bst_, bst_hab_pim_, bst_hab_;
    BurstType crf_bst_[4];
    BurstType* srf_bst_;
    vector<int> pim_chans_;
    vector<int> pim_ranks_;
    PIMMode mode_;
    shared_ptr<MultiChannelMemorySystem> mem_;
    const uint32_t pim_reg_ra_ = 0x3fff;
    const uint32_t pim_abmr_ra_ = 0x27ff;
    const uint32_t pim_sbmr_ra_ = 0x2fff;

    void setActivePimChannels(unsigned channels, unsigned channel_start = 0);
    void setActivePimChannelList(const vector<int>& channels);

    int inline getToggleCond(pimBankType pb_type = pimBankType::ALL_BANK)
    {
        // set Toggle Condition
        switch (pb_type)
        {
            case pimBankType::EVEN_BANK:
                return 2;
            case pimBankType::ODD_BANK:
                return 1;
            case pimBankType::ALL_BANK:
                return 0;
            default:
                return -1;
        }
    }
};

#endif
