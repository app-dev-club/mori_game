import { isBot } from "./shared";

export const BOT_FIXED_BALANCE = 5;

export interface MoriMorrieTransfer {
  requestedMorrie: number;
  actualMorrie: number;
  morrieBurst: boolean;
  deltas: Record<string, number>;
}

export function moriMorrieAmount(pointDelta: number, rate: number): number {
  if (pointDelta <= 0 || rate <= 0) return 0;
  return pointDelta * rate;
}

export function computeMoriMorrieTransfer(params: {
  pointDelta: number;
  rate: number;
  winnerId: string;
  loserId: string;
  humanBalances: Record<string, number>;
}): MoriMorrieTransfer {
  const { pointDelta, rate, winnerId, loserId, humanBalances } = params;
  const requested = moriMorrieAmount(pointDelta, rate);
  if (requested <= 0) {
    return {
      requestedMorrie: 0,
      actualMorrie: 0,
      morrieBurst: false,
      deltas: {},
    };
  }

  const loserAvailable = isBot(loserId)
    ? BOT_FIXED_BALANCE
    : Math.max(0, humanBalances[loserId] ?? 0);
  const actual = Math.min(requested, loserAvailable);
  const morrieBurst = !isBot(loserId) && requested > loserAvailable;

  const deltas: Record<string, number> = {};
  if (!isBot(loserId)) deltas[loserId] = -actual;
  if (!isBot(winnerId)) deltas[winnerId] = (deltas[winnerId] ?? 0) + actual;

  return {
    requestedMorrie: requested,
    actualMorrie: actual,
    morrieBurst,
    deltas,
  };
}

export function describeMoriMorrieTransfer(params: {
  winnerName: string;
  loserName: string;
  pointDelta: number;
  rate: number;
  transfer: MoriMorrieTransfer;
}): string {
  const { winnerName, loserName, pointDelta, rate, transfer } = params;
  if (transfer.actualMorrie <= 0) return "";
  const lines = [
    `モリー: ${loserName} → ${winnerName} ${transfer.actualMorrie}（${pointDelta}点×${rate}）`,
  ];
  if (transfer.morrieBurst) {
    lines.push(`${loserName} は所持モリー不足のため全財産を失い、飛びとなりました`);
  }
  return lines.join("\n");
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
