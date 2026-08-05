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

#ifndef _PIMRANK_H_
#define _PIMRANK_H_

#include <vector>
#include <unordered_map>

#include "AddressMapping.h"
#include "BusPacket.h"
#include "Configuration.h"
#include "PIMBlock.h"
#include "PIMCmd.h"
#include "LogicDieScheduler.h"
#include "LogicDieWeightBuffer.h"
#include "LogicDieAccumulator.h"
#include "Rank.h"
#include "SimulatorObject.h"

using namespace std;
using namespace DRAMSim;

namespace DRAMSim
{
#define OUTLOG_ALL(msg)                                                                       \
    msg << " ch[" << getChanId() << "] ra[" << getRankId() << "] bg["                         \
        << config.addrMapping.bankgroupId(packet->bank) << "] ba[" << packet->bank << "] ro[" \
        << packet->row << "] co[" << packet->column << "] @" << currentClockCycle
#define OUTLOG_CH_RA(msg) \
    msg << " ch[" << getChanId() << "] ra[" << getRankId() << "] @" << currentClockCycle
#define OUTLOG_PRECHARGE(msg)                                                                 \
    msg << " ch[" << getChanId() << "] ra[" << getRankId() << "] bg["                         \
        << config.addrMapping.bankgroupId(packet->bank) << "] ba[" << packet->bank << "] ro[" \
        << bankStates[packet->bank].openRowAddress << "] @" << currentClockCycle
#define OUTLOG_GRF_A(msg)                                                                 \
    msg << " ch[" << getChanId() << "] ra[" << getRankId() << "] pb[" << packet->bank / 2 \
        << " reg" << packet->column - 0x8 << " @" << currentClockCycle
#define OUTLOG_GRF_B(msg)                                                                 \
    msg << " ch[" << getChanId() << "] ra[" << getRankId() << "] pb[" << packet->bank / 2 \
        << "] reg[" << packet->column - 0x18 << "] @" << currentClockCycle
#define OUTLOG_B_GRF_A(msg)                                                                    \
    msg << " ch[" << getChanId() << "] ra[" << getRankId() << "] reg[" << packet->column - 0x8 \
        << "] @" << currentClockCycle
#define OUTLOG_B_GRF_B(msg)                                                                     \
    msg << " ch[" << getChanId() << "] ra[" << getRankId() << "] reg[" << packet->column - 0x18 \
        << "] @" << currentClockCycle
#define OUTLOG_B_CRF(msg)                                                                      \
    msg << " ch[" << getChanId() << "] ra[" << getRankId() << "] idx[" << packet->column - 0x4 \
        << "] @" << currentClockCycle

class Rank;  // forward declaration

class PIMRank : public SimulatorObject
{
  private:
    enum class PIMRouteMode
    {
        BANK_ONLY,
        LOGIC_ONLY,
        HYBRID
    };
    int chanId;
    int rankId;
    ostream& dramsimLog;
    Configuration& config;
    struct PIMExecutionContext
    {
        int pc = 0;
        int lastJump = -1;
        int jumpsRemaining = -1;
        int lastRepeat = -1;
        int repeatsRemaining = -1;
        bool pimOpMode = false;
        bool toggleEvenBank = false;
        bool toggleOddBank = false;
        bool toggleRa13h = false;
        bool crfExit = false;
    };
    PIMExecutionContext bankContext_;
    PIMExecutionContext logicContext_;
    uint64_t logicBusyUntil_;
    uint64_t logicCommandCount_;
    uint64_t logicComputeCycles_;
    uint64_t logicTransferBytes_;
    uint64_t logicTransferCycles_;
    uint64_t logicServiceCycles_;
    unsigned lastLogicServiceCycles_;
    uint64_t lastLogicReleaseEpoch_;
    uint64_t logicCommandOrdinal_;
    shared_ptr<LogicDieScheduler> logicScheduler_;
    shared_ptr<LogicDieWeightBuffer> logicWeightBuffer_;
    shared_ptr<LogicDieAccumulator> logicAccumulator_;
    unordered_map<uint64_t, BurstType> bankLocalAccumulator_;
    unordered_map<uint64_t, unsigned> bankLocalAccumulatorCounts_;
    uint64_t bankLocalAccumulatorBusyUntil_ = 0;
    uint64_t bankLocalAccumulatorStalls_ = 0;
    uint64_t bankLocalAccumulatorPeakEntries_ = 0;
    vector<unsigned> bankLocalAccumulatorEntriesPerBank_;
    vector<unsigned> bankLocalAccumulatorPeakEntriesPerBank_;

  public:
    PIMRank(ostream& simLog, Configuration& configuration,
            shared_ptr<LogicDieScheduler> logicScheduler,
            shared_ptr<LogicDieWeightBuffer> logicWeightBuffer,
            shared_ptr<LogicDieAccumulator> logicAccumulator);
    ~PIMRank() {}

    void attachRank(Rank* r);
    int getChanId() const;
    void setChanId(int id);
    int getRankId() const;
    void setRankId(int id);
    void update();
    void readHab(BusPacket* packet);
    void writeHab(BusPacket* packet);
    void doPIM(BusPacket* packet);
    void doPIMBlock(BusPacket* packet, PIMCmd curCmd, int pimblock_id);
    void controlPIM(BusPacket* packet);
    void readOpd(int pb, BurstType& bst, PIMOpdType type, BusPacket* packet, int idx, bool is_auto,
                 bool is_mac, bool use_logic_die);
    void writeOpd(int pb, BurstType& bst, PIMOpdType type, BusPacket* packet, int idx, bool is_auto,
                  bool is_mac, bool use_logic_die);
    bool isToggleCond(BusPacket* packet);
    bool isBankSideEnabled() const;
    bool isLogicDieEnabled() const;
    bool isHybridEnabled() const;
    PIMRouteMode getRouteMode() const;
    const char* routeModeToStr(PIMRouteMode mode) const;
    bool shouldRouteToLogicDie(PIMCmd cCmd) const;
    unsigned reserveLogicDie(PIMCmd cCmd);
    bool canAcceptLogicDieCommand(const BusPacket* packet, bool recordStall = true) const;
    unsigned consumeLastLogicServiceCycles();
    bool isLogicDieBusy(uint64_t cycle) const;
    uint64_t getLogicCommandCount() const;
    uint64_t getLogicComputeCycles() const;
    uint64_t getLogicTransferBytes() const;
    uint64_t getLogicTransferCycles() const;
    uint64_t getLogicServiceCycles() const;
    void executeLogicDieCmd(BusPacket* packet, PIMCmd cCmd, int pimblock_id);
    void dispatchLogicDieStub(PIMCmd cCmd, BusPacket* packet);
    vector<PIMBlock>& getActivePIMBlocks(bool use_logic_die);
    const vector<PIMBlock>& getActivePIMBlocks(bool use_logic_die) const;
    void readLogicOutput(BusPacket* packet);
    void handleLogicAccumulatorPacket(BusPacket* packet);
    void beginBankLocalAccumulation();
    bool canAcceptBankLocalAccumulator(const BusPacket* packet, bool recordStall = true);
    uint64_t getBankLocalAccumulatorStalls() const { return bankLocalAccumulatorStalls_; }
    uint64_t getBankLocalAccumulatorPeakEntries() const
    {
        return bankLocalAccumulatorPeakEntries_;
    }
    uint64_t getBankLocalAccumulatorPeakEntriesPerBank() const;

  private:
    bool peekNextExecutableCommand(PIMCmd& command, bool logic_die) const;
    LogicCommandContext peekLogicCommandContext() const;
    bool isLogicCommandPacket(const BusPacket* packet) const;
    PIMExecutionContext& contextForPacket(const BusPacket* packet);
    const PIMExecutionContext& contextForPacket(const BusPacket* packet) const;

  public:

    union crf_t
    {
        uint32_t data[32];
        BurstType bst[4];
        crf_t()
        {
            memset(data, 0, sizeof(uint32_t) * 32);
        }
    } crf, logicCrf;

    unsigned inline getGrfIdx(unsigned idx)
    {
        return idx & 0x7;
    }
    unsigned inline getGrfIdxHigh(unsigned r, unsigned c)
    {
        return ((r & 0x1) << 2 | ((c >> 3) & 0x3));
    }
    unsigned inline isReservedRA(unsigned row)
    {
        return (row & (1 << 13));
    }
    unsigned inline masked2accessibleRA(unsigned row)
    {
        return (row & ((1 << 13) - 1));
    }

    Rank* rank;
    vector<PIMBlock> pimBlocks;
    vector<PIMBlock> logicPimBlocks;
};
}  // namespace DRAMSim
#endif
