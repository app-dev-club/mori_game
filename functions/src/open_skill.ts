export interface OpenSkillRating {
  mu: number;
  sigma: number;
}

export const OpenSkillConstants = {
  defaultMu: 25,
  defaultSigma: 25 / 3,
  beta: 25 / 6,
  tau: 25 / 300,
  kappa: 0.0001,
  z: 3,
  displayRatingOffset: 1500,
};

export function defaultSkillRating(): OpenSkillRating {
  return { mu: OpenSkillConstants.defaultMu, sigma: OpenSkillConstants.defaultSigma };
}

export function ordinal(rating: OpenSkillRating): number {
  return rating.mu - OpenSkillConstants.z * rating.sigma;
}

export function displayRating(rating: OpenSkillRating): number {
  return Math.round(ordinal(rating) + OpenSkillConstants.displayRatingOffset);
}

export function fromLegacyRating(legacyRating: number): OpenSkillRating {
  const ordinalValue = legacyRating - OpenSkillConstants.displayRatingOffset;
  return {
    mu: ordinalValue + OpenSkillConstants.z * OpenSkillConstants.defaultSigma,
    sigma: OpenSkillConstants.defaultSigma,
  };
}

export function parseStoredSkill(data: Record<string, unknown>): OpenSkillRating {
  const mu = data.mu;
  const sigma = data.sigma;
  if (typeof mu === "number" && typeof sigma === "number") {
    return { mu, sigma };
  }
  const rating = data.rating;
  if (typeof rating === "number") {
    return fromLegacyRating(Math.round(rating));
  }
  return defaultSkillRating();
}

interface TeamRatingData {
  muSum: number;
  sigmaSq: number;
  team: OpenSkillRating[];
  rank: number;
}

export function rate(
  teams: OpenSkillRating[][],
  ranks: number[],
  tau = OpenSkillConstants.tau,
): OpenSkillRating[][] {
  if (teams.length < 2) return teams;
  if (ranks.length !== teams.length) {
    throw new Error("ranks length must match teams length");
  }

  const tauSquared = tau * tau;
  const processed = teams.map((team) =>
    team.map((p) => ({
      mu: p.mu,
      sigma: Math.sqrt(p.sigma * p.sigma + tauSquared),
    })),
  );

  const indexed = processed.map((team, index) => ({
    rank: ranks[index],
    team,
    index,
  }));
  indexed.sort((a, b) => a.rank - b.rank);

  const sortedTeams = indexed.map((e) => e.team);
  const sortedRanks = [...indexed.map((e) => e.rank)].sort((a, b) => a - b);
  const rated = plackettLuce(sortedTeams, sortedRanks);

  const result = processed.map((team) => team.map((p) => ({ ...p })));
  for (let i = 0; i < indexed.length; i++) {
    result[indexed[i].index] = rated[i];
  }
  return result;
}

function plackettLuce(game: OpenSkillRating[][], rankInput: number[]): OpenSkillRating[][] {
  const betaSq = OpenSkillConstants.beta * OpenSkillConstants.beta;
  const teamRatings = teamRatingsFromGame(game, rankInput);
  const c = utilC(teamRatings, betaSq);
  const sumQ = utilSumQ(teamRatings, c);
  const a = utilA(teamRatings);

  return teamRatings.map((iTeam, i) => {
    const iMuOverCe = Math.exp(iTeam.muSum / c);
    let omegaSum = 0;
    let deltaSum = 0;

    for (let q = 0; q < teamRatings.length; q++) {
      if (teamRatings[q].rank > iTeam.rank) continue;
      const quotient = iMuOverCe / sumQ[q];
      omegaSum += (i === q ? 1 - quotient : -quotient) / a[q];
      deltaSum += (quotient * (1 - quotient)) / a[q];
    }

    const gamma = Math.sqrt(iTeam.sigmaSq) / c;
    const omega = omegaSum * (iTeam.sigmaSq / c);
    const delta = deltaSum * (iTeam.sigmaSq / (c * c)) * gamma;

    return iTeam.team.map((player) => {
      const sigmaSq = player.sigma * player.sigma;
      const newMu = player.mu + (sigmaSq / iTeam.sigmaSq) * omega;
      const newSigma =
        player.sigma *
        Math.sqrt(Math.max(1 - (sigmaSq / iTeam.sigmaSq) * delta, OpenSkillConstants.kappa));
      return { mu: newMu, sigma: newSigma };
    });
  });
}

function teamRatingsFromGame(
  game: OpenSkillRating[][],
  rankInput: number[],
): TeamRatingData[] {
  const placementRanks = placementRanksFromInput(rankInput);
  return game.map((team, i) => {
    let muSum = 0;
    let sigmaSq = 0;
    for (const player of team) {
      muSum += player.mu;
      sigmaSq += player.sigma * player.sigma;
    }
    return { muSum, sigmaSq, team, rank: placementRanks[i] };
  });
}

function placementRanksFromInput(rankInput: number[]): number[] {
  const outRank = new Array<number>(rankInput.length).fill(0);
  let s = 0;
  for (let j = 0; j < rankInput.length; j++) {
    if (j > 0 && rankInput[j - 1] < rankInput[j]) s = j;
    outRank[j] = s;
  }
  return outRank;
}

function utilC(teamRatings: TeamRatingData[], betaSq: number): number {
  let sum = 0;
  for (const team of teamRatings) sum += team.sigmaSq + betaSq;
  return Math.sqrt(sum);
}

function utilSumQ(teamRatings: TeamRatingData[], c: number): number[] {
  return teamRatings.map((qTeam) => {
    let sum = 0;
    for (const iTeam of teamRatings) {
      if (iTeam.rank >= qTeam.rank) sum += Math.exp(iTeam.muSum / c);
    }
    return sum;
  });
}

function utilA(teamRatings: TeamRatingData[]): number[] {
  return teamRatings.map(
    (iTeam) => teamRatings.filter((qTeam) => qTeam.rank === iTeam.rank).length,
  );
}
