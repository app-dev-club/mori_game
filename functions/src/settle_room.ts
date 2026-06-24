import { Database } from "firebase-admin/database";
import {
  botBalancesAfterSettlement,
  humanBalanceUpdates,
  rawMorrieDeltas,
  BOT_FIXED_BALANCE,
} from "./morrie_rules";
import {
  buildSeriesSummary,
  computeSkillUpdates,
  rankByPoints,
  parseRatingRecord,
} from "./rating_logic";
import { displayRating } from "./open_skill";
import {
  asIntMap,
  asStringList,
  asStringMap,
  botDisplayName,
  DEFAULT_STARTING_BALANCE,
  isBot,
  resolveMatchCount,
  resolveMorrieRate,
  resolveNonNegativeInt,
} from "./shared";

export interface SettleRoomResult {
  ok: boolean;
  reason?: string;
}

function isMatchEnded(room: Record<string, unknown>): boolean {
  if (room.burstPlayerId != null) return true;
  return room.moriPhase === "finished";
}

function buildMorrieSummary(params: {
  ranked: ReturnType<typeof rankByPoints>;
  displayNames: Record<string, string>;
  deltas: Record<string, number>;
  rawDeltas: Record<string, number>;
  morrieRate: number;
}): string {
  const { ranked, displayNames, deltas, rawDeltas, morrieRate } = params;
  const lines = [`レート ×${morrieRate}`];
  for (const entry of ranked) {
    const name = displayNames[entry.id] ?? entry.id;
    if (isBot(entry.id)) {
      const raw = rawDeltas[entry.id] ?? 0;
      const sign = raw >= 0 ? "+" : "";
      lines.push(
        `${name}: ${entry.points}点 → ${BOT_FIXED_BALANCE}モリー（変動 ${sign}${raw}、リセット）`,
      );
      continue;
    }
    const delta = deltas[entry.id] ?? 0;
    const sign = delta >= 0 ? "+" : "";
    lines.push(`${name}: ${entry.points}点 → ${sign}${delta} モリー`);
  }
  return lines.join("\n");
}

async function ensureHumanBalance(
  db: Database,
  userId: string,
): Promise<number> {
  const ref = db.ref(`users/${userId}`);
  const snap = await ref.get();
  if (!snap.exists()) {
    await ref.update({
      morrieBalance: DEFAULT_STARTING_BALANCE,
      updatedAt: Date.now(),
    });
    return DEFAULT_STARTING_BALANCE;
  }
  const balance = snap.child("morrieBalance").val();
  if (typeof balance !== "number") {
    await ref.update({
      morrieBalance: DEFAULT_STARTING_BALANCE,
      updatedAt: Date.now(),
    });
    return DEFAULT_STARTING_BALANCE;
  }
  return Math.max(0, Math.round(balance));
}

async function ensureBotRating(db: Database, botId: string): Promise<void> {
  const ref = db.ref(`ratings/${botId}`);
  const snap = await ref.get();
  if (snap.exists()) return;
  await ref.set({
    rating: displayRating({ mu: 25, sigma: 25 / 3 }),
    mu: 25,
    sigma: 25 / 3,
    gamesPlayed: 0,
    isBot: true,
    displayName: botDisplayName(botId),
    playerName: botDisplayName(botId),
  });
}

async function ensureUserRating(
  db: Database,
  userId: string,
  displayName?: string,
): Promise<void> {
  const ref = db.ref(`ratings/${userId}`);
  const snap = await ref.get();
  if (snap.exists()) return;
  const payload: Record<string, unknown> = {
    rating: displayRating({ mu: 25, sigma: 25 / 3 }),
    mu: 25,
    sigma: 25 / 3,
    gamesPlayed: 0,
    isBot: false,
  };
  if (displayName) {
    payload.displayName = displayName;
    payload.playerName = displayName;
  }
  await ref.set(payload);
}

export async function settleRoomSeries(
  db: Database,
  roomId: string,
): Promise<SettleRoomResult> {
  const roomRef = db.ref(`rooms/${roomId}`);
  const snap = await roomRef.get();
  if (!snap.exists()) {
    return { ok: false, reason: "room_not_found" };
  }

  const room = snap.val() as Record<string, unknown>;

  if (room.gameStarted !== true) {
    return { ok: false, reason: "game_not_started" };
  }
  if (!isMatchEnded(room)) {
    return { ok: false, reason: "match_not_ended" };
  }

  const totalMatches = resolveMatchCount(room.totalMatches);
  const completedMatches = resolveNonNegativeInt(room.completedMatches);
  if (completedMatches < totalMatches) {
    return { ok: false, reason: "series_incomplete" };
  }

  const ratingDone = room.seriesRatingApplied === true;
  const morrieDone = room.seriesMorrieSettled === true;
  const morrieRate = resolveMorrieRate(room.morrieRate);
  const morrieNeeded = morrieRate > 0;

  if (ratingDone && (!morrieNeeded || morrieDone)) {
    await roomRef.update({
      settlementRequested: null,
      settlementError: null,
    });
    return { ok: true, reason: "already_settled" };
  }

  const seriesRoster = asStringList(room.seriesPlayerIds);
  const players = asStringList(room.players);
  const roster = seriesRoster.length > 0 ? seriesRoster : players;
  if (roster.length < 2) {
    await roomRef.update({
      settlementRequested: null,
      settlementError: "invalid_roster",
    });
    return { ok: false, reason: "invalid_roster" };
  }

  const finalPoints = asIntMap(room.playerPoints);
  for (const id of roster) {
    if (finalPoints[id] == null) finalPoints[id] = 0;
  }

  const displayNames = asStringMap(room.playerNames);
  for (const id of roster) {
    if (!displayNames[id]?.trim()) {
      displayNames[id] = isBot(id) ? botDisplayName(id) : "プレイヤー";
    }
  }

  const updates: Record<string, unknown> = {};
  const now = Date.now();

  if (!ratingDone) {
    for (const id of roster) {
      if (isBot(id)) {
        await ensureBotRating(db, id);
      } else {
        await ensureUserRating(db, id, displayNames[id]);
      }
    }

    const oldSkills: Record<string, ReturnType<typeof parseRatingRecord>> = {};
    for (const id of roster) {
      const ratingSnap = await db.ref(`ratings/${id}`).get();
      oldSkills[id] = parseRatingRecord(
        ratingSnap.exists() ? (ratingSnap.val() as Record<string, unknown>) : null,
      );
    }

    const skillUpdates = computeSkillUpdates({
      oldRatings: oldSkills,
      playerIds: roster,
      finalPoints,
    });
    const ranked = rankByPoints(roster, finalPoints);
    const ratingSummary = buildSeriesSummary({
      ranked,
      oldRatings: oldSkills,
      updates: skillUpdates,
      displayNames,
    });

    const ratingDetails: Record<string, unknown> = {};
    for (const entry of ranked) {
      const update = skillUpdates[entry.id];
      if (!update) continue;
      const display = displayRating(update.newRating);
      ratingDetails[entry.id] = {
        rank: entry.rank,
        points: entry.points,
        rating: display,
        ratingDelta: update.ratingDelta,
        mu: update.newRating.mu,
        sigma: update.newRating.sigma,
      };

      const ratingPayload: Record<string, unknown> = {
        rating: display,
        mu: update.newRating.mu,
        sigma: update.newRating.sigma,
      };
      const ratingRef = db.ref(`ratings/${entry.id}`);
      const existing = await ratingRef.get();
      const gamesPlayed =
        typeof existing.child("gamesPlayed").val() === "number"
          ? Math.round(existing.child("gamesPlayed").val() as number) + 1
          : 1;
      ratingPayload.gamesPlayed = gamesPlayed;

      if (isBot(entry.id)) {
        ratingPayload.isBot = true;
        ratingPayload.displayName = botDisplayName(entry.id);
        ratingPayload.playerName = botDisplayName(entry.id);
      } else {
        ratingPayload.isBot = false;
        const name = displayNames[entry.id];
        if (name) {
          ratingPayload.displayName = name;
          ratingPayload.playerName = name;
        }
      }
      await ratingRef.update(ratingPayload);
    }

    updates["seriesRatingApplied"] = true;
    updates["seriesRatingSummary"] = ratingSummary;
    updates["seriesRatingDetails"] = ratingDetails;
  }

  if (morrieNeeded && !morrieDone) {
    const humanBalances: Record<string, number> = {};
    for (const id of roster) {
      if (isBot(id)) continue;
      humanBalances[id] = await ensureHumanBalance(db, id);
    }

    const balanceUpdates = humanBalanceUpdates({
      participantIds: roster,
      finalPoints,
      rate: morrieRate,
      humanBalances,
    });

    const ranked = rankByPoints(roster, finalPoints);
    const rawDeltas = rawMorrieDeltas(finalPoints, morrieRate);
    const morrieDetails: Record<string, unknown> = {};
    const appliedDeltas: Record<string, number> = {};
    const newBalances: Record<string, number> = {};

    for (const entry of ranked) {
      const id = entry.id;
      const rawDelta = rawDeltas[id] ?? 0;
      if (isBot(id)) {
        morrieDetails[id] = {
          rank: entry.rank,
          points: entry.points,
          morrieDelta: rawDelta,
          morrieBalance: BOT_FIXED_BALANCE,
          isBot: true,
        };
        continue;
      }

      const delta = balanceUpdates[id] ?? 0;
      const current = humanBalances[id] ?? DEFAULT_STARTING_BALANCE;
      const next = current + delta;
      appliedDeltas[id] = delta;
      newBalances[id] = next;
      morrieDetails[id] = {
        rank: entry.rank,
        points: entry.points,
        morrieDelta: delta,
        morrieBalance: next,
        isBot: false,
      };
    }

    const morrieSummary = buildMorrieSummary({
      ranked,
      displayNames,
      deltas: appliedDeltas,
      rawDeltas,
      morrieRate,
    });

    for (const entry of ranked) {
      const id = entry.id;
      if (isBot(id)) continue;
      const next = newBalances[id];
      if (next == null) continue;
      const name = displayNames[id] ?? "プレイヤー";
      await db.ref(`users/${id}`).update({
        morrieBalance: next,
        updatedAt: now,
      });
      await db.ref(`morrieRankings/${id}`).set({
        playerName: name,
        morrieBalance: next,
        updatedAt: now,
      });
      await roomRef.child(`morrieClaimed/${id}`).set(true);
      await db.ref(`userMorriePending/${id}/${roomId}`).remove();
    }

    const botBalances = botBalancesAfterSettlement(roster);
    updates["seriesMorrieSettled"] = true;
    updates["seriesMorrieSummary"] = morrieSummary;
    updates["seriesMorrieDetails"] = morrieDetails;
    if (Object.keys(botBalances).length > 0) {
      updates["botMorrieBalances"] = botBalances;
    }
  } else if (!morrieNeeded && !morrieDone) {
    updates["seriesMorrieSettled"] = true;
    updates["seriesMorrieSummary"] = "";
    updates["seriesMorrieDetails"] = {};
  }

  updates["settlementRequested"] = null;
  updates["settlementError"] = null;
  updates["settlementCompletedAt"] = now;

  await roomRef.update(updates);
  return { ok: true };
}
