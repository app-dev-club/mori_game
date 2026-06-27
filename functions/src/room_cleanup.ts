import { Database } from "firebase-admin/database";
import {
  isGameFullyConcluded,
  isMatchEnded,
  isSeriesContinuationPending,
  isSettlementComplete,
  playerIdsFromRoom,
} from "./room_lifecycle";

export const NEW_ROOM_GRACE_MS = 60 * 1000;
export const MAX_ROOM_AGE_MS = 24 * 60 * 60 * 1000;
export const INACTIVE_LOBBY_AGE_MS = 15 * 60 * 1000;

export function hasActivePlayers(room: Record<string, unknown>): boolean {
  const presence = room.presence;
  if (!presence || typeof presence !== "object") return false;
  return Object.keys(presence as Record<string, unknown>).length > 0;
}

export function hasSpectators(room: Record<string, unknown>): boolean {
  const spectators = room.spectators;
  if (!spectators || typeof spectators !== "object") return false;
  return Object.keys(spectators as Record<string, unknown>).length > 0;
}

function isActiveMatch(room: Record<string, unknown>): boolean {
  if (room.gameStarted !== true) return false;
  if (isSeriesContinuationPending(room)) return true;
  return !isMatchEnded(room);
}

function isProtectedRoomState(room: Record<string, unknown>): boolean {
  if (room.postGameActive === true) return true;
  if (room.awaitingGuestStayResponses === true) return true;
  if (room.seriesRestarting === true) return true;
  if (room.seriesNextMatchAt != null) return true;
  return false;
}

function resolveCreatedAtMs(room: Record<string, unknown>, nowMs: number): number {
  const createdAtRaw = room.createdAt;
  if (typeof createdAtRaw === "number" && Number.isFinite(createdAtRaw)) {
    return Math.round(createdAtRaw);
  }
  return nowMs;
}

function lastActivityMs(room: Record<string, unknown>): number | null {
  let latest: number | null = null;

  const consider = (value: unknown) => {
    if (typeof value === "number" && Number.isFinite(value)) {
      const ms = Math.round(value);
      if (latest == null || ms > latest) latest = ms;
    }
  };

  consider(room.createdAt);
  consider(room.deckResetAt);
  consider(room.moriDeclaredAt);
  consider(room.postGameEndedAt);
  consider(room.rematchStartedAt);
  consider(room.seriesNextMatchAt);

  const presence = room.presence;
  if (presence && typeof presence === "object") {
    for (const value of Object.values(presence as Record<string, unknown>)) {
      consider(value);
    }
  }

  return latest;
}

function isInactiveRoom(room: Record<string, unknown>, nowMs: number): boolean {
  const lastActivity = lastActivityMs(room);
  if (lastActivity == null) return false;
  return nowMs - lastActivity >= INACTIVE_LOBBY_AGE_MS;
}

export function hostIdFromRoom(room: Record<string, unknown>): string | null {
  const host = room.host?.toString();
  return host && host.length > 0 ? host : null;
}

export function isHostPresent(room: Record<string, unknown>): boolean {
  const hostId = hostIdFromRoom(room);
  if (!hostId) return false;
  const presence = room.presence;
  if (!presence || typeof presence !== "object") return false;
  return Object.prototype.hasOwnProperty.call(presence, hostId);
}

/** 全ゲーム終了・精算完了後にホストが離脱した */
export function shouldDeleteAfterHostLeft(
  room: Record<string, unknown>,
  nowMs: number,
): boolean {
  if (room.gameStarted !== true) return false;
  if (!isGameFullyConcluded(room, nowMs)) return false;
  if (!isSettlementComplete(room)) return false;
  const hostId = hostIdFromRoom(room);
  if (!hostId) return false;
  return !isHostPresent(room);
}

/** 接続者・観戦者がいないルーム */
export function isRoomEmpty(room: Record<string, unknown>): boolean {
  return !hasActivePlayers(room) && !hasSpectators(room);
}

/** 放置・空ルーム・期限切れルームの削除判定 */
export function shouldDeleteAbandonedRoom(
  room: Record<string, unknown>,
  nowMs: number,
): boolean {
  const createdAt = resolveCreatedAtMs(room, nowMs);
  if (nowMs - createdAt > MAX_ROOM_AGE_MS) return true;

  const players = playerIdsFromRoom(room);
  if (
    players.length > 0 &&
    room.gameStarted !== true &&
    nowMs - createdAt < NEW_ROOM_GRACE_MS
  ) {
    return false;
  }

  if (
    isGameFullyConcluded(room, nowMs) &&
    isSettlementComplete(room) &&
    isRoomEmpty(room)
  ) {
    return true;
  }

  const activePlayers = hasActivePlayers(room);
  const hasSpectatorsInRoom = hasSpectators(room);

  if (!activePlayers && !hasSpectatorsInRoom) {
    if (isActiveMatch(room) && players.length > 0) {
      return false;
    }
    return true;
  }

  if (!activePlayers && hasSpectatorsInRoom) {
    if (
      room.gameStarted === true &&
      !isGameFullyConcluded(room, nowMs)
    ) {
      return false;
    }
    return room.gameStarted !== true;
  }

  if (
    room.gameStarted !== true &&
    !isProtectedRoomState(room) &&
    isInactiveRoom(room, nowMs)
  ) {
    return true;
  }

  return false;
}

export function shouldDeleteRoom(
  room: Record<string, unknown>,
  nowMs: number,
): { delete: boolean; reason?: string } {
  if (shouldDeleteAfterHostLeft(room, nowMs)) {
    return { delete: true, reason: "host_left_after_conclusion" };
  }

  if (shouldDeleteAbandonedRoom(room, nowMs)) {
    if (nowMs - resolveCreatedAtMs(room, nowMs) > MAX_ROOM_AGE_MS) {
      return { delete: true, reason: "max_age" };
    }
    if (isRoomEmpty(room)) {
      return { delete: true, reason: "empty_room" };
    }
    if (
      room.gameStarted !== true &&
      !isProtectedRoomState(room) &&
      isInactiveRoom(room, nowMs)
    ) {
      return { delete: true, reason: "inactive_lobby" };
    }
    if (!hasActivePlayers(room) && hasSpectators(room)) {
      return { delete: true, reason: "spectators_only" };
    }
  }

  return { delete: false };
}

export async function tryDeleteRoomIfNeeded(
  db: Database,
  roomId: string,
  nowMs: number = Date.now(),
): Promise<{ deleted: boolean; reason?: string }> {
  const roomRef = db.ref(`rooms/${roomId}`);
  const snap = await roomRef.get();
  if (!snap.exists()) return { deleted: false };

  const room = snap.val() as Record<string, unknown>;
  const decision = shouldDeleteRoom(room, nowMs);
  if (!decision.delete) return { deleted: false };

  await roomRef.remove();
  return { deleted: true, reason: decision.reason };
}

export async function sweepRoomCleanup(db: Database): Promise<number> {
  const snap = await db.ref("rooms").get();
  if (!snap.exists()) return 0;

  const nowMs = Date.now();
  const rooms = snap.val() as Record<string, unknown>;
  let deleted = 0;

  for (const roomId of Object.keys(rooms)) {
    const room = rooms[roomId];
    if (!room || typeof room !== "object") continue;
    try {
      const result = await tryDeleteRoomIfNeeded(db, roomId, nowMs);
      if (result.deleted) deleted++;
    } catch {
      // 他ルームの処理は継続
    }
  }

  return deleted;
}
