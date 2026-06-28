import { initializeApp } from "firebase-admin/app";
import { getDatabase } from "firebase-admin/database";
import { onValueWritten } from "firebase-functions/v2/database";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions";
import { processRoomSteward, sweepRoomStewards } from "./room_steward";
import { settleRoomSeries } from "./settle_room";
import { applyMatchMorrieOnEnd } from "./morrie_transfer";
import { sweepRoomCleanup, tryDeleteRoomIfNeeded } from "./room_cleanup";

initializeApp();

const db = getDatabase();
const region = "asia-southeast1";

async function runRoomSteward(roomId: string, source: string): Promise<void> {
  try {
    const result = await processRoomSteward(db, roomId);
    if (result.action && result.action !== "skip") {
      logger.info("roomSteward", { roomId, source, action: result.action });
    }
  } catch (error) {
    logger.error("roomSteward error", { roomId, source, error });
  }
}

async function runRoomCleanup(roomId: string, source: string): Promise<void> {
  try {
    const result = await tryDeleteRoomIfNeeded(db, roomId);
    if (result.deleted) {
      logger.info("roomCleanup", { roomId, source, reason: result.reason });
    }
  } catch (error) {
    logger.error("roomCleanup error", { roomId, source, error });
  }
}

async function runMatchMorrieApply(roomId: string, source: string): Promise<void> {
  try {
    const applied = await applyMatchMorrieOnEnd(db, roomId);
    if (applied) {
      logger.info("matchMorrieApply", { roomId, source });
    }
  } catch (error) {
    logger.error("matchMorrieApply error", { roomId, source, error });
  }
}

async function runRoomStewardAndCleanup(
  roomId: string,
  source: string,
): Promise<void> {
  await runRoomSteward(roomId, source);
  await runRoomCleanup(roomId, source);
}

export const onRoomSettlementRequested = onValueWritten(
  {
    ref: "/rooms/{roomId}/settlementRequested",
    region,
  },
  async (event) => {
    const roomId = event.params.roomId;
    const requested = event.data.after.val();
    if (requested !== true) return;

    try {
      const result = await settleRoomSeries(db, roomId);
      if (!result.ok) {
        logger.warn("settleRoomSeries skipped", { roomId, reason: result.reason });
        if (
          result.reason !== "already_settled" &&
          result.reason !== "series_incomplete" &&
          result.reason !== "match_not_ended"
        ) {
          await db.ref(`rooms/${roomId}`).update({
            settlementError: result.reason ?? "failed",
            settlementRequested: null,
          });
        } else if (result.reason === "already_settled") {
          await db.ref(`rooms/${roomId}/settlementRequested`).set(null);
        }
      } else {
        logger.info("settleRoomSeries completed", { roomId, reason: result.reason });
        await runRoomStewardAndCleanup(roomId, "after_settlement");
      }
    } catch (error) {
      logger.error("settleRoomSeries error", { roomId, error });
      await db.ref(`rooms/${roomId}`).update({
        settlementError: "internal_error",
        settlementRequested: null,
      });
    }
  },
);

export const onRoomPresenceChanged = onValueWritten(
  {
    ref: "/rooms/{roomId}/presence",
    region,
  },
  async (event) => {
    await runRoomStewardAndCleanup(event.params.roomId, "presence");
  },
);

export const onRoomMatchEndedPhase = onValueWritten(
  {
    ref: "/rooms/{roomId}/moriPhase",
    region,
  },
  async (event) => {
    if (event.data.after.val() !== "finished") return;
    const roomId = event.params.roomId;
    await runMatchMorrieApply(roomId, "mori_finished");
    await runRoomSteward(roomId, "mori_finished");
  },
);

export const onRoomBurstPlayer = onValueWritten(
  {
    ref: "/rooms/{roomId}/burstPlayerId",
    region,
  },
  async (event) => {
    if (event.data.after.val() == null) return;
    const roomId = event.params.roomId;
    await runMatchMorrieApply(roomId, "burst");
    await runRoomSteward(roomId, "burst");
  },
);

export const onRoomSeriesDeadline = onValueWritten(
  {
    ref: "/rooms/{roomId}/seriesNextMatchAt",
    region,
  },
  async (event) => {
    if (event.data.after.val() == null) return;
    await runRoomSteward(event.params.roomId, "series_deadline_set");
  },
);

export const scheduledRoomStewardSweep = onSchedule(
  {
    schedule: "every 1 minutes",
    region,
    timeZone: "Asia/Tokyo",
  },
  async () => {
    const processed = await sweepRoomStewards(db);
    if (processed > 0) {
      logger.info("roomSteward sweep", { processed });
    }
  },
);

export const scheduledRoomCleanupSweep = onSchedule(
  {
    schedule: "every 5 minutes",
    region,
    timeZone: "Asia/Tokyo",
  },
  async () => {
    const deleted = await sweepRoomCleanup(db);
    if (deleted > 0) {
      logger.info("roomCleanup sweep", { deleted });
    }
  },
);
