import { Database } from "firebase-admin/database";
import { logger } from "firebase-functions";
import { DEFAULT_STARTING_BALANCE, isBot } from "./shared";

export const AD_REWARD_AMOUNT = 5;
export async function readHumanMorrieBalance(
  db: Database,
  userId: string,
): Promise<number | null> {
  const snap = await db.ref(`users/${userId}/morrieBalance`).get();
  if (!snap.exists()) return null;
  const balance = snap.val();
  if (typeof balance !== "number" || !Number.isFinite(balance)) {
    logger.warn("readHumanMorrieBalance invalid value", { userId, balance });
    return null;
  }
  return Math.max(0, Math.round(balance));
}

export async function syncHumanMorrieRanking(
  db: Database,
  userId: string,
  morrieBalance: number,
  playerName?: string,
): Promise<void> {
  if (isBot(userId)) return;
  let name = playerName?.trim();
  if (!name) {
    const nameSnap = await db.ref(`users/${userId}/playerName`).get();
    const raw = nameSnap.val();
    if (typeof raw === "string" && raw.trim().length > 0) {
      name = raw.trim();
    }
  }
  await db.ref(`morrieRankings/${userId}`).set({
    playerName: name ?? "プレイヤー",
    morrieBalance,
    updatedAt: Date.now(),
  });
}

/** 初回のみ残高 10 を付与（異常値の上書きはしない） */
export async function ensureMorrieAccount(
  db: Database,
  userId: string,
): Promise<{ balance: number; created: boolean }> {
  const ref = db.ref(`users/${userId}`);
  const snap = await ref.get();
  const now = Date.now();

  if (!snap.exists()) {
    await ref.set({
      morrieBalance: DEFAULT_STARTING_BALANCE,
      updatedAt: now,
    });
    await syncHumanMorrieRanking(db, userId, DEFAULT_STARTING_BALANCE);
    return { balance: DEFAULT_STARTING_BALANCE, created: true };
  }

  const existing = await readHumanMorrieBalance(db, userId);
  if (existing != null) {
    return { balance: existing, created: false };
  }

  if (!snap.child("morrieBalance").exists()) {
    await ref.update({
      morrieBalance: DEFAULT_STARTING_BALANCE,
      updatedAt: now,
    });
    await syncHumanMorrieRanking(db, userId, DEFAULT_STARTING_BALANCE);
    return { balance: DEFAULT_STARTING_BALANCE, created: true };
  }

  logger.warn("ensureMorrieAccount skipped invalid balance", { userId });
  return { balance: 0, created: false };
}

export async function grantAdRewardMorrie(
  db: Database,
  userId: string,
): Promise<number> {
  const current = await readHumanMorrieBalance(db, userId);
  if (current == null) {
    throw new Error("morrie_balance_unavailable");
  }
  const next = current + AD_REWARD_AMOUNT;
  const now = Date.now();
  await db.ref(`users/${userId}`).update({
    morrieBalance: next,
    updatedAt: now,
  });
  await syncHumanMorrieRanking(db, userId, next);
  return next;
}

export async function refreshMorrieRankingForUser(
  db: Database,
  userId: string,
): Promise<void> {
  const balance = await readHumanMorrieBalance(db, userId);
  if (balance == null) return;
  await syncHumanMorrieRanking(db, userId, balance);
}

/** 試合精算用: 読めない場合は 0（10 へ上書きしない） */
export async function loadHumanMorrieBalanceForTransfer(
  db: Database,
  userId: string,
): Promise<number> {
  const balance = await readHumanMorrieBalance(db, userId);
  return balance ?? 0;
}
