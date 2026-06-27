import { isBot } from "./shared";
import { burstPenalty } from "./scoring_rules";

export const BOT_FIXED_BALANCE = 5;
export const DEFAULT_STARTING_BALANCE = 10;
export const BURST_RECOVERY_AMOUNT = 5;

export interface MoriMorrieTransfer {
  requestedMorrie: number;
  actualMorrie: number;
  morrieBurst: boolean;
  deltas: Record<string, number>;
}

export interface BurstMorrieDeduction {
  requestedMorrie: number;
  actualMorrie: number;
  morrieBurst: boolean;
  deltas: Record<string, number>;
}

export function resolvePlayerBalance(
  playerId: string,
  playerBalances: Record<string, number>,
): number {
  if (isBot(playerId)) {
    return Math.max(0, playerBalances[playerId] ?? BOT_FIXED_BALANCE);
  }
  return Math.max(0, playerBalances[playerId] ?? DEFAULT_STARTING_BALANCE);
}

export function moriMorrieAmount(pointDelta: number, rate: number): number {
  if (pointDelta <= 0 || rate <= 0) return 0;
  return pointDelta * rate;
}

export function burstMorrieAmount(rate: number): number {
  if (rate <= 0) return 0;
  return burstPenalty() * rate;
}

export function computeBurstMorrieDeduction(params: {
  rate: number;
  burstPlayerId: string;
  playerBalances: Record<string, number>;
}): BurstMorrieDeduction {
  const { rate, burstPlayerId, playerBalances } = params;
  const requested = burstMorrieAmount(rate);
  if (requested <= 0) {
    return { requestedMorrie: 0, actualMorrie: 0, morrieBurst: false, deltas: {} };
  }

  const available = resolvePlayerBalance(burstPlayerId, playerBalances);
  const actual = Math.min(requested, available);
  const morrieBurst = requested > available;

  return {
    requestedMorrie: requested,
    actualMorrie: actual,
    morrieBurst,
    deltas: { [burstPlayerId]: -actual },
  };
}

export function describeBurstMorrieDeduction(params: {
  burstPlayerName: string;
  burstPlayerId: string;
  rate: number;
  deduction: BurstMorrieDeduction;
}): string {
  const { burstPlayerName, burstPlayerId, rate, deduction } = params;
  if (deduction.actualMorrie <= 0 && !deduction.morrieBurst) return "";
  const lines: string[] = [];
  if (deduction.actualMorrie > 0) {
    lines.push(
      `モリー: ${burstPlayerName} -${deduction.actualMorrie}（${burstPenalty()}点×${rate}）`,
    );
  }
  if (deduction.morrieBurst) {
    lines.push(`${burstPlayerName} は所持モリー不足のため全財産を失い、飛びとなりました`);
    if (isBot(burstPlayerId)) {
      lines.push(`（試合終了後に${BURST_RECOVERY_AMOUNT}モリーが付与されます）`);
    }
  }
  return lines.join("\n");
}

export function computeMoriMorrieTransfer(params: {
  pointDelta: number;
  rate: number;
  winnerId: string;
  loserId: string;
  playerBalances: Record<string, number>;
}): MoriMorrieTransfer {
  const { pointDelta, rate, winnerId, loserId, playerBalances } = params;
  const requested = moriMorrieAmount(pointDelta, rate);
  if (requested <= 0) {
    return {
      requestedMorrie: 0,
      actualMorrie: 0,
      morrieBurst: false,
      deltas: {},
    };
  }

  const loserAvailable = resolvePlayerBalance(loserId, playerBalances);
  const actual = Math.min(requested, loserAvailable);
  const morrieBurst = requested > loserAvailable;

  return {
    requestedMorrie: requested,
    actualMorrie: actual,
    morrieBurst,
    deltas: {
      [loserId]: -actual,
      [winnerId]: actual,
    },
  };
}

export function describeMoriMorrieTransfer(params: {
  winnerName: string;
  loserName: string;
  loserId: string;
  pointDelta: number;
  rate: number;
  transfer: MoriMorrieTransfer;
}): string {
  const { winnerName, loserName, loserId, pointDelta, rate, transfer } = params;
  if (transfer.actualMorrie <= 0) return "";
  const lines = [
    `モリー: ${loserName} → ${winnerName} ${transfer.actualMorrie}（${pointDelta}点×${rate}）`,
  ];
  if (transfer.morrieBurst) {
    lines.push(`${loserName} は所持モリー不足のため全財産を失い、飛びとなりました`);
    if (isBot(loserId)) {
      lines.push(`（試合終了後に${BURST_RECOVERY_AMOUNT}モリーが付与されます）`);
    }
  }
  return lines.join("\n");
}

export function initialBotBalances(botIds: string[]): Record<string, number> {
  const out: Record<string, number> = {};
  for (const id of botIds) {
    out[id] = BOT_FIXED_BALANCE;
  }
  return out;
}
