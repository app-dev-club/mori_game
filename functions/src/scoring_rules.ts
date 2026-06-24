export function burstPenalty(): number {
  return 2;
}

export function moriGaeshiMultiplier(moriGaeshiCount: number): number {
  if (moriGaeshiCount <= 0) return 1;
  return 1 << moriGaeshiCount;
}

export function moriWinnerDelta(
  declarationFactors: number[],
  moriGaeshiCount: number,
): number {
  if (declarationFactors.length === 0) return 0;
  let product = 1;
  for (const factor of declarationFactors) {
    product *= factor;
  }
  return product * moriGaeshiMultiplier(moriGaeshiCount);
}

function formatSignedPoints(points: number): string {
  return points >= 0 ? `+${points}` : `${points}`;
}

function formatFactorFormula(
  declarationFactors: number[],
  moriGaeshiCount: number,
): string {
  if (declarationFactors.length === 0) return "0";
  const parts = declarationFactors.map((f) => `${f}`);
  const gaeshiMult = moriGaeshiMultiplier(moriGaeshiCount);
  if (gaeshiMult > 1) parts.push(`${gaeshiMult}`);
  return parts.join("×");
}

export function describeBurstScoring(burstPlayerName: string): string {
  return `${burstPlayerName} ${formatSignedPoints(-burstPenalty())}点（バースト）`;
}

export function describeMoriScoring(params: {
  winnerName: string;
  loserName: string;
  declarationFactors: number[];
  moriGaeshiCount: number;
  delta: number;
}): string {
  const { winnerName, loserName, declarationFactors, moriGaeshiCount, delta } =
    params;
  const formula = formatFactorFormula(declarationFactors, moriGaeshiCount);
  return (
    `${winnerName} ${formatSignedPoints(delta)}点 / ` +
    `${loserName} ${formatSignedPoints(-delta)}点\n` +
    `（${formula} = ${delta}点）`
  );
}
