import { Database } from "firebase-admin/database";
import { moriWinnerDelta } from "./scoring_rules";
import {
  BOT_FIXED_BALANCE,
  BURST_RECOVERY_AMOUNT,
  computeBurstMorrieDeduction,
  computeMoriMorrieTransfer,
  describeBurstMorrieDeduction,
  describeMoriMorrieTransfer,
  resolvePlayerBalance,
} from "./morrie_rules";
import {
  asIntMap,
  asStringList,
  asStringMap,
  botDisplayName,
  DEFAULT_STARTING_BALANCE,
  isBot,
  resolveMorrieRate,
  resolveNonNegativeInt,
} from "./shared";
import { playerIdsFromRoom } from "./room_lifecycle";

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

async function ensureHumanBalance(db: Database, userId: string): Promise<number> {
  const ref = db.ref(`users/${userId}`);
  const snap = await ref.get();
  if (!snap.exists()) {
    await ref.update({
      morrieBalance: DEFAULT_STARTING_BALANCE,
      updatedAt: Date.now(),
    });
    return DEFAULT_STARTING_BALANCE;
  }
  const balance = snap.child("morrieBalance").val();
  if (typeof balance !== "number") {
    await ref.update({
      morrieBalance: DEFAULT_STARTING_BALANCE,
      updatedAt: Date.now(),
    });
    return DEFAULT_STARTING_BALANCE;
  }
  return Math.max(0, Math.round(balance));
}

export async function getBotRankingBalance(
  db: Database,
  botId: string,
): Promise<number> {
  const snap = await db.ref(`morrieRankings/${botId}/morrieBalance`).get();
  const balance = snap.val();
  if (typeof balance === "number" && Number.isFinite(balance)) {
    return Math.max(0, Math.round(balance));
  }
  return BOT_FIXED_BALANCE;
}

async function loadBotMorrieBalancesFromRoomOrRanking(
  db: Database,
  room: Record<string, unknown>,
  botIds: string[],
): Promise<Record<string, number>> {
  const stored = asIntMap(room.botMorrieBalances);
  const out: Record<string, number> = {};
  for (const id of botIds) {
    if (stored[id] != null) {
      out[id] = stored[id]!;
    } else {
      out[id] = await getBotRankingBalance(db, id);
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
  return isBot(playerId) ? botDisplayName(playerId) : "プレイヤー";
}

async function syncBotRankingEntry(
  db: Database,
  botId: string,
  morrieBalance: number,
  playerNames: Record<string, string>,
  now: number,
): Promise<void> {
  if (!isBot(botId)) return;
  await db.ref(`morrieRankings/${botId}`).set({
    playerName: resolveDisplayName(botId, playerNames),
    morrieBalance,
    updatedAt: now,
  });
}

function participantIdsFromRoom(room: Record<string, unknown>): string[] {
  const series = asStringList(room.seriesPlayerIds);
  if (series.length > 0) return series;
  return playerIdsFromRoom(room);
}

async function loadParticipantMorrieBalances(
  db: Database,
  room: Record<string, unknown>,
  participantIds: string[],
): Promise<Record<string, number>> {
  const balances: Record<string, number> = {};
  Object.assign(
    balances,
    await loadBotMorrieBalancesFromRoomOrRanking(
      db,
      room,
      participantIds.filter((id) => isBot(id)),
    ),
  );
  for (const id of participantIds) {
    if (isBot(id)) continue;
    balances[id] = await ensureHumanBalance(db, id);
  }
  return balances;
}

function buildFullMatchMorrieDisplay(params: {
  participantIds: string[];
  moveDeltas: Record<string, number>;
  afterMoveBalances: Record<string, number>;
  beforeBalances: Record<string, number>;
}): { deltas: Record<string, number>; balances: Record<string, number> } {
  const { participantIds, moveDeltas, afterMoveBalances, beforeBalances } = params;
  const deltas: Record<string, number> = {};
  const balances: Record<string, number> = {};
  for (const id of participantIds) {
    deltas[id] = moveDeltas[id] ?? 0;
    balances[id] =
      afterMoveBalances[id] ??
      beforeBalances[id] ??
      resolvePlayerBalance(id, beforeBalances);
  }
  return { deltas, balances };
}

/** 試合モリー適用の二重実行を防ぐ（トランザクションで先取り） */
export async function claimLastMatchMorrieApply(
  db: Database,
  roomId: string,
): Promise<boolean> {
  const ref = db.ref(`rooms/${roomId}/lastMatchMorrieApplied`);
  const result = await ref.transaction((current) => {
    if (current === true) return undefined;
    return true;
  });
  return result.committed === true && result.snapshot.val() === true;
}

async function releaseLastMatchMorrieApplyClaim(
  db: Database,
  roomId: string,
): Promise<void> {
  await db.ref(`rooms/${roomId}/lastMatchMorrieApplied`).set(null);
}

/** 試合終了時のモリー適用（在室人数に関係なく CF が実行） */
export async function applyMatchMorrieOnEnd(
  db: Database,
  roomId: string,
): Promise<boolean> {
  const roomRef = db.ref(`rooms/${roomId}`);
  const snap = await roomRef.get();
  if (!snap.exists()) return false;
  const room = snap.val() as Record<string, unknown>;

  let applied = false;
  if (room.lastMatchMorrieApplied !== true) {
    if (room.burstPlayerId != null) {
      applied = await applyBurstMorrieDeductionIfNeeded(db, roomId, room);
    } else if (room.moriPhase === "finished") {
      applied = await applyMatchMorrieTransferIfNeeded(db, roomId, room);
    }
  }

  const afterSnap = await roomRef.get();
  if (afterSnap.exists()) {
    await applyMorrieBurstRecoveryIfNeeded(
      db,
      roomId,
      afterSnap.val() as Record<string, unknown>,
    );
  }
  return applied;
}

/** もり成立時にモリーを loser → winner へ移動（二重適用防止付き） */
export async function applyMatchMorrieTransferIfNeeded(
  db: Database,
  roomId: string,
  room: Record<string, unknown>,
): Promise<boolean> {
  const morrieRate = resolveMorrieRate(room.morrieRate);
  if (morrieRate <= 0) return false;
  if (room.lastMatchMorrieApplied === true) return false;
  if (room.moriPhase !== "finished") return false;
  if (room.burstPlayerId != null) return false;

  const winnerId = room.lastMoriPlayerId?.toString();
  const loserId = room.loserPlayerId?.toString();
  const factors = asIntArray(room.moriDeclarationFactors);
  const moriGaeshiCount = resolveNonNegativeInt(room.moriGaeshiCount);
  if (!winnerId || !loserId || factors.length === 0) return false;

  const pointDelta = moriWinnerDelta(factors, moriGaeshiCount);
  if (pointDelta <= 0) return false;

  const playerNames = asStringMap(room.playerNames);
  const participantIds = participantIdsFromRoom(room);
  const playerBalances = await loadParticipantMorrieBalances(
    db,
    room,
    participantIds,
  );

  const transfer = computeMoriMorrieTransfer({
    pointDelta,
    rate: morrieRate,
    winnerId,
    loserId,
    playerBalances,
  });
  if (transfer.actualMorrie <= 0) {
    if (!(await claimLastMatchMorrieApply(db, roomId))) return false;
    return false;
  }

  if (!(await claimLastMatchMorrieApply(db, roomId))) return false;

  const now = Date.now();
  const newBalances: Record<string, number> = {};
  const botBalanceUpdates: Record<string, number> = {};
  for (const [id, delta] of Object.entries(transfer.deltas)) {
    if (isBot(id)) {
      const current = resolvePlayerBalance(id, playerBalances);
      const next = Math.max(0, current + delta);
      botBalanceUpdates[id] = next;
      newBalances[id] = next;
      await syncBotRankingEntry(db, id, next, playerNames, now);
      continue;
    }

    const current = playerBalances[id] ?? (await ensureHumanBalance(db, id));
    const next = Math.max(0, current + delta);
    newBalances[id] = next;
    const name = resolveDisplayName(id, playerNames);
    await db.ref(`users/${id}`).update({
      morrieBalance: next,
      updatedAt: now,
    });
    await db.ref(`morrieRankings/${id}`).set({
      playerName: name,
      morrieBalance: next,
      updatedAt: now,
    });
    await db.ref(`rooms/${roomId}/morrieClaimed/${id}`).set(true);
    await db.ref(`userMorriePending/${id}/${roomId}`).remove();
  }

  const seriesDeltas = asIntMap(room.playerMorrieSeriesDeltas);
  for (const [id, delta] of Object.entries(transfer.deltas)) {
    seriesDeltas[id] = (seriesDeltas[id] ?? 0) + delta;
  }

  const summary = describeMoriMorrieTransfer({
    winnerName: resolveDisplayName(winnerId, playerNames),
    loserName: resolveDisplayName(loserId, playerNames),
    loserId,
    pointDelta,
    rate: morrieRate,
    transfer,
  });

  const display = buildFullMatchMorrieDisplay({
    participantIds,
    moveDeltas: transfer.deltas,
    afterMoveBalances: newBalances,
    beforeBalances: playerBalances,
  });

  const updates: Record<string, unknown> = {
    lastMatchMorrieDeltas: display.deltas,
    lastMatchMorrieSummary: summary,
    playerMorrieSeriesDeltas: seriesDeltas,
    lastMatchMorrieBalances: display.balances,
  };
  if (transfer.morrieBurst) {
    updates.morrieBurstPlayerId = loserId;
  }
  for (const [id, balance] of Object.entries(botBalanceUpdates)) {
    updates[`botMorrieBalances/${id}`] = balance;
  }

  try {
    await db.ref(`rooms/${roomId}`).update(updates);
    return true;
  } catch (error) {
    await releaseLastMatchMorrieApplyClaim(db, roomId);
    throw error;
  }
}

/** バースト時にモリーを減算（2点 × レート、二重適用防止付き） */
export async function applyBurstMorrieDeductionIfNeeded(
  db: Database,
  roomId: string,
  room: Record<string, unknown>,
): Promise<boolean> {
  const morrieRate = resolveMorrieRate(room.morrieRate);
  if (morrieRate <= 0) return false;
  if (room.lastMatchMorrieApplied === true) return false;

  const burstPlayerId = room.burstPlayerId?.toString();
  if (!burstPlayerId) return false;

  const playerNames = asStringMap(room.playerNames);
  const participantIds = participantIdsFromRoom(room);
  const playerBalances = await loadParticipantMorrieBalances(
    db,
    room,
    participantIds,
  );

  const deduction = computeBurstMorrieDeduction({
    rate: morrieRate,
    burstPlayerId,
    playerBalances,
  });
  if (deduction.actualMorrie <= 0 && !deduction.morrieBurst) {
    if (!(await claimLastMatchMorrieApply(db, roomId))) return false;
    return false;
  }

  if (!(await claimLastMatchMorrieApply(db, roomId))) return false;

  const now = Date.now();
  const newBalances: Record<string, number> = {};
  const botBalanceUpdates: Record<string, number> = {};
  for (const [id, delta] of Object.entries(deduction.deltas)) {
    if (isBot(id)) {
      const current = resolvePlayerBalance(id, playerBalances);
      const next = Math.max(0, current + delta);
      botBalanceUpdates[id] = next;
      newBalances[id] = next;
      await syncBotRankingEntry(db, id, next, playerNames, now);
      continue;
    }

    const current = playerBalances[id] ?? (await ensureHumanBalance(db, id));
    const next = Math.max(0, current + delta);
    newBalances[id] = next;
    const name = resolveDisplayName(id, playerNames);
    await db.ref(`users/${id}`).update({
      morrieBalance: next,
      updatedAt: now,
    });
    await db.ref(`morrieRankings/${id}`).set({
      playerName: name,
      morrieBalance: next,
      updatedAt: now,
    });
    await db.ref(`rooms/${roomId}/morrieClaimed/${id}`).set(true);
    await db.ref(`userMorriePending/${id}/${roomId}`).remove();
  }

  const seriesDeltas = asIntMap(room.playerMorrieSeriesDeltas);
  for (const [id, delta] of Object.entries(deduction.deltas)) {
    seriesDeltas[id] = (seriesDeltas[id] ?? 0) + delta;
  }

  const summary = describeBurstMorrieDeduction({
    burstPlayerName: resolveDisplayName(burstPlayerId, playerNames),
    burstPlayerId,
    rate: morrieRate,
    deduction,
  });

  const display = buildFullMatchMorrieDisplay({
    participantIds,
    moveDeltas: deduction.deltas,
    afterMoveBalances: newBalances,
    beforeBalances: playerBalances,
  });

  const updates: Record<string, unknown> = {
    lastMatchMorrieDeltas: display.deltas,
    lastMatchMorrieSummary: summary,
    playerMorrieSeriesDeltas: seriesDeltas,
    lastMatchMorrieBalances: display.balances,
  };
  if (deduction.morrieBurst) {
    updates.morrieBurstPlayerId = burstPlayerId;
  }
  for (const [id, balance] of Object.entries(botBalanceUpdates)) {
    updates[`botMorrieBalances/${id}`] = balance;
  }

  try {
    await db.ref(`rooms/${roomId}`).update(updates);
    return true;
  } catch (error) {
    await releaseLastMatchMorrieApplyClaim(db, roomId);
    throw error;
  }
}

/** 飛び発生ボットへ試合終了後に回復モリーを付与（人間には付与しない） */
export async function applyMorrieBurstRecoveryIfNeeded(
  db: Database,
  roomId: string,
  room: Record<string, unknown>,
): Promise<boolean> {
  const burstId = room.morrieBurstPlayerId?.toString();
  if (!burstId) return false;
  if (room.morrieBurstRecoveryApplied === true) return false;

  if (!isBot(burstId)) {
    await db.ref(`rooms/${roomId}`).update({ morrieBurstRecoveryApplied: true });
    return false;
  }

  const playerNames = asStringMap(room.playerNames);
  const stored = asIntMap(room.botMorrieBalances);
  const current =
    stored[burstId] ?? (await getBotRankingBalance(db, burstId));
  if (current > 0) {
    await db.ref(`rooms/${roomId}`).update({ morrieBurstRecoveryApplied: true });
    return false;
  }

  const amount = BURST_RECOVERY_AMOUNT;
  const now = Date.now();
  const next = current + amount;
  const updates: Record<string, unknown> = {
    morrieBurstRecoveryApplied: true,
    [`botMorrieBalances/${burstId}`]: next,
  };

  const lastBalances = asIntMap(room.lastMatchMorrieBalances);
  lastBalances[burstId] = next;
  updates.lastMatchMorrieBalances = lastBalances;

  await syncBotRankingEntry(db, burstId, next, playerNames, now);

  const summary = room.lastMatchMorrieSummary?.toString() ?? "";
  if (summary) {
    const label = resolveDisplayName(burstId, playerNames);
    updates.lastMatchMorrieSummary =
      `${summary}\n（${label} に回復${amount}モリー付与）`;
  }

  await db.ref(`rooms/${roomId}`).update(updates);
  return true;
}
