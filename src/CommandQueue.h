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

#ifndef CMDQUEUE_H
#define CMDQUEUE_H

#include <array>
#include <limits>
#include <set>
#include <vector>
#include <functional>
#include <string>

#include "BankState.h"
#include "BusPacket.h"
#include "SimulatorObject.h"
#include "SystemConfiguration.h"
#include "Transaction.h"

using namespace std;

namespace DRAMSim
{
enum class CommandIssuabilityRejectReason
{
    LOGIC_PCU_BUSY,
    MODE_BLOCKED,
    BANK_STATE,
    TIMING,
    ROW_MISMATCH,
    ROW_ACCESS_LIMIT,
    XAW_LIMIT,
    COUNT
};

enum class CommandTagClass
{
    WEIGHT_FILL,
    PARK,
    MODE_CONTROL,
    CRF_CONTROL,
    INPUT_UPLOAD,
    MAC,
    OUTPUT,
    OTHER,
    COUNT
};

class Rank;
class CommandQueue : public SimulatorObject
{
    CommandQueue();
    ostream& dramsimLog;

  public:
    // typedefs
    typedef vector<BusPacket*> BusPacket1D;
    typedef vector<BusPacket1D> BusPacket2D;
    typedef vector<BusPacket2D> BusPacket3D;

    // functions
    CommandQueue(vector<vector<BankState>>& states, ostream& dramsimLog);
    virtual ~CommandQueue();

    void enqueue(BusPacket* newBusPacket);
    bool pop(BusPacket** busPacket,
             const std::function<bool(BusPacket*)>& issuePredicate = {},
             const std::function<bool(BusPacket*)>& probePredicate = {});
    bool popDirect(BusPacket** busPacket,
                   const std::function<bool(BusPacket*)>& issuePredicate = {});

    // TODO: rename this...
    bool process_refresh(BusPacket** busPacket);
    bool process_command(BusPacket** busPacket,
                         const std::function<bool(BusPacket*)>& issuePredicate,
                         const std::function<bool(BusPacket*)>& probePredicate);
    bool process_precharge(BusPacket** busPacket,
                           const std::function<bool(BusPacket*)>& probePredicate);

    bool hasRoomFor(unsigned numberToEnqueue, unsigned rank, unsigned bank);
    bool isIssuable(BusPacket* busPacket, bool recordReject = false);
    bool isEmpty(unsigned rank);
    void needRefresh(unsigned rank);

    void print();
    string getDebugSummary() const;
    uint64_t getPredicateRejectCycles() const { return predicateRejectCycles_; }
    uint64_t getPredicateHolCycles() const { return predicateHolCycles_; }
    uint64_t getPredicateHolCandidates() const { return predicateHolCandidates_; }
    uint64_t getPredicateHolMaxCandidates() const { return predicateHolMaxCandidates_; }
    uint64_t getPredicateBypassIssues() const { return predicateBypassIssues_; }
    uint64_t getIssuabilityRejectAttempts(CommandIssuabilityRejectReason reason) const
    {
        return issuabilityRejectAttempts_[static_cast<size_t>(reason)];
    }
    uint64_t getIssuabilityRejectWallCycles(CommandIssuabilityRejectReason reason) const
    {
        return issuabilityRejectWallCycles_[static_cast<size_t>(reason)];
    }
    bool hadIssuabilityRejectThisPop(CommandIssuabilityRejectReason reason) const
    {
        return issuabilityRejectedThisPop_[static_cast<size_t>(reason)];
    }
    bool hadBankStateTagRejectThisPop(CommandTagClass tagClass) const
    {
        return bankStateTagRejectedThisPop_[static_cast<size_t>(tagClass)];
    }
    const set<string>& getBankStateRawTagsRejectedThisPop() const
    {
        return bankStateRawTagsRejectedThisPop_;
    }
    void update();  // SimulatorObject requirement
    vector<BusPacket*>& getCommandQueue(unsigned rank, unsigned bank);

    // fields
    BusPacket3D queues;  // 3D array of BusPacket pointers
    vector<vector<BankState>>& bankStates;
    vector<Rank*>* ranks;

  private:
    void nextRankAndBank(unsigned& rank, unsigned& bank);
    bool hasPriorDependency(const BusPacket1D& queue, size_t index) const;
    uint64_t countPredicateBypassCandidates(
        BusPacket* blockedPacket, const std::function<bool(BusPacket*)>& probePredicate);
    // fields

    unsigned nextBank;
    unsigned nextRank;

    unsigned nextBankPRE;
    unsigned nextRankPRE;

    unsigned refreshRank;
    unsigned refreshBank;

    bool refreshWaiting;

    vector<vector<unsigned>> tXAWCountdown;
    vector<vector<unsigned>> rowAccessCounters;

    bool sendAct;

    // preloaded system configuration parameters
    unsigned num_ranks_;
    unsigned num_banks_;
    unsigned cmd_queue_depth_;
    unsigned xaw_;
    unsigned total_row_accesses_;
    SchedulingPolicy schedulingPolicy_;
    QueuingStructure queuingStructure_;
    uint64_t predicateRejectCycles_;
    uint64_t predicateHolCycles_;
    uint64_t predicateHolCandidates_;
    uint64_t predicateHolMaxCandidates_;
    uint64_t predicateBypassIssues_;
    static constexpr size_t issuabilityRejectReasonCount_ =
        static_cast<size_t>(CommandIssuabilityRejectReason::COUNT);
    array<uint64_t, issuabilityRejectReasonCount_> issuabilityRejectAttempts_{};
    array<uint64_t, issuabilityRejectReasonCount_> issuabilityRejectWallCycles_{};
    array<uint64_t, issuabilityRejectReasonCount_> issuabilityRejectLastCycle_{};
    array<bool, issuabilityRejectReasonCount_> issuabilityRejectedThisPop_{};
    static constexpr size_t commandTagClassCount_ =
        static_cast<size_t>(CommandTagClass::COUNT);
    array<bool, commandTagClassCount_> bankStateTagRejectedThisPop_{};
    set<string> bankStateRawTagsRejectedThisPop_;
    static CommandTagClass classifyTag(const string& tag);
    static string normalizeTag(const string& tag);
    void recordIssuabilityReject(CommandIssuabilityRejectReason reason,
                                 const BusPacket* packet = nullptr);
};

}  // namespace DRAMSim
#endif
