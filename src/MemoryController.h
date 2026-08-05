/*********************************************************************************
 *  Copyright (c) 2010-2011, Elliott Cooper-Balis
 *                             Paul Rosenfeld
 *                             Bruce Jacob
 *                             University of Maryland
 *                             dramninjas [at] gmail [dot] com
 *  All rights reserved.
 *
 *  Redistribution and use in source and binary forms, with or without
 *  modification, are permitted provided that the following conditions are met:
 *
 *     * Redistributions of source code must retain the above copyright notice,
 *        this list of conditions and the following disclaimer.
 *
 *     * Redistributions in binary form must reproduce the above copyright notice,
 *        this list of conditions and the following disclaimer in the documentation
 *        and/or other materials provided with the distribution.
 *
 *  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 *  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 *  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 *  DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
 *  FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 *  DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 *  SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 *  CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 *  OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 *  OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *********************************************************************************/

#ifndef MEMORYCONTROLLER_H
#define MEMORYCONTROLLER_H

#include <array>
#include <map>
#include <vector>

#include "BankState.h"
#include "BusPacket.h"
#include "CSVWriter.h"
#include "CommandQueue.h"
#include "Configuration.h"
#include "Rank.h"
#include "SimulatorObject.h"
#include "SystemConfiguration.h"
#include "Transaction.h"

using namespace std;

namespace DRAMSim
{
enum class HierarchyPredicateBlockReason
{
    EPOCH_MISMATCH,
    BARRIER_OUTSTANDING,
    WRITE_BUS_BUSY,
    COUNT
};

class Rank;
class MemorySystem;
class MemoryControllerStats;
enum class BarrierTagClass : size_t
{
    PARK,
    OPERAND_LOAD,
    ALU,
    MAC,
    OUTPUT,
    OTHER,
    COUNT
};
class MemoryController : public SimulatorObject
{
  public:
    // functions
    MemoryController(MemorySystem* ms, CSVWriter& csvOut_, ostream& simLog, Configuration& config);
    virtual ~MemoryController();

    bool addTransaction(Transaction* trans);
    void returnReadData(const Transaction* trans);
    void receiveFromBus(BusPacket* bpacket);
    void attachRanks(vector<Rank*>* ranks);
    void update();
    void printDebugOnUpate();
    void printStats(bool finalStats = false);
    void resetStats();
    string getCommandQueueDebugSummary() const;
    uint64_t getTotalRefreshes() const { return totalRefreshes; }
    uint64_t getCommandPredicateRejectCycles() const
    {
        return commandQueue.getPredicateRejectCycles();
    }
    uint64_t getCommandPredicateHolCycles() const
    {
        return commandQueue.getPredicateHolCycles();
    }
    uint64_t getCommandPredicateHolCandidates() const
    {
        return commandQueue.getPredicateHolCandidates();
    }
    uint64_t getCommandPredicateHolMaxCandidates() const
    {
        return commandQueue.getPredicateHolMaxCandidates();
    }
    uint64_t getCommandPredicateBypassIssues() const
    {
        return commandQueue.getPredicateBypassIssues();
    }
    uint64_t getIssuabilityRejectAttempts(CommandIssuabilityRejectReason reason) const
    {
        return commandQueue.getIssuabilityRejectAttempts(reason);
    }
    uint64_t getIssuabilityRejectWallCycles(CommandIssuabilityRejectReason reason) const
    {
        return commandQueue.getIssuabilityRejectWallCycles(reason);
    }
    uint64_t getIssuabilityBlockedControllerCycles(CommandIssuabilityRejectReason reason) const
    {
        return issuabilityBlockedControllerCycles_[static_cast<size_t>(reason)];
    }
    bool wasIssuabilityBlockedThisCycle(CommandIssuabilityRejectReason reason) const
    {
        return issuabilityBlockedThisCycle_[static_cast<size_t>(reason)];
    }
    bool wasRankModeBlockedThisCycle() const { return rankModeBlockedThisCycle_; }
    bool wasRankLogicQueueBlockedThisCycle() const
    {
        return rankLogicQueueBlockedThisCycle_;
    }
    bool wasHierarchyPredicateBlockedThisCycle(HierarchyPredicateBlockReason reason) const
    {
        return hierarchyPredicateBlockedThisCycle_[static_cast<size_t>(reason)];
    }
    uint64_t getHierarchyPredicateBlockedControllerCycles(
        HierarchyPredicateBlockReason reason) const
    {
        return hierarchyPredicateBlockedControllerCycles_[static_cast<size_t>(reason)];
    }
    bool wasBankStateTagBlockedThisCycle(CommandTagClass tagClass) const
    {
        return bankStateTagBlockedThisCycle_[static_cast<size_t>(tagClass)];
    }
    const map<string, uint64_t>& getBankStateBlockedCyclesByRawTag() const
    {
        return bankStateBlockedCyclesByRawTag_;
    }
    uint64_t getEpochMismatchRejects() const { return epochMismatchRejects_; }
    uint64_t getBarrierOutstandingRejects() const { return barrierOutstandingRejects_; }
    uint64_t getWriteBusBusyRejects() const { return writeBusBusyRejects_; }
    uint64_t getRankCommandRejects() const { return rankCommandRejects_; }
    uint64_t getRankModeTransitionRejects() const { return rankModeTransitionRejects_; }
    uint64_t getRankLogicQueueRejects() const { return rankLogicQueueRejects_; }
    uint64_t getRankBankDomainRejects() const { return rankBankDomainRejects_; }
    uint64_t getRankLogicDomainRejects() const { return rankLogicDomainRejects_; }
    uint64_t getRankModeBlockedControllerCycles() const
    {
        return rankModeBlockedControllerCycles_;
    }
    uint64_t getRankLogicQueueBlockedControllerCycles() const
    {
        return rankLogicQueueBlockedControllerCycles_;
    }
    uint64_t getWriteDataCompletions(WriteCompletionClass completionClass) const
    {
        return writeDataCompletions_[static_cast<size_t>(completionClass)];
    }
    uint64_t getWriteBarrierCompletions(WriteCompletionClass completionClass) const
    {
        return writeBarrierCompletions_[static_cast<size_t>(completionClass)];
    }
    uint64_t getBarrierOutstandingRejects(WriteCompletionClass completionClass) const
    {
        return barrierOutstandingRejectsByClass_[static_cast<size_t>(completionClass)];
    }
    uint64_t getEpochMismatchRejects(WriteCompletionClass completionClass) const
    {
        return epochMismatchRejectsByClass_[static_cast<size_t>(completionClass)];
    }
    uint64_t getBarrierOutstandingRejects(BarrierTagClass tagClass) const
    {
        return barrierOutstandingRejectsByTag_[static_cast<size_t>(tagClass)];
    }
    uint64_t getEpochMismatchRejects(BarrierTagClass tagClass) const
    {
        return epochMismatchRejectsByTag_[static_cast<size_t>(tagClass)];
    }
    const map<string, uint64_t>& getBarrierOutstandingRejectsByRawTag() const
    {
        return barrierOutstandingRejectsByRawTag_;
    }
    const map<string, uint64_t>& getEpochMismatchRejectsByRawTag() const
    {
        return epochMismatchRejectsByRawTag_;
    }
    bool WillAcceptTransaction();
    bool addBarrier();

    // fields
    vector<Transaction*> transactionQueue;

  private:
    ostream& dramsimLog;
    vector<vector<BankState>> bankStates;
    vector<vector<BankState>> logicControlBankStates;

    // functions
    void insertHistogram(unsigned latencyValue, unsigned rank, unsigned bank);
    void updateCommandQueue(BusPacket* poppedBusPacket);
    void updateTransactionQueue();
    void updateBankState();
    void updateRefresh();
    bool isLogicControlPacket(const BusPacket* packet) const;
    bool isLogicControlTransaction(const Transaction* transaction, unsigned row) const;
    uint64_t logicEpoch(const string& tag) const;
    uint64_t bankEpoch(const string& tag) const;
    bool canIssueEpochBarrier(const BusPacket* packet) const;
    bool hasWriteDataSlot() const;
    bool canIssueHierarchyCommand(BusPacket* packet, bool updateRankState,
                                  bool countRejection);
    void completeEpochTransaction(const BusPacket* packet);
    void completeEpochAndAdvance(const BusPacket* packet);
    void setBankStatesRW(size_t rank, size_t bank, uint64_t nextRead, uint64_t nextWrite);
    void setBankStates(size_t rank, size_t bank, CurrentBankState currentBankState,
                       BusPacketType lastCommand, uint64_t stateChangeCountdown, uint64_t nextAct);

    // fields
    MemorySystem* parentMemorySystem;

    CommandQueue commandQueue;
    CommandQueue logicControlCommandQueue;
    BusPacket* poppedBusPacket;
    vector<BusPacket*> writeDataToSend;
    vector<unsigned> writeDataCountdown;
    vector<Transaction*> returnTransaction;
    vector<Transaction*> pendingReadTransactions;
    map<unsigned, unsigned> latencies;  // latencyValue -> latencyCount
    vector<bool> powerDown;
    vector<Rank*>* ranks;

    // output file
    CSVWriter& csvOut;

    // these packets are counting down waiting to be transmitted on the "bus"
    BusPacket *outgoingCmdPacket, *outgoingDataPacket;
    unsigned cmdCyclesLeft, dataCyclesLeft;

    uint64_t totalTransactions, totalRefreshes;
    vector<uint64_t> grandTotalBankAccesses, totalReadsPerBank, totalWritesPerBank;
    vector<uint64_t> totalReadsPerRank, totalWritesPerRank;
    vector<uint64_t> totalActivatesPerBank, totalActivatesPerRank, totalEpochLatency;
    unsigned refreshRank, refreshBank;
    vector<unsigned> refreshCountdown, refreshCountdownBank;
    Configuration& config;
    MemoryControllerStats* memoryContStats;
    bool nextLogicTransaction_ = false;
    bool nextLogicControlCommand_ = false;
    uint64_t nextLogicSequenceToAssign_ = 0;
    uint64_t nextBankSequenceToAssign_ = 0;
    uint64_t logicEpochToAssign_ = 0;
    uint64_t logicEpochToIssue_ = 0;
    uint64_t bankEpochToAssign_ = 0;
    uint64_t bankEpochToIssue_ = 0;
    map<uint64_t, uint64_t> logicEpochOutstanding_;
    map<uint64_t, uint64_t> bankEpochOutstanding_;
    map<uint64_t, WriteCompletionClass> logicEpochBarrierClass_;
    map<uint64_t, WriteCompletionClass> bankEpochBarrierClass_;
    map<uint64_t, BarrierTagClass> logicEpochBarrierTagClass_;
    map<uint64_t, BarrierTagClass> bankEpochBarrierTagClass_;
    map<uint64_t, string> logicEpochBarrierRawTag_;
    map<uint64_t, string> bankEpochBarrierRawTag_;
    uint64_t epochMismatchRejects_ = 0;
    uint64_t barrierOutstandingRejects_ = 0;
    uint64_t writeBusBusyRejects_ = 0;
    uint64_t rankCommandRejects_ = 0;
    uint64_t rankModeTransitionRejects_ = 0;
    uint64_t rankLogicQueueRejects_ = 0;
    uint64_t rankBankDomainRejects_ = 0;
    uint64_t rankLogicDomainRejects_ = 0;
    bool rankModeRejectedThisCycle_ = false;
    bool rankLogicQueueRejectedThisCycle_ = false;
    uint64_t rankModeBlockedControllerCycles_ = 0;
    uint64_t rankLogicQueueBlockedControllerCycles_ = 0;
    bool rankModeBlockedThisCycle_ = false;
    bool rankLogicQueueBlockedThisCycle_ = false;
    static constexpr size_t issuabilityRejectReasonCount_ =
        static_cast<size_t>(CommandIssuabilityRejectReason::COUNT);
    array<uint64_t, issuabilityRejectReasonCount_> issuabilityBlockedControllerCycles_{};
    array<bool, issuabilityRejectReasonCount_> issuabilityBlockedThisCycle_{};
    static constexpr size_t commandTagClassCount_ =
        static_cast<size_t>(CommandTagClass::COUNT);
    array<bool, commandTagClassCount_> bankStateTagBlockedThisCycle_{};
    map<string, uint64_t> bankStateBlockedCyclesByRawTag_;
    static constexpr size_t hierarchyPredicateBlockReasonCount_ =
        static_cast<size_t>(HierarchyPredicateBlockReason::COUNT);
    array<bool, hierarchyPredicateBlockReasonCount_> hierarchyPredicateRejectedThisCycle_{};
    array<bool, hierarchyPredicateBlockReasonCount_> hierarchyPredicateBlockedThisCycle_{};
    array<uint64_t, hierarchyPredicateBlockReasonCount_>
        hierarchyPredicateBlockedControllerCycles_{};
    static constexpr size_t writeCompletionClassCount_ =
        static_cast<size_t>(WriteCompletionClass::COUNT);
    array<uint64_t, writeCompletionClassCount_> writeDataCompletions_{};
    array<uint64_t, writeCompletionClassCount_> writeBarrierCompletions_{};
    array<uint64_t, writeCompletionClassCount_> barrierOutstandingRejectsByClass_{};
    array<uint64_t, writeCompletionClassCount_> epochMismatchRejectsByClass_{};
    static constexpr size_t barrierTagClassCount_ =
        static_cast<size_t>(BarrierTagClass::COUNT);
    array<uint64_t, barrierTagClassCount_> barrierOutstandingRejectsByTag_{};
    array<uint64_t, barrierTagClassCount_> epochMismatchRejectsByTag_{};
    static BarrierTagClass classifyBarrierTag(const string& tag);
    static string normalizeBarrierTag(const string& tag);
    map<string, uint64_t> barrierOutstandingRejectsByRawTag_;
    map<string, uint64_t> epochMismatchRejectsByRawTag_;

  public:
    // energy values are per rank -- SST uses these directly, so make these public
    vector<uint64_t> backgroundEnergy, burstEnergy, actpreEnergy, refreshEnergy, aluPIMEnergy,
        readPIMEnergy;
    double totalBandwidth;

    uint64_t totalReads, totalWrites;
    uint64_t logicWeightFillWrites;
    uint64_t logicWeightFillCompletedWrites;
    uint64_t logicWeightFillActivates;
    uint64_t logicWeightFillPrecharges;
    uint64_t logicWeightFillLastCompletionCycle;
    uint64_t logicAccumulatorDirectTransfers;
    uint64_t logicAccumulatorCompletedTransfers;
    uint64_t logicAccumulatorFinalWrites;
};

class MemoryControllerStats
{
  public:
    MemoryControllerStats(MemorySystem* parent, CSVWriter& csvOut_, ostream& simLog,
                          Configuration& configuration, uint64_t& totalTrans,
                          vector<uint64_t>& grandTotalBankAcc, vector<uint64_t>& totalReadsPerR,
                          vector<uint64_t>& totalWritesPerR, vector<uint64_t>& totalReadsPerB,
                          vector<uint64_t>& totalWritesPerB, vector<uint64_t>& totalActivatesPerR,
                          vector<uint64_t>& totalActivatesPerB, uint64_t& totalRef,
                          vector<uint64_t>& backgroundE, vector<uint64_t>& burstE,
                          vector<uint64_t>& actpreE, vector<uint64_t>& refreshE,
                          vector<uint64_t>& aluPIME, vector<uint64_t>& readPIME,
                          vector<Transaction*>& pendingReadTrans)
        : csvOut(csvOut_),
          dramsimLog(simLog),
          config(configuration),
          totalTransactions(totalTrans),
          grandTotalBankAccesses(grandTotalBankAcc),
          totalReadsPerRank(totalReadsPerR),
          totalWritesPerRank(totalWritesPerR),
          totalReadsPerBank(totalReadsPerB),
          totalWritesPerBank(totalWritesPerB),
          totalActivatesPerRank(totalActivatesPerR),
          totalActivatesPerBank(totalActivatesPerB),
          totalRefreshes(totalRef),
          backgroundEnergy(backgroundE),
          burstEnergy(burstE),
          actpreEnergy(actpreE),
          refreshEnergy(refreshE),
          aluPIMEnergy(aluPIME),
          readPIMEnergy(readPIME),
          pendingReadTransactions(pendingReadTrans)
    {
        parentMemorySystem = parent;
        totalEpochLatency = vector<uint64_t>(config.NUM_RANKS * config.NUM_BANKS, 0);
        resetStats();
    }

    void printStats(bool finalStats, unsigned myChannel, uint64_t currentClockCycle);
    void insertHistogram(unsigned latencyValue, unsigned rank, unsigned bank);
    void resetStats();

  private:
    MemorySystem* parentMemorySystem;
    ostream& dramsimLog;
    Configuration& config;
    CSVWriter& csvOut;

    uint64_t& totalTransactions;
    vector<uint64_t>& grandTotalBankAccesses;
    vector<uint64_t>& totalReadsPerRank;
    vector<uint64_t>& totalWritesPerRank;
    vector<uint64_t>& totalReadsPerBank;
    vector<uint64_t>& totalWritesPerBank;
    vector<uint64_t>& totalActivatesPerRank;
    vector<uint64_t>& totalActivatesPerBank;
    uint64_t& totalRefreshes;
    vector<uint64_t>& backgroundEnergy;
    vector<uint64_t>& burstEnergy;
    vector<uint64_t>& actpreEnergy;
    vector<uint64_t>& refreshEnergy;
    vector<uint64_t>& aluPIMEnergy;
    vector<uint64_t>& readPIMEnergy;
    vector<Transaction*>& pendingReadTransactions;

    uint64_t currentClockCycle;
    double totalBandwidth;
    map<unsigned, unsigned> latencies;
    vector<uint64_t> totalEpochLatency;
};

}  // namespace DRAMSim

#endif

//
