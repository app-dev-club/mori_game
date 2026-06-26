import { isBot } from "./shared";

export const BOT_FIXED_BALANCE = 5;

export function morrieDeltaForPoints(points: number, rate: number): number {
  return points * rate;
}

export function rawMorrieDeltas(
  finalPoints: Record<string, number>,
  rate: number,
): Record<string, number> {
  const out: Record<string, number> = {};
  for (const [id, points] of Object.entries(finalPoints)) {
    out[id] = morrieDeltaForPoints(points, rate);
  }
  return out;
}

/** 人間プレイヤーへの残高変動（累計得点 × レート） */
export function humanBalanceUpdates(params: {
  participantIds: string[];
  finalPoints: Record<string, number>;
  rate: number;
}): Record<string, number> {
  const { participantIds, finalPoints, rate } = params;
  const raw = rawMorrieDeltas(finalPoints, rate);
  const updates: Record<string, number> = {};
  for (const id of participantIds) {
    if (!isBot(id)) {
      updates[id] = raw[id] ?? 0;
    }
  }
  return updates;
}

export function botBalancesAfterSettlement(
  participantIds: string[],
): Record<string, number> {
  const out: Record<string, number> = {};
  for (const id of participantIds) {
    if (isBot(id)) out[id] = BOT_FIXED_BALANCE;
  }
  return out;
}
