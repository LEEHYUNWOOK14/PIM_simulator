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

#include "CommandQueue.h"

#include <assert.h>
#include <sstream>

#include "AddressMapping.h"
#include "MemoryController.h"

using namespace DRAMSim;

CommandQueue::CommandQueue(vector<vector<BankState>>& states, ostream& simLog)
    : dramsimLog(simLog),
      bankStates(states),
      nextBank(0),
      nextRank(0),
      nextBankPRE(0),
      nextRankPRE(0),
      refreshRank(0),
      refreshBank(0),
      refreshWaiting(false),
      sendAct(true),
      predicateRejectCycles_(0),
      predicateHolCycles_(0),
      predicateHolCandidates_(0),
      predicateHolMaxCandidates_(0),
      predicateBypassIssues_(0)
{
    issuabilityRejectLastCycle_.fill(std::numeric_limits<uint64_t>::max());
    // set here to avoid compile errors
    currentClockCycle = 0;

    // set system parameters
    num_ranks_ = getConfigParam(UINT, "NUM_RANKS");
    num_banks_ = getConfigParam(UINT, "NUM_BANKS");
    cmd_queue_depth_ = getConfigParam(UINT, "CMD_QUEUE_DEPTH");
    xaw_ = getConfigParam(UINT, "XAW");
    total_row_accesses_ = getConfigParam(UINT, "TOTAL_ROW_ACCESSES");
    schedulingPolicy_ = PIMConfiguration::getSchedulingPolicy();
    queuingStructure_ = PIMConfiguration::getQueueingStructure();

    // use numBankQueus below to create queue structure
    size_t numBankQueues;
    if (queuingStructure_ == PerRank)
    {
        numBankQueues = 1;
    }
    else if (queuingStructure_ == PerRankPerBank)
    {
        numBankQueues = num_banks_;
    }
    else
    {
        ERROR("== Error - Unknown queuing structure");
        exit(0);
    }

    // vector of counters used to ensure rows don't stay open too long
    rowAccessCounters = vector<vector<unsigned>>(num_ranks_, vector<unsigned>(num_banks_, 0));

    // create queue based on the structure we want
    BusPacket1D actualQueue;
    BusPacket2D perBankQueue = BusPacket2D();
    queues = BusPacket3D();
    for (size_t rank = 0; rank < num_ranks_; rank++)
    {
        // this loop will run only once for per-rank and NUM_BANKS times for
        // per-rank-per-bank
        for (size_t bank = 0; bank < numBankQueues; bank++)
        {
            actualQueue = BusPacket1D();
            perBankQueue.push_back(actualQueue);
        }
        queues.push_back(perBankQueue);
    }

    // X-bank activation window
    //    this will count the number of activations within a given window
    //    (decrementing counter)
    //
    // countdown vector will have decrementing counters starting at tXAW
    //  when the 0th element reaches 0, remove it
    tXAWCountdown.reserve(num_ranks_);
    for (size_t i = 0; i < num_ranks_; i++)
    {
        tXAWCountdown.push_back(vector<unsigned>());
    }
}

CommandQueue::~CommandQueue()
{
    // ERROR("COMMAND QUEUE destructor");
    size_t bankMax = num_ranks_;
    if (queuingStructure_ == PerRank)
    {
        bankMax = 1;
    }
    for (size_t r = 0; r < num_ranks_; r++)
    {
        for (size_t b = 0; b < bankMax; b++)
        {
            for (size_t i = 0; i < queues[r][b].size(); i++)
            {
                delete (queues[r][b][i]);
            }
            queues[r][b].clear();
        }
    }
}

// Adds a command to appropriate queue
void CommandQueue::enqueue(BusPacket* newBusPacket)
{
    unsigned rank = newBusPacket->rank;
    unsigned bank = newBusPacket->bank;
    if (queuingStructure_ == PerRank)
    {
        queues[rank][0].push_back(newBusPacket);
        if (queues[rank][0].size() > cmd_queue_depth_)
        {
            ERROR("== Error - Enqueued more than allowed in command queue");
            ERROR(
                "                        Need to call .hasRoomFor(int numberToEnqueue, "
                "unsigned rank, unsigned bank) first");
            exit(0);
        }
    }
    else if (queuingStructure_ == PerRankPerBank)
    {
        queues[rank][bank].push_back(newBusPacket);
        if (queues[rank][bank].size() > cmd_queue_depth_)
        {
            ERROR("== Error - Enqueued more than allowed in command queue");
            ERROR(
                "                        Need to call .hasRoomFor(int numberToEnqueue, "
                "unsigned rank, unsigned bank) first");
            exit(0);
        }
    }
    else
    {
        ERROR("== Error - Unknown queuing structure");
        exit(0);
    }
}

bool CommandQueue::process_refresh(BusPacket** busPacket)
{
    if (refreshWaiting)
    {
        bool sendREF = true;
        for (size_t b = 0; b < num_banks_; b++)
        {
            if (bankStates[refreshRank][b].currentBankState == RowActive)
            {
                sendREF = false;
                *busPacket =
                    new BusPacket(PRECHARGE, 0, 0, bankStates[refreshRank][b].openRowAddress,
                                  refreshRank, b, nullptr, dramsimLog);
                if (isIssuable(*busPacket))
                {
                    return true;
                }
                else
                {
                    delete *busPacket;
                }
            }
        }
        if (sendREF)
        {
            *busPacket = new BusPacket(REF, 0, 0, 0, refreshRank, 0, nullptr, dramsimLog);
            if (isIssuable(*busPacket))
            {
                refreshWaiting = false;
                return true;
            }
            else
            {
                delete *busPacket;
            }
        }
    }
    return false;
}

bool CommandQueue::process_command(BusPacket** busPacket,
                                   const std::function<bool(BusPacket*)>& issuePredicate,
                                   const std::function<bool(BusPacket*)>& probePredicate)
{
    unsigned startingRank = nextRank;
    unsigned startingBank = nextBank;
    bool bypassingRejectedCommand = false;
    // if(refreshWaiting)
    //         return false;
    do
    {
        vector<BusPacket*>& queue = getCommandQueue(nextRank, nextBank);
        for (size_t i = 0; i < queue.size(); i++)
        {
            BusPacket* packet = queue[i];

            if (isIssuable(packet, true))
            {
                if (!getConfigParam(BOOL, "HIERARCHY_SOURCE_QUEUES") && i != 0 &&
                    queue[i]->tag.find("BAR", 0) != std::string::npos)
                    break;
                {
                    if (!hasPriorDependency(queue, i))
                    {
                        const bool accepted =
                            !issuePredicate ||
                            (bypassingRejectedCommand && probePredicate
                                 ? probePredicate(packet)
                                 : issuePredicate(packet));
                        if (!accepted)
                        {
                            if (!bypassingRejectedCommand)
                            {
                                predicateRejectCycles_++;
                                const uint64_t candidates =
                                    countPredicateBypassCandidates(packet, probePredicate);
                                if (candidates > 0)
                                {
                                    predicateHolCycles_++;
                                    predicateHolCandidates_ += candidates;
                                    predicateHolMaxCandidates_ =
                                        max(predicateHolMaxCandidates_, candidates);
                                }
                            }
                            if (getConfigParam(BOOL, "HIERARCHY_READY_BYPASS"))
                            {
                                bypassingRejectedCommand = true;
                                continue;
                            }
                            return false;
                        }
                        *busPacket = packet;
                        queue.erase(queue.begin() + i);
                        if (bypassingRejectedCommand) predicateBypassIssues_++;
                        return true;
                    }
                }
            }
        }

        for (size_t i = 0; i < queue.size(); i++)
        {
            if (!getConfigParam(BOOL, "HIERARCHY_SOURCE_QUEUES") && i != 0 &&
                queue[i]->tag.find("BAR", 0) != std::string::npos)
                break;
            BusPacket* packet = queue[i];
            if (getConfigParam(BOOL, "HIERARCHY_SOURCE_QUEUES") &&
                hasPriorDependency(queue, i))
                continue;
            if (issuePredicate && !issuePredicate(packet))
                continue;
            if (bankStates[packet->rank][packet->bank].currentBankState == Idle)
            {
                *busPacket =
                    new BusPacket(ACTIVATE, packet->physicalAddress, packet->column, packet->row,
                                  packet->rank, packet->bank, nullptr, dramsimLog, packet->tag);
                if (isIssuable(*busPacket, true))
                {
                    return true;
                }
                else
                {
                    delete *busPacket;
                }
            }
        }

        if (queuingStructure_ == PerRank)
            nextRank = (nextRank + 1) % num_ranks_;
        else
            nextRankAndBank(nextRank, nextBank);
    } while (!(startingRank == nextRank && startingBank == nextBank));

    return false;
}

bool CommandQueue::process_precharge(
    BusPacket** busPacket, const std::function<bool(BusPacket*)>& probePredicate)
{
    unsigned startingRank = nextRankPRE;
    unsigned startingBank = nextBankPRE;

    do
    {
        bool found = false;
        std::string prechargeTag;
        vector<BusPacket*>& queue = getCommandQueue(nextRankPRE, nextBankPRE);
        for (size_t i = 0; i < queue.size(); i++)
        {
            BusPacket* packet = queue[i];
            if (probePredicate && !probePredicate(packet))
                continue;
            if (nextRankPRE == packet->rank && nextBankPRE == packet->bank &&
                bankStates[packet->rank][packet->bank].currentBankState == RowActive &&
                packet->row == bankStates[packet->rank][packet->bank].openRowAddress)
                found = true;
            else if (nextRankPRE == packet->rank && nextBankPRE == packet->bank &&
                     prechargeTag.empty())
                prechargeTag = packet->tag;
            if (packet->tag.find("BAR", 0) != std::string::npos)
                break;
        }
        if (!found)
        {
            *busPacket =
                new BusPacket(PRECHARGE, 0, 0, bankStates[nextRankPRE][nextBankPRE].openRowAddress,
                              nextRankPRE, nextBankPRE, nullptr, dramsimLog, prechargeTag);
            // An empty tag means this is only the scheduler's speculative scan of
            // an unrelated bank, not a PRE required by a queued request.
            if (isIssuable(*busPacket, !prechargeTag.empty()))
                return true;
            else
                delete *busPacket;
        }
        nextRankAndBank(nextRankPRE, nextBankPRE);
    } while (!(startingRank == nextRankPRE && startingBank == nextBankPRE));

    return false;
}

bool CommandQueue::pop(BusPacket** busPacket,
                       const std::function<bool(BusPacket*)>& issuePredicate,
                       const std::function<bool(BusPacket*)>& probePredicate)
{
    issuabilityRejectedThisPop_.fill(false);
    bankStateTagRejectedThisPop_.fill(false);
    bankStateRawTagsRejectedThisPop_.clear();
    if (queuingStructure_ == PerRankPerBank)
    {
        ERROR("== Error - queuingStructure_ PerRankPerBank is not allowed");
        exit(0);
    }
    for (size_t i = 0; i < num_ranks_; i++)
    {
        // decrement all the counters we have going
        for (size_t j = 0; j < tXAWCountdown[i].size(); j++) tXAWCountdown[i][j]--;
        // the head will always be the smallest counter, so check if it has reached 0
        if (tXAWCountdown[i].size() > 0 && tXAWCountdown[i][0] == 0)
            tXAWCountdown[i].erase(tXAWCountdown[i].begin());
    }

    if (process_refresh(busPacket))
        return true;
    else if (process_command(busPacket, issuePredicate, probePredicate))
        return true;
    else if (process_precharge(busPacket, probePredicate))
        return true;
    else
        return false;
    return false;
}

// check if a rank/bank queue has room for a certain number of bus packets
bool CommandQueue::hasRoomFor(unsigned numberToEnqueue, unsigned rank, unsigned bank)
{
    vector<BusPacket*>& queue = getCommandQueue(rank, bank);
    return ((cmd_queue_depth_ - queue.size()) >= numberToEnqueue);
}

// prints the contents of the command queue
void CommandQueue::print()
{
    if (queuingStructure_ == PerRank)
    {
        PRINT(endl << "== Printing Per Rank Queue");
        for (size_t i = 0; i < num_ranks_; i++)
        {
            PRINT(" = Rank " << i << "  size : " << queues[i][0].size());
            for (size_t j = 0; j < queues[i][0].size(); j++)
            {
                PRINTN("    " << j << "]");
                queues[i][0][j]->print();
            }
        }
    }
    else if (queuingStructure_ == PerRankPerBank)
    {
        PRINT("\n== Printing Per Rank, Per Bank Queue");

        for (size_t i = 0; i < num_ranks_; i++)
        {
            PRINT(" = Rank " << i);
            for (size_t j = 0; j < num_banks_; j++)
            {
                PRINT("    Bank " << j << "   size : " << queues[i][j].size());

                for (size_t k = 0; k < queues[i][j].size(); k++)
                {
                    PRINTN("       " << k << "]");
                    queues[i][j][k]->print();
                }
            }
        }
    }
}

/**
 * return a reference to the queue for a given rank, bank. Since we
 * don't always have a per bank queuing structure, sometimes the bank
 * argument is ignored (and the 0th index is returned
 */
vector<BusPacket*>& CommandQueue::getCommandQueue(unsigned rank, unsigned bank)
{
    if (queuingStructure_ == PerRankPerBank)
        return queues[rank][bank];
    else if (queuingStructure_ == PerRank)
        return queues[rank][0];
    else
    {
        ERROR("Unknown queue structure");
        abort();
    }
}

// checks if busPacket is allowed to be issued
CommandTagClass CommandQueue::classifyTag(const string& tag)
{
    if (tag.find("LOGIC_WEIGHT_FILL") != string::npos) return CommandTagClass::WEIGHT_FILL;
    if (tag.find("PARK_") != string::npos) return CommandTagClass::PARK;
    if (tag.find("SB_TO_HAB") != string::npos ||
        tag.find("HAB_TO_SB") != string::npos || tag.find("_PIM") != string::npos)
        return CommandTagClass::MODE_CONTROL;
    if (tag.find("PROGRAM_LOGIC_CRF") != string::npos ||
        tag.find("PROGRAM_BANK_CRF") != string::npos)
        return CommandTagClass::CRF_CONTROL;
    if (tag.find("WRIO_TO_GRF") != string::npos ||
        tag.find("PRELOAD_DATA") != string::npos)
        return CommandTagClass::INPUT_UPLOAD;
    if (tag.find("MAC_") != string::npos) return CommandTagClass::MAC;
    if (tag.find("OUTPUT") != string::npos || tag.find("output") != string::npos ||
        tag.find("GRFB_TO_BANK") != string::npos)
        return CommandTagClass::OUTPUT;
    return CommandTagClass::OTHER;
}

string CommandQueue::normalizeTag(const string& tag)
{
    string normalized = tag;
    const string logicDomain = "LOGIC_DOMAIN_";
    const string bankDomain = "BANK_DOMAIN_";
    if (normalized.rfind(logicDomain, 0) == 0)
        normalized.erase(0, logicDomain.size());
    else if (normalized.rfind(bankDomain, 0) == 0)
        normalized.erase(0, bankDomain.size());
    size_t metadata = normalized.find("LOGIC_SEQ_");
    if (metadata == string::npos) metadata = normalized.find("BANK_SEQ_");
    if (metadata != string::npos) normalized.erase(metadata);
    size_t barrier = normalized.find("BAR");
    if (barrier != string::npos) normalized.erase(barrier);
    while (!normalized.empty() && normalized.back() == '_') normalized.pop_back();
    return normalized.empty() ? "EMPTY" : normalized;
}

void CommandQueue::recordIssuabilityReject(CommandIssuabilityRejectReason reason,
                                            const BusPacket* packet)
{
    const size_t index = static_cast<size_t>(reason);
    issuabilityRejectedThisPop_[index] = true;
    if (reason == CommandIssuabilityRejectReason::BANK_STATE && packet != nullptr)
    {
        bankStateTagRejectedThisPop_[static_cast<size_t>(classifyTag(packet->tag))] = true;
        bankStateRawTagsRejectedThisPop_.insert(normalizeTag(packet->tag));
    }
    issuabilityRejectAttempts_[index]++;
    if (issuabilityRejectLastCycle_[index] != currentClockCycle)
    {
        issuabilityRejectLastCycle_[index] = currentClockCycle;
        issuabilityRejectWallCycles_[index]++;
    }
}

bool CommandQueue::isIssuable(BusPacket* busPacket, bool recordReject)
{
    if (!getConfigParam(BOOL, "LOGIC_GLOBAL_SCHEDULER") && busPacket->busPacketType != REF &&
        busPacket->busPacketType != RFCSB &&
        (*ranks)[busPacket->rank]->pimRank->isLogicDieBusy(currentClockCycle))
    {
        if (recordReject)
            recordIssuabilityReject(CommandIssuabilityRejectReason::LOGIC_PCU_BUSY);
        return false;
    }

    switch (busPacket->busPacketType)
    {
        case REF:
        case RFCSB:
            return true;
            break;
        case ACTIVATE:

            if ((*ranks)[busPacket->rank]->getModeForPacket(busPacket) != dramMode::SB &&
                busPacket->bank >= 2)
            {
                if (recordReject)
                    recordIssuabilityReject(CommandIssuabilityRejectReason::MODE_BLOCKED);
                return false;
            }

            if (bankStates[busPacket->rank][busPacket->bank].currentBankState != Idle &&
                bankStates[busPacket->rank][busPacket->bank].currentBankState != Refreshing)
            {
                if (recordReject)
                    recordIssuabilityReject(CommandIssuabilityRejectReason::BANK_STATE,
                                            busPacket);
                return false;
            }
            if (currentClockCycle < bankStates[busPacket->rank][busPacket->bank].nextActivate)
            {
                if (recordReject)
                    recordIssuabilityReject(CommandIssuabilityRejectReason::TIMING);
                return false;
            }
            if (tXAWCountdown[busPacket->rank].size() >= xaw_)
            {
                if (recordReject)
                    recordIssuabilityReject(CommandIssuabilityRejectReason::XAW_LIMIT);
                return false;
            }
            return true;
            break;

        case WRITE:
            if (bankStates[busPacket->rank][busPacket->bank].currentBankState != RowActive)
            {
                if (recordReject)
                    recordIssuabilityReject(CommandIssuabilityRejectReason::BANK_STATE,
                                            busPacket);
                return false;
            }
            if (currentClockCycle < bankStates[busPacket->rank][busPacket->bank].nextWrite)
            {
                if (recordReject)
                    recordIssuabilityReject(CommandIssuabilityRejectReason::TIMING);
                return false;
            }
            if (busPacket->row != bankStates[busPacket->rank][busPacket->bank].openRowAddress)
            {
                if (recordReject)
                    recordIssuabilityReject(CommandIssuabilityRejectReason::ROW_MISMATCH);
                return false;
            }
            if (rowAccessCounters[busPacket->rank][busPacket->bank] >= total_row_accesses_)
            {
                if (recordReject)
                    recordIssuabilityReject(CommandIssuabilityRejectReason::ROW_ACCESS_LIMIT);
                return false;
            }
            return true;
            break;
        case READ:
            if (bankStates[busPacket->rank][busPacket->bank].currentBankState != RowActive)
            {
                if (recordReject)
                    recordIssuabilityReject(CommandIssuabilityRejectReason::BANK_STATE,
                                            busPacket);
                return false;
            }
            if (currentClockCycle < bankStates[busPacket->rank][busPacket->bank].nextRead)
            {
                if (recordReject)
                    recordIssuabilityReject(CommandIssuabilityRejectReason::TIMING);
                return false;
            }
            if (busPacket->row != bankStates[busPacket->rank][busPacket->bank].openRowAddress)
            {
                if (recordReject)
                    recordIssuabilityReject(CommandIssuabilityRejectReason::ROW_MISMATCH);
                return false;
            }
            if (rowAccessCounters[busPacket->rank][busPacket->bank] >= total_row_accesses_)
            {
                if (recordReject)
                    recordIssuabilityReject(CommandIssuabilityRejectReason::ROW_ACCESS_LIMIT);
                return false;
            }
            return true;
            break;
        case PRECHARGE:
            if (bankStates[busPacket->rank][busPacket->bank].currentBankState != RowActive)
            {
                if (recordReject)
                    recordIssuabilityReject(CommandIssuabilityRejectReason::BANK_STATE,
                                            busPacket);
                return false;
            }
            if (currentClockCycle < bankStates[busPacket->rank][busPacket->bank].nextPrecharge)
            {
                if (recordReject)
                    recordIssuabilityReject(CommandIssuabilityRejectReason::TIMING);
                return false;
            }
            return true;
            break;

        default:
            ERROR("== Error - Trying to issue a crazy bus packet type : ");
            busPacket->print();
            exit(0);
    }
    return false;
}

// figures out if a rank's queue is empty
bool CommandQueue::isEmpty(unsigned rank)
{
    if (queuingStructure_ == PerRank)
    {
        return queues[rank][0].empty();
    }
    else if (queuingStructure_ == PerRankPerBank)
    {
        for (size_t i = 0; i < num_banks_; i++)
        {
            if (!queues[rank][i].empty())
                return false;
        }
        return true;
    }
    else
    {
        DEBUG("Invalid Queueing Stucture");
        abort();
    }
}

// tells the command queue that a particular rank is in need of a refresh
void CommandQueue::needRefresh(unsigned rank)
{
    refreshWaiting = true;
    refreshRank = rank;
}

void CommandQueue::nextRankAndBank(unsigned& rank, unsigned& bank)
{
    if (schedulingPolicy_ == RankThenBankRoundRobin)
    {
        rank++;
        if (rank == num_ranks_)
        {
            rank = 0;
            bank++;
            if (bank == num_banks_)
            {
                bank = 0;
            }
        }
    }
    // bank-then-rank round robin
    else if (schedulingPolicy_ == BankThenRankRoundRobin)
    {
        bank++;
        if (bank == num_banks_)
        {
            bank = 0;
            rank++;
            if (rank == num_ranks_)
            {
                rank = 0;
            }
        }
    }
    else
    {
        ERROR("== Error - Unknown scheduling policy");
        exit(0);
    }
}

void CommandQueue::update()
{
    // do nothing since pop() is effectively update(),
    // needed for SimulatorObject
    // TODO: make CommandQueue not a SimulatorObject
}
string CommandQueue::getDebugSummary() const
{
    stringstream summary;
    unsigned shown = 0;
    for (unsigned rank = 0; rank < queues.size() && shown < 4; rank++)
        for (unsigned bank = 0; bank < queues[rank].size() && shown < 4; bank++)
        {
            const auto& queue = queues[rank][bank];
            if (queue.empty()) continue;
            const BusPacket* packet = queue.front();
            summary << " q" << rank << ":" << bank << "[" << queue.size() << "]"
                    << "_packet_bank[" << packet->bank << "]"
                    << "_type[" << static_cast<int>(packet->busPacketType) << "]"
                    << "_row[" << packet->row << "]_col[" << packet->column << "]"
                    << "_tag[" << packet->tag << "]"
                    << "_state["
                    << static_cast<int>(bankStates[packet->rank][packet->bank].currentBankState)
                    << "]_open["
                    << bankStates[packet->rank][packet->bank].openRowAddress
                    << "]_next_read["
                    << bankStates[packet->rank][packet->bank].nextRead
                    << "]_next_write["
                    << bankStates[packet->rank][packet->bank].nextWrite
                    << "]_next_act["
                    << bankStates[packet->rank][packet->bank].nextActivate << "]";
            shown++;
        }
    return summary.str();
}

bool CommandQueue::popDirect(
    BusPacket** busPacket, const std::function<bool(BusPacket*)>& issuePredicate)
{
    unsigned startingRank = nextRank;
    unsigned startingBank = nextBank;
    do
    {
        BusPacket1D& queue = getCommandQueue(nextRank, nextBank);
        for (size_t index = 0; index < queue.size(); index++)
        {
            BusPacket* packet = queue[index];
            if (hasPriorDependency(queue, index)) continue;
            if (issuePredicate && !issuePredicate(packet)) continue;
            *busPacket = packet;
            queue.erase(queue.begin() + index);
            return true;
        }
        if (queuingStructure_ == PerRank)
            nextRank = (nextRank + 1) % num_ranks_;
        else
            nextRankAndBank(nextRank, nextBank);
    } while (!(startingRank == nextRank && startingBank == nextBank));
    return false;
}

bool CommandQueue::hasPriorDependency(const BusPacket1D& queue, size_t index) const
{
    const bool source_queues = getConfigParam(BOOL, "HIERARCHY_SOURCE_QUEUES");
    const bool logic = queue[index]->tag.find("LOGIC_DOMAIN_") != std::string::npos;
    if (!source_queues && index != 0 && queue[index]->tag.find("BAR", 0) != std::string::npos)
        return true;
    for (size_t prior = 0; prior < index; prior++)
    {
        const bool prior_logic =
            queue[prior]->tag.find("LOGIC_DOMAIN_") != std::string::npos;
        if (source_queues && logic != prior_logic) continue;
        if (queue[index]->bank == queue[prior]->bank &&
            queue[index]->row == queue[prior]->row &&
            queue[index]->column == queue[prior]->column)
            return true;
        if (queue[prior]->tag.find("BAR", 0) != std::string::npos) return true;
    }
    return false;
}

uint64_t CommandQueue::countPredicateBypassCandidates(
    BusPacket* blockedPacket, const std::function<bool(BusPacket*)>& probePredicate)
{
    uint64_t candidates = 0;
    for (auto& rankQueues : queues)
    {
        for (auto& queue : rankQueues)
        {
            for (size_t index = 0; index < queue.size(); index++)
            {
                BusPacket* packet = queue[index];
                if (packet == blockedPacket || !isIssuable(packet) ||
                    hasPriorDependency(queue, index))
                    continue;
                if (!probePredicate || probePredicate(packet)) candidates++;
            }
        }
    }
    return candidates;
}
