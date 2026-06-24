import {
  displayRating,
  defaultSkillRating,
  OpenSkillRating,
  parseStoredSkill,
  rate,
} from "./open_skill";

export interface RankedPlayer {
  id: string;
  points: number;
  rank: number;
}

export function rankByPoints(
  playerIds: string[],
  finalPoints: Record<string, number>,
): RankedPlayer[] {
  const entries = playerIds.map((id) => ({
    id,
    points: finalPoints[id] ?? 0,
  }));
  entries.sort((a, b) => b.points - a.points);

  const ranked: RankedPlayer[] = [];
  for (let i = 0; i < entries.length; i++) {
    let rank = i + 1;
    if (i > 0 && entries[i].points === entries[i - 1].points) {
      rank = ranked[i - 1].rank;
    }
    ranked.push({ id: entries[i].id, points: entries[i].points, rank });
  }
  return ranked;
}

export function computeSkillUpdates(params: {
  oldRatings: Record<string, OpenSkillRating>;
  playerIds: string[];
  finalPoints: Record<string, number>;
}): Record<
  string,
  { oldRating: OpenSkillRating; newRating: OpenSkillRating; ratingDelta: number }
> {
  const { oldRatings, playerIds, finalPoints } = params;
  if (playerIds.length < 2) return {};

  const ranked = rankByPoints(playerIds, finalPoints);
  const rankById: Record<string, number> = {};
  for (const entry of ranked) rankById[entry.id] = entry.rank;

  const teams = playerIds.map((id) => [oldRatings[id] ?? defaultSkillRating()]);
  const ranks = playerIds.map((id) => rankById[id]);
  const updatedTeams = rate(teams, ranks);

  const updates: Record<
    string,
    { oldRating: OpenSkillRating; newRating: OpenSkillRating; ratingDelta: number }
  > = {};

  for (let i = 0; i < playerIds.length; i++) {
    const id = playerIds[i];
    const oldRating = oldRatings[id] ?? defaultSkillRating();
    const newRating = updatedTeams[i][0];
    const ratingDelta = displayRating(newRating) - displayRating(oldRating);
    updates[id] = { oldRating, newRating, ratingDelta };
  }

  return updates;
}

export function buildSeriesSummary(params: {
  ranked: RankedPlayer[];
  oldRatings: Record<string, OpenSkillRating>;
  updates: Record<
    string,
    { oldRating: OpenSkillRating; newRating: OpenSkillRating; ratingDelta: number }
  >;
  displayNames: Record<string, string>;
}): string {
  const { ranked, oldRatings, updates, displayNames } = params;
  const lines = ["【最終順位・レート】"];
  for (const entry of ranked) {
    const name = displayNames[entry.id] ?? entry.id;
    const old = oldRatings[entry.id] ?? defaultSkillRating();
    const update = updates[entry.id];
    const neu = update?.newRating ?? old;
    const delta = update?.ratingDelta ?? 0;
    const sign = delta >= 0 ? `+${delta}` : `${delta}`;
    lines.push(
      `${entry.rank}位 ${name} ${entry.points}点 → レート ${displayRating(neu)} (${sign}) · σ ${neu.sigma.toFixed(2)}`,
    );
  }
  return lines.join("\n");
}

export function parseRatingRecord(data: Record<string, unknown> | null): OpenSkillRating {
  if (!data) return defaultSkillRating();
  return parseStoredSkill(data);
}

export function formatSignedDelta(delta: number): string {
  return delta >= 0 ? `+${delta}` : `${delta}`;
}
