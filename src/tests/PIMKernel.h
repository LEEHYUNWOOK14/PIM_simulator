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

#include <deque>
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

struct PointwiseSpatialHandle
{
    NumpyBurstType compactWeights;
    vector<NumpyBurstType> positionInputs;
    vector<vector<BurstType>> physicalOutput;
    unsigned logicalOutputDim = 0;
    unsigned batchSize = 0;
    uint64_t outputLayer = 0;
    bool waited = false;
    bool consumed = false;
};

struct PointwiseSpatialSession
{
    NumpyBurstType weights;
    NumpyBurstType input;
    unsigned height = 0;
    unsigned width = 0;
    unsigned logicalOutputDim = 0;
    unsigned nextRow = 0;
    unsigned activeRowStart = 0;
    unsigned activeRowCount = 0;
    uint64_t weightLayerGeneration = 0;
    uint64_t weightFillBursts = 0;
    uint64_t reusedWeightFillBursts = 0;
    uint64_t crfProgramCalls = 0;
    uint64_t reusedCrfProgramCalls = 0;
    unsigned reusedRowRanges = 0;
    bool weightResident = false;
    vector<bool> logicCrfResidentGroups;
    shared_ptr<PointwiseSpatialHandle> activeHandle;
    vector<fp16> output;
};

struct DepthwiseLoweredHandle
{
    int dim = 0;
    unsigned kernelSize = 0;
    int inputBaseRow = 0;
    int weightBaseRow = 0;
    int productRow = 0;
    int accumulatorRow = 0;
    int resultRow = 0;
    int tapRowStride = 0;
    unsigned nextStage = 0;
    unsigned totalStages = 0;
    bool stagePending = false;
    bool complete = false;
};

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
          depthwiseAccumulatorTransferBytes_(0),
          depthwiseAccumulatorTransferCycles_(0),
          depthwiseAccumulatorOverlapCycles_(0),
          depthwiseAccumulatorWaitCycles_(0),
          lastPointwiseActiveChannels_(num_pim_chan),
          lastPointwisePhysicalOutputDim_(0),
          lastPointwiseSpatialGroups_(1),
          lastPointwiseBatchWaves_(0),
          logicHabEntries_(0),
          logicHabExits_(0),
          baselineLogicWeightBytes_(0),
          physicalLogicWeightBytes_(0),
          modeledLogicWeightBytes_(0),
          savedLogicWeightBytes_(0),
          logicWeightFillBarrierCycles_(0),
          logicWeightBufferPortWaitCycles_(0),
          logicPostFillGuardCycles_(0),
          logicBroadcastQueueAppliedCycles_(0),
          logicBroadcastQueueLastPreStallCycle_(0),
          pointwiseSpatialOutstanding_(false)
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
    uint64_t getDepthwiseAccumulatorTransferBytes() const;
    uint64_t getDepthwiseAccumulatorTransferCycles() const;
    uint64_t getDepthwiseAccumulatorOverlapCycles() const;
    uint64_t getDepthwiseAccumulatorWaitCycles() const;
    uint64_t getDepthwiseAccumulatorPartialBursts() const;
    uint64_t getDepthwiseAccumulatorFinalBursts() const;
    uint64_t getDepthwiseAccumulatorPeakEntries() const;
    uint64_t getBankLocalAccumulatorStalls() const;
    uint64_t getBankLocalAccumulatorPeakEntries() const;
    uint64_t getBankLocalAccumulatorPeakEntriesPerBank() const;
    DRAMSim::LogicDieAccumulator::LinkReplayStats getDepthwiseLinkReplayStats() const;
    void writeDepthwiseAccumulatorTrace(const std::string& path) const;
    unsigned getLastPointwiseActiveChannels() const;
    unsigned getLastPointwisePhysicalOutputDim() const;
    unsigned getLastPointwiseSpatialGroups() const;
    unsigned getLastPointwiseBatchWaves() const;
    uint64_t getLogicHabEntries() const;
    uint64_t getLogicHabExits() const;
    uint64_t getTotalReads() const;
    uint64_t getTotalWrites() const;
    uint64_t getGlobalLogicCommandCount() const;
    uint64_t getGlobalLogicQueueCycles() const;
    uint64_t getGlobalLogicServiceCycles() const;
    uint64_t getGlobalLogicBusyUntil() const;
    uint64_t getGlobalLogicDispatchCount() const;
    uint64_t getGlobalLogicCoalescedCommandCount() const;
    uint64_t getGlobalLogicDispatchOverheadCycles() const;
    void resetHierarchyActivity();
    HierarchyActivityStats getHierarchyActivityStats() const;
    uint64_t getLogicReleaseEpochCount() const;
    uint64_t getLogicReleaseMaxStreams() const;
    uint64_t getLogicReleaseCompleteMasks() const;
    uint64_t getLogicReleaseIncompleteMasks() const;
    uint64_t getLogicBroadcastMaskCount() const;
    uint64_t getLogicBroadcastFanout() const;
    uint64_t getLogicBroadcastMinFanout() const;
    uint64_t getLogicBroadcastMaxFanout() const;
    LogicEpochStats getLogicEpochStats(uint64_t epochId) const;
    uint64_t getLogicBroadcastQueueStallCycles() const;
    uint64_t getLogicBroadcastQueueFullEvents() const;
    uint64_t getLogicBroadcastQueueAppliedCycles() const;
    uint64_t getLogicBroadcastQueueLastPreStallCycle() const;
    uint64_t getLogicOnlineIssueStallCycles() const;
    uint64_t getLogicOnlineIssueBusyOverlapCycles() const;
    uint64_t getLogicBlockedWallCycles() const;
    uint64_t getLogicBlockedStreamCount() const;
    uint64_t getLogicMinBlockedCyclesPerStream() const;
    uint64_t getLogicMaxBlockedCyclesPerStream() const;
    uint64_t getLogicMinIssuedCommandsPerStream() const;
    uint64_t getLogicMaxIssuedCommandsPerStream() const;
    uint64_t getLogicBlockedStreamMaskLow() const;
    uint64_t getLogicBlockedStreamMaskHigh() const;
    uint64_t getCommandPredicateRejectCycles() const;
    uint64_t getCommandPredicateHolCycles() const;
    uint64_t getCommandPredicateHolCandidates() const;
    uint64_t getCommandPredicateHolMaxCandidates() const;
    uint64_t getCommandPredicateBypassIssues() const;
    uint64_t getIssuabilityRejectAttempts(CommandIssuabilityRejectReason reason) const;
    uint64_t getIssuabilityRejectWallCycles(CommandIssuabilityRejectReason reason) const;
    uint64_t getIssuabilityBlockedControllerCycles(
        CommandIssuabilityRejectReason reason) const;
    uint64_t getGlobalAnyBlockedCycles(CommandIssuabilityRejectReason reason) const;
    uint64_t getGlobalAllActiveBlockedCycles(CommandIssuabilityRejectReason reason) const;
    uint64_t getGlobalPeakBlockedChannels(CommandIssuabilityRejectReason reason) const;
    uint64_t getGlobalRankModeAnyBlockedCycles() const;
    uint64_t getGlobalRankModeAllActiveBlockedCycles() const;
    uint64_t getGlobalRankModePeakBlockedChannels() const;
    uint64_t getGlobalPredicateAnyBlockedCycles(HierarchyPredicateBlockReason reason) const;
    uint64_t getGlobalPredicateAllActiveBlockedCycles(
        HierarchyPredicateBlockReason reason) const;
    uint64_t getGlobalPredicatePeakBlockedChannels(
        HierarchyPredicateBlockReason reason) const;
    uint64_t getGlobalHierarchyUnionAnyBlockedCycles() const;
    uint64_t getGlobalHierarchyUnionAllActiveBlockedCycles() const;
    uint64_t getGlobalHierarchyUnionPeakBlockedChannels() const;
    uint64_t getGlobalBankStateAllNoHierarchyCycles() const;
    uint64_t getGlobalBankStateAllWithHierarchyCycles() const;
    uint64_t getGlobalBankStateOnlyCycles() const;
    uint64_t getGlobalHierarchyAllNoIssuabilityCycles() const;
    uint64_t getGlobalBankHierarchyAllIntersectionCycles() const;
    uint64_t getGlobalBankTagAnyBlockedCycles(CommandTagClass tagClass) const;
    uint64_t getGlobalBankTagAllActiveBlockedCycles(CommandTagClass tagClass) const;
    uint64_t getGlobalBankTagPeakBlockedChannels(CommandTagClass tagClass) const;
    map<string, uint64_t> getBankStateBlockedCyclesByRawTag() const;
    uint64_t getEpochMismatchRejects() const;
    uint64_t getBarrierOutstandingRejects() const;
    uint64_t getWriteBusBusyRejects() const;
    uint64_t getRankCommandRejects() const;
    uint64_t getRankModeTransitionRejects() const;
    uint64_t getRankLogicQueueRejects() const;
    uint64_t getRankBankDomainRejects() const;
    uint64_t getRankLogicDomainRejects() const;
    uint64_t getRankModeBlockedControllerCycles() const;
    uint64_t getRankLogicQueueBlockedControllerCycles() const;
    uint64_t getWriteDataCompletions(WriteCompletionClass completionClass) const;
    uint64_t getWriteBarrierCompletions(WriteCompletionClass completionClass) const;
    uint64_t getBarrierOutstandingRejects(WriteCompletionClass completionClass) const;
    uint64_t getEpochMismatchRejects(WriteCompletionClass completionClass) const;
    uint64_t getBarrierOutstandingRejects(BarrierTagClass tagClass) const;
    uint64_t getEpochMismatchRejects(BarrierTagClass tagClass) const;
    map<string, uint64_t> getBarrierOutstandingRejectsByRawTag() const;
    map<string, uint64_t> getEpochMismatchRejectsByRawTag() const;
    uint64_t getLogicOutputBufferReservations() const;
    uint64_t getLogicOutputBufferRetirements() const;
    uint64_t getLogicOutputBufferFullStalls() const;
    uint64_t getLogicOutputBufferPeakEntries() const;
    uint64_t getLogicOutputBufferDrainBusyCycles() const;
    uint64_t getLogicOutputBufferFullWallCycles() const;
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
                           BurstType* bst, bool use_barrier = false, int num_loop = 1,
                           WriteCompletionClass completionClass =
                               WriteCompletionClass::ORDERED);
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
    void programCrf(vector<PIMCmd>& cmds, bool logic_die = false);
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
    void executeGemv(NumpyBurstType* w_data, NumpyBurstType* i_data, bool is_tree,
                     bool program_crf = true, bool enter_hab = true, bool exit_hab = true);
    std::vector<fp16> executePointwiseAndRead(NumpyBurstType* weights, NumpyBurstType* input,
                                              unsigned logical_output_dim);
    std::vector<fp16> executePointwiseBatchAndRead(NumpyBurstType* weights,
                                                   NumpyBurstType* input,
                                                   unsigned logical_output_dim,
                                                   unsigned channel_start = 0);
    std::vector<fp16> executePointwiseSpatialGroupsAndRead(NumpyBurstType* weights,
                                                           NumpyBurstType* input,
                                                           unsigned logical_output_dim);
    shared_ptr<PointwiseSpatialHandle> enqueuePointwiseSpatialGroups(
        NumpyBurstType* weights, NumpyBurstType* input, unsigned logical_output_dim);
    void waitPointwiseSpatial(const shared_ptr<PointwiseSpatialHandle>& handle);
    vector<fp16> readPointwiseSpatial(const shared_ptr<PointwiseSpatialHandle>& handle);
    shared_ptr<PointwiseSpatialSession> beginPointwiseSpatialSession(
        NumpyBurstType* weights, NumpyBurstType* input, unsigned height, unsigned width,
        unsigned logical_output_dim);
    void enqueuePointwiseRows(const shared_ptr<PointwiseSpatialSession>& session,
                              unsigned row_start, unsigned row_count);
    void waitPointwiseRows(const shared_ptr<PointwiseSpatialSession>& session);
    vector<fp16> readPointwiseRows(const shared_ptr<PointwiseSpatialSession>& session);
    void executeEltwise(int dim, pimBankType bank_types, KernelType ktype, int input0_row,
                        int result_row, int input1_row = 0);
    void executeDepthwiseLowered(int dim, unsigned kernel_size, int input_base_row,
                                 int weight_base_row, int product_row, int accumulator_row,
                                 int result_row,
                                 int tap_row_stride = 128);
    void executeDepthwiseHierarchical(int dim, unsigned kernel_size, int input_base_row,
                                      int weight_base_row, int result_row,
                                      int tap_row_stride = 128);
    shared_ptr<DepthwiseLoweredHandle> beginDepthwiseLowered(
        int dim, unsigned kernel_size, int input_base_row, int weight_base_row,
        int product_row, int accumulator_row, int result_row, int tap_row_stride = 128);
    void enqueueDepthwiseStage(const shared_ptr<DepthwiseLoweredHandle>& handle);
    void waitDepthwiseStage(const shared_ptr<DepthwiseLoweredHandle>& handle);
    void executeLogicDieStub(const std::string& op_name);
    void computeGemv(NumpyBurstType* data, int num_input_tiles, int num_output_tile, int input_tile,
                     int output_tile, int batch_idx, pimBankType bank_types);
    void computeAddOrMul(int numTile, int input0Row, int resultRow, int input1Row);
    void computeRelu(int numTile, int input0Row, int resultRow);
    // void computeBn(int numTile, int input0Row, int resultRow);
    bool usesBankSidePIM() const;
    bool usesLogicDiePIM() const;

    void readResult(BurstType* resultBst, pimBankType bank_types, int output_dim,
                    uint64_t baseAddr = 0, unsigned startingRow = 0, unsigned startingCol = 0,
                    uint64_t outputLayer = 0, uint64_t outputPosition = 0);
    void readData(BurstType* bst_data, size_t bst_cnt, unsigned s_row = 0, unsigned s_col = 0);
    void adderTree(BurstType* result, int output_dim, int numTile, int step, fp16* temp);

  private:
    shared_ptr<PointwiseSpatialHandle> enqueuePointwiseSpatialGroupsInternal(
        NumpyBurstType* weights, NumpyBurstType* input, unsigned logical_output_dim,
        bool reuse_shared_weight_layer, vector<bool>* crf_resident_groups = nullptr);
    string domainTag(const string& tag) const;
    unsigned cycle_;
    uint64_t hierarchyTransferCount_;
    uint64_t hierarchyTransferBytes_;
    uint64_t hierarchyTransferCycles_;
    uint64_t depthwiseAccumulatorTransferBytes_;
    uint64_t depthwiseAccumulatorTransferCycles_;
    uint64_t depthwiseAccumulatorOverlapCycles_;
    uint64_t depthwiseAccumulatorWaitCycles_;
    deque<BurstType> depthwiseAccumulatorWritePayloads_;
    unsigned lastPointwiseActiveChannels_;
    unsigned lastPointwisePhysicalOutputDim_;
    unsigned lastPointwiseSpatialGroups_;
    unsigned lastPointwiseBatchWaves_;
    uint64_t logicHabEntries_;
    uint64_t logicHabExits_;
    uint64_t baselineLogicWeightBytes_;
    uint64_t physicalLogicWeightBytes_;
    uint64_t modeledLogicWeightBytes_;
    uint64_t savedLogicWeightBytes_;
    uint64_t logicWeightFillBarrierCycles_;
    uint64_t logicWeightBufferPortWaitCycles_;
    uint64_t logicPostFillGuardCycles_;
    uint64_t logicBroadcastQueueAppliedCycles_;
    uint64_t logicBroadcastQueueLastPreStallCycle_;
    bool pointwiseSpatialOutstanding_;
    bool depthwiseLoweredOutstanding_ = false;
    uint64_t crfProgramCalls_ = 0;
    uint64_t outputLayerGeneration_ = 0;
    bool logicTransactionDomain_ = false;
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
    void addDepthwiseAccumulatorTransactions(int row, int col, int bank, bool final,
                                             bool flush, int num_loop);
    void computeMulToAccumulator(int tile_start, int tile_count, int input_row, int weight_row,
                                 int result_row, bool flush_partial, bool final_tap);
    void advanceDepthwiseAccumulatorTransfer(uint64_t bytes, uint64_t overlap_window);

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
