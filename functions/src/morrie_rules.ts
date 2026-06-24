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

export function humanBalanceUpdates(params: {
  participantIds: string[];
  finalPoints: Record<string, number>;
  rate: number;
  humanBalances: Record<string, number>;
}): Record<string, number> {
  const { participantIds, finalPoints, rate, humanBalances } = params;
  const raw = rawMorrieDeltas(finalPoints, rate);
  const winnerPoints: Record<string, number> = {};
  let totalCollected = 0;

  const updates: Record<string, number> = {};
  for (const id of participantIds) {
    if (!isBot(id)) updates[id] = 0;
  }

  for (const id of participantIds) {
    const points = finalPoints[id] ?? 0;
    const rawDelta = raw[id] ?? 0;
    if (points > 0) {
      winnerPoints[id] = points;
      continue;
    }
    if (rawDelta >= 0) continue;

    const requested = -rawDelta;
    const maxPay = isBot(id)
      ? BOT_FIXED_BALANCE
      : Math.max(0, humanBalances[id] ?? 0);
    const actual = Math.min(requested, maxPay);
    if (actual <= 0) continue;

    totalCollected += actual;
    if (!isBot(id)) {
      updates[id] = -actual;
    }
  }

  if (totalCollected <= 0 || Object.keys(winnerPoints).length === 0) {
    return updates;
  }

  const gains = splitIntegerByPoints(winnerPoints, totalCollected, (id) => !isBot(id));
  for (const [id, gain] of Object.entries(gains)) {
    updates[id] = (updates[id] ?? 0) + gain;
  }

  return updates;
}

function splitIntegerByPoints(
  winnerPoints: Record<string, number>,
  total: number,
  receives: (id: string) => boolean,
): Record<string, number> {
  if (total <= 0) return {};

  const totalPoints = Object.values(winnerPoints).reduce((s, p) => s + p, 0);
  if (totalPoints <= 0) return {};

  const shares: Record<string, number> = {};
  const fractionalParts: Record<string, number> = {};
  let floorSum = 0;

  for (const [id, points] of Object.entries(winnerPoints)) {
    if (points <= 0) continue;
    const exact = (total * points) / totalPoints;
    const base = Math.floor(exact);
    floorSum += base;
    if (receives(id)) shares[id] = base;
    fractionalParts[id] = exact - base;
  }

  let remainder = total - floorSum;
  if (remainder <= 0) return shares;

  const recipients = Object.entries(winnerPoints)
    .filter(([id, points]) => points > 0 && receives(id))
    .sort((a, b) => fractionalParts[b[0]] - fractionalParts[a[0]]);

  for (let i = 0; i < recipients.length && remainder > 0; i++) {
    const id = recipients[i][0];
    shares[id] = (shares[id] ?? 0) + 1;
    remainder--;
  }

  return shares;
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
