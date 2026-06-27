import { Database } from "firebase-admin/database";
import { moriWinnerDelta } from "./scoring_rules";
import {
  BOT_FIXED_BALANCE,
  botBalancesAfterSettlement,
  computeMoriMorrieTransfer,
  describeMoriMorrieTransfer,
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

function resolveDisplayName(
  playerId: string,
  playerNames: Record<string, string>,
): string {
  const name = playerNames[playerId]?.trim();
  if (name) return name;
  return isBot(playerId) ? botDisplayName(playerId) : "プレイヤー";
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
  const humanBalances: Record<string, number> = {};
  for (const id of [winnerId, loserId]) {
    if (isBot(id)) continue;
    humanBalances[id] = await ensureHumanBalance(db, id);
  }

  const transfer = computeMoriMorrieTransfer({
    pointDelta,
    rate: morrieRate,
    winnerId,
    loserId,
    humanBalances,
  });
  if (transfer.actualMorrie <= 0) {
    await db.ref(`rooms/${roomId}`).update({ lastMatchMorrieApplied: true });
    return false;
  }

  const now = Date.now();
  const newBalances: Record<string, number> = {};
  for (const [id, delta] of Object.entries(transfer.deltas)) {
    const current = humanBalances[id] ?? (await ensureHumanBalance(db, id));
    const next = current + delta;
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
    pointDelta,
    rate: morrieRate,
    transfer,
  });

  const balanceSnapshot: Record<string, number> = {};
  for (const id of Object.keys(transfer.deltas)) {
    balanceSnapshot[id] = newBalances[id] ?? humanBalances[id] ?? 0;
  }
  if (isBot(loserId)) {
    balanceSnapshot[loserId] = BOT_FIXED_BALANCE;
  }

  const updates: Record<string, unknown> = {
    lastMatchMorrieApplied: true,
    lastMatchMorrieDeltas: transfer.deltas,
    lastMatchMorrieSummary: summary,
    playerMorrieSeriesDeltas: seriesDeltas,
    lastMatchMorrieBalances: balanceSnapshot,
  };
  if (transfer.morrieBurst) {
    updates.morrieBurstPlayerId = loserId;
  }

  const roster = asStringList(room.players);
  const botBalances = botBalancesAfterSettlement(
    roster.length > 0 ? roster : [winnerId, loserId],
  );
  if (Object.keys(botBalances).length > 0) {
    updates.botMorrieBalances = botBalances;
  }

  await db.ref(`rooms/${roomId}`).update(updates);
  return true;
}
