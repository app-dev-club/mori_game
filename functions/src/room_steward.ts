import { Database } from "firebase-admin/database";
import {
  generateDeck,
  serializeCard,
  shuffleInPlace,
  shuffledPlayerOrder,
} from "./game_deck";
import {
  HOST_REMATCH_DECISION_MS,
  isMatchEnded,
  isSeriesContinuationPending,
  isSettlementComplete,
  MIN_PLAYERS,
  playerIdsFromRoom,
  SERIES_NEXT_MATCH_MS,
  shouldServerStewardRoom,
} from "./room_lifecycle";
import {
  burstPenalty,
  describeBurstScoring,
  describeMoriScoring,
  moriWinnerDelta,
} from "./scoring_rules";
import { settleRoomSeries } from "./settle_room";
import { applyBurstMorrieDeductionIfNeeded, applyMatchMorrieTransferIfNeeded } from "./morrie_transfer";
import {
  asIntMap,
  asStringList,
  asStringMap,
  resolveMatchCount,
  resolveNonNegativeInt,
} from "./shared";

export interface StewardResult {
  ok: boolean;
  action?: string;
  reason?: string;
}

function asIntArray(raw: unknown): number[] {
  if (!Array.isArray(raw)) return [];
  const out: number[] = [];
  for (const value of raw) {
    if (typeof value === "number" && Number.isFinite(value)) {
      out.push(Math.round(value));
    }
  }
  return out;
}

function resolveDisplayName(
  playerId: string,
  playerNames: Record<string, string>,
): string {
  const name = playerNames[playerId]?.trim();
  if (name) return name;
  return "プレイヤー";
}

async function applyMatchScoringIfNeeded(
  db: Database,
  roomId: string,
  room: Record<string, unknown>,
): Promise<boolean> {
  if (room.lastMatchPointDeltas != null) return false;

  const playerIds = playerIdsFromRoom(room);
  const playerPoints = asIntMap(room.playerPoints);
  for (const id of playerIds) {
    if (playerPoints[id] == null) playerPoints[id] = 0;
  }

  const playerNames = asStringMap(room.playerNames);
  const matchDeltas: Record<string, number> = {};
  let summary: string | null = null;

  const burstPlayerId = room.burstPlayerId?.toString();
  if (burstPlayerId) {
    const penalty = burstPenalty();
    playerPoints[burstPlayerId] = (playerPoints[burstPlayerId] ?? 0) - penalty;
    matchDeltas[burstPlayerId] = -penalty;
    summary = describeBurstScoring(
      resolveDisplayName(burstPlayerId, playerNames),
    );
  } else {
    const winnerId = room.lastMoriPlayerId?.toString();
    const loserId = room.loserPlayerId?.toString();
    const factors = asIntArray(room.moriDeclarationFactors);
    const moriGaeshiCount = resolveNonNegativeInt(room.moriGaeshiCount);
    if (winnerId && loserId && factors.length > 0) {
      const delta = moriWinnerDelta(factors, moriGaeshiCount);
      playerPoints[winnerId] = (playerPoints[winnerId] ?? 0) + delta;
      playerPoints[loserId] = (playerPoints[loserId] ?? 0) - delta;
      matchDeltas[winnerId] = delta;
      matchDeltas[loserId] = -delta;
      summary = describeMoriScoring({
        winnerName: resolveDisplayName(winnerId, playerNames),
        loserName: resolveDisplayName(loserId, playerNames),
        declarationFactors: factors,
        moriGaeshiCount,
        delta,
      });
    }
  }

  if (!summary) return false;

  await db.ref(`rooms/${roomId}`).update({
    playerPoints,
    lastMatchPointSummary: summary,
    lastMatchPointDeltas: matchDeltas,
  });
  return true;
}

async function markPostGameStarted(
  db: Database,
  roomId: string,
  nowMs: number,
): Promise<void> {
  await db.ref(`rooms/${roomId}`).update({
    postGameActive: true,
    postGameEndedAt: nowMs,
    rematchHostRequested: false,
    rematchDeadline: null,
    rematchReady: null,
    roomDismissedByHost: false,
    roomStatus: "closed",
  });
}

async function requestSettlement(db: Database, roomId: string): Promise<void> {
  const roomRef = db.ref(`rooms/${roomId}`);
  const snap = await roomRef.get();
  if (!snap.exists()) return;
  const room = snap.val() as Record<string, unknown>;
  if (isSettlementComplete(room)) return;
  await settleRoomSeries(db, roomId);
}

function seriesMatchResetFields(): Record<string, unknown> {
  return {
    moriPhase: "none",
    moriDeclaredAt: null,
    lastMoriPlayerId: null,
    loserPlayerId: null,
    moriRevealedHand: null,
    moriRevealedType: null,
    burstPlayerId: null,
    morrieBurstPlayerId: null,
    morrieBurstRecoveryApplied: null,
    moriGaeshiCount: null,
    moriDeclarationFactors: null,
    moriDeclaredPlayerIds: null,
    openJokerPlayerIds: null,
    lastMatchPointSummary: null,
    lastMatchPointDeltas: null,
    lastMatchMorrieApplied: null,
    lastMatchMorrieDeltas: null,
    lastMatchMorrieSummary: null,
    lastMatchMorrieBalances: null,
    seriesRatingApplied: null,
    seriesRatingSummary: null,
    seriesRatingDetails: null,
    seriesMorrieSettled: null,
    seriesMorrieSummary: null,
    seriesMorrieDetails: null,
    settlementRequested: null,
    settlementError: null,
    settlementCompletedAt: null,
    lastDrawerId: null,
    lastPlayerId: "system",
    isDrawCompetitive: false,
    deckResetAt: null,
    postGameSeriesAdvanced: null,
    rematchHostRequested: false,
    awaitingGuestStayResponses: false,
    rematchEligiblePlayers: null,
    rematchStartedAt: null,
    rematchDeadline: null,
    rematchReady: null,
  };
}

async function startNextSeriesMatch(
  db: Database,
  roomId: string,
  room: Record<string, unknown>,
): Promise<StewardResult> {
  const roomRef = db.ref(`rooms/${roomId}`);
  await roomRef.update({ seriesRestarting: true });

  const rosterSource = asStringList(room.seriesPlayerIds);
  const roster = shuffledPlayerOrder(
    rosterSource.length > 0 ? rosterSource : playerIdsFromRoom(room),
  );

  if (roster.length < MIN_PLAYERS) {
    await roomRef.remove();
    return { ok: true, action: "deleted_insufficient_players" };
  }

  const deckCards = generateDeck();
  shuffleInPlace(deckCards);

  const playerCards: Record<string, Array<{ number: number; suit: string }>> = {};
  const playerHands: Record<string, number> = {};

  for (const pid of roster) {
    const hand: Array<{ number: number; suit: string }> = [];
    for (let i = 0; i < 5; i++) {
      const card = deckCards.pop();
      if (card) hand.push(serializeCard(card));
    }
    playerCards[pid] = hand;
    playerHands[pid] = hand.length;
  }

  if (deckCards.length === 0) {
    await roomRef.update({
      seriesRestarting: false,
      seriesNextMatchAt: null,
    });
    return { ok: false, action: "empty_deck" };
  }

  const remainingDeck = deckCards.map(serializeCard);

  await roomRef.update({
    players: roster,
    playerCards,
    playerHands,
    deck: remainingDeck,
    deckIndex: remainingDeck,
    field: { number: -1, suit: "joker" },
    fieldHistory: [],
    isInitialPhase: true,
    currentTurnIndex: 0,
    gameStarted: false,
    roomStatus: "open",
    postGameActive: false,
    postGameEndedAt: null,
    seriesRestarting: false,
    seriesNextMatchAt: null,
    seriesPlayerIds: roster,
    ...seriesMatchResetFields(),
  });

  return { ok: true, action: "series_prepared" };
}

async function advanceSeriesAfterMatch(
  db: Database,
  roomId: string,
  room: Record<string, unknown>,
  nowMs: number,
): Promise<StewardResult> {
  const roomRef = db.ref(`rooms/${roomId}`);
  const totalMatches = resolveMatchCount(room.totalMatches);
  const completedMatches = resolveNonNegativeInt(room.completedMatches);

  if (room.morrieBurstPlayerId != null && completedMatches < totalMatches) {
    await roomRef.update({
      completedMatches: totalMatches,
      seriesNextMatchAt: null,
      postGameSeriesAdvanced: true,
      seriesPlayerIds: null,
      seriesRestarting: false,
    });
    await requestSettlement(db, roomId);
    return { ok: true, action: "morrie_burst_series_end" };
  }

  if (totalMatches <= 1) {
    if (completedMatches < 1) {
      await roomRef.update({ completedMatches: 1 });
    }
    await requestSettlement(db, roomId);
    return { ok: true, action: "settlement_single" };
  }

  if (completedMatches >= totalMatches) {
    await requestSettlement(db, roomId);
    return { ok: true, action: "settlement_series_complete" };
  }

  if (room.postGameSeriesAdvanced === true) {
    if (typeof room.seriesNextMatchAt === "number") {
      return { ok: true, action: "already_scheduled" };
    }
    await requestSettlement(db, roomId);
    return { ok: true, action: "settlement_after_advance" };
  }

  const nextCompleted = completedMatches + 1;
  const updates: Record<string, unknown> = {
    completedMatches: nextCompleted,
    postGameSeriesAdvanced: true,
  };

  if (nextCompleted < totalMatches) {
    updates.seriesNextMatchAt = nowMs + SERIES_NEXT_MATCH_MS;
    const roster = asStringList(room.seriesPlayerIds);
    if (roster.length === 0) {
      updates.seriesPlayerIds = playerIdsFromRoom(room);
    }
  } else {
    updates.seriesNextMatchAt = null;
    updates.seriesRestarting = false;
    updates.seriesPlayerIds = null;
  }

  await roomRef.update(updates);

  if (nextCompleted >= totalMatches) {
    await requestSettlement(db, roomId);
    return { ok: true, action: "settlement_final_match" };
  }

  return { ok: true, action: "series_scheduled" };
}

export async function processRoomSteward(
  db: Database,
  roomId: string,
  nowMs: number = Date.now(),
): Promise<StewardResult> {
  const roomRef = db.ref(`rooms/${roomId}`);
  const snap = await roomRef.get();
  if (!snap.exists()) {
    return { ok: false, reason: "room_not_found" };
  }

  const room = snap.val() as Record<string, unknown>;
  if (!shouldServerStewardRoom(room, nowMs)) {
    return { ok: true, action: "skip" };
  }

  const seriesNext = room.seriesNextMatchAt;
  if (
    typeof seriesNext === "number" &&
    nowMs >= Math.round(seriesNext) &&
    isSeriesContinuationPending(room)
  ) {
    return startNextSeriesMatch(db, roomId, room);
  }

  if (!isMatchEnded(room)) {
    return { ok: true, action: "skip_not_ended" };
  }

  if (room.burstPlayerId != null) {
    await applyBurstMorrieDeductionIfNeeded(db, roomId, room);
  } else {
    await applyMatchMorrieTransferIfNeeded(db, roomId, room);
  }

  const afterMorrieSnap = await roomRef.get();
  if (!afterMorrieSnap.exists()) {
    return { ok: false, reason: "room_removed" };
  }
  const afterMorrie = afterMorrieSnap.val() as Record<string, unknown>;

  await applyMatchScoringIfNeeded(db, roomId, afterMorrie);

  const afterScoringSnap = await roomRef.get();
  if (!afterScoringSnap.exists()) {
    return { ok: false, reason: "room_removed" };
  }
  let current = afterScoringSnap.val() as Record<string, unknown>;

  if (current.postGameEndedAt == null) {
    await markPostGameStarted(db, roomId, nowMs);
    const refreshed = await roomRef.get();
    if (!refreshed.exists()) {
      return { ok: false, reason: "room_removed" };
    }
    current = refreshed.val() as Record<string, unknown>;
  }

  if (typeof current.seriesNextMatchAt === "number") {
    const completed = resolveNonNegativeInt(current.completedMatches);
    const total = resolveMatchCount(current.totalMatches);
    if (completed >= total) {
      await requestSettlement(db, roomId);
      return { ok: true, action: "settlement_waiting_close" };
    }
    return { ok: true, action: "awaiting_series_deadline" };
  }

  return advanceSeriesAfterMatch(db, roomId, current, nowMs);
}

export async function sweepRoomStewards(db: Database): Promise<number> {
  const nowMs = Date.now();
  const snap = await db.ref("rooms").get();
  if (!snap.exists()) return 0;

  const rooms = snap.val() as Record<string, unknown>;
  let processed = 0;

  for (const roomId of Object.keys(rooms)) {
    const room = rooms[roomId];
    if (!room || typeof room !== "object") continue;
    const roomData = room as Record<string, unknown>;
    if (!shouldServerStewardRoom(roomData, nowMs)) continue;
    try {
      await processRoomSteward(db, roomId, nowMs);
      processed++;
    } catch {
      // 他ルームの処理は継続
    }
  }

  return processed;
}

export function hostRematchDecisionMs(): number {
  return HOST_REMATCH_DECISION_MS;
}

export function seriesNextMatchMs(): number {
  return SERIES_NEXT_MATCH_MS;
}
