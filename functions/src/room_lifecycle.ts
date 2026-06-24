import { isBot, resolveMatchCount, resolveNonNegativeInt } from "./shared";

export const SERIES_NEXT_MATCH_MS = 5 * 1000;
export const HOST_REMATCH_DECISION_MS = 60 * 1000;
export const SERIES_CONTINUE_GRACE_MS = 30 * 1000;
export const MIN_PLAYERS = 2;

export function playerIdsFromRoom(room: Record<string, unknown>): string[] {
  const players = room.players;
  if (!Array.isArray(players)) return [];
  return players.map((e) => String(e));
}

export function afkPlayerIdsFromRoom(room: Record<string, unknown>): Set<string> {
  const afk = room.afkPlayerIds;
  if (!afk || typeof afk !== "object") return new Set();
  const out = new Set<string>();
  for (const [key, value] of Object.entries(afk as Record<string, unknown>)) {
    if (value === true) out.add(key);
  }
  return out;
}

export function hasPresentHumanPlayers(room: Record<string, unknown>): boolean {
  const presence = room.presence;
  if (!presence || typeof presence !== "object") return false;
  const presentIds = new Set(
    Object.keys(presence as Record<string, unknown>).map((e) => String(e)),
  );
  if (presentIds.size === 0) return false;
  const afkIds = afkPlayerIdsFromRoom(room);
  for (const id of playerIdsFromRoom(room)) {
    if (isBot(id)) continue;
    if (presentIds.has(id) && !afkIds.has(id)) return true;
  }
  return false;
}

export function isMatchEnded(room: Record<string, unknown>): boolean {
  if (room.burstPlayerId != null) return true;
  return room.moriPhase === "finished";
}

export function isSeriesContinuationPending(
  room: Record<string, unknown>,
): boolean {
  if (room.seriesRestarting === true) return true;
  if (room.seriesNextMatchAt != null) return true;
  if (room.postGameActive !== true) return false;
  const totalMatches = resolveMatchCount(room.totalMatches);
  const completedMatches = resolveNonNegativeInt(room.completedMatches);
  return totalMatches > 1 && completedMatches < totalMatches;
}

export function needsPostGameSteward(room: Record<string, unknown>): boolean {
  if (room.gameStarted !== true) return false;
  if (!isMatchEnded(room)) return false;
  if (hasPresentHumanPlayers(room)) return false;
  if (room.seriesRestarting === true) return false;
  if (isSeriesContinuationPending(room)) return false;
  return true;
}

export function isGameFullyConcluded(
  room: Record<string, unknown>,
  nowMs: number,
): boolean {
  if (room.gameStarted !== true) return false;
  if (!isMatchEnded(room)) return false;
  if (room.seriesRestarting === true) return false;
  if (room.awaitingGuestStayResponses === true) return false;
  if (room.rematchHostRequested === true) return false;

  const totalMatches = resolveMatchCount(room.totalMatches);
  const completedMatches = resolveNonNegativeInt(room.completedMatches);

  if (completedMatches < totalMatches) {
    const seriesNext = room.seriesNextMatchAt;
    if (typeof seriesNext === "number") {
      return nowMs >= Math.round(seriesNext) + SERIES_CONTINUE_GRACE_MS;
    }
    return false;
  }

  const postGameEndedAt = room.postGameEndedAt;
  if (typeof postGameEndedAt === "number") {
    return nowMs >= Math.round(postGameEndedAt) + HOST_REMATCH_DECISION_MS;
  }

  return true;
}

export function isSettlementComplete(room: Record<string, unknown>): boolean {
  if (room.seriesRatingApplied !== true) return false;
  const morrieRate =
    typeof room.morrieRate === "number" && Number.isFinite(room.morrieRate)
      ? Math.round(room.morrieRate)
      : 1;
  if (morrieRate <= 0) return true;
  return room.seriesMorrieSettled === true;
}

export function shouldServerStewardRoom(
  room: Record<string, unknown>,
  nowMs: number,
): boolean {
  if (room.gameStarted !== true) return false;
  if (hasPresentHumanPlayers(room)) return false;
  if (room.seriesRestarting === true) return false;

  if (needsPostGameSteward(room)) return true;

  const seriesNext = room.seriesNextMatchAt;
  if (
    typeof seriesNext === "number" &&
    nowMs >= Math.round(seriesNext) &&
    isSeriesContinuationPending(room)
  ) {
    return true;
  }

  if (isGameFullyConcluded(room, nowMs) && isSettlementComplete(room)) {
    return true;
  }

  return false;
}
