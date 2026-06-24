import { initializeApp } from "firebase-admin/app";
import { getDatabase } from "firebase-admin/database";
import { onValueWritten } from "firebase-functions/v2/database";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions";
import { processRoomSteward, sweepRoomStewards } from "./room_steward";
import { settleRoomSeries } from "./settle_room";

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
        await runRoomSteward(roomId, "after_settlement");
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
    await runRoomSteward(event.params.roomId, "presence");
  },
);

export const onRoomMatchEndedPhase = onValueWritten(
  {
    ref: "/rooms/{roomId}/moriPhase",
    region,
  },
  async (event) => {
    if (event.data.after.val() !== "finished") return;
    await runRoomSteward(event.params.roomId, "mori_finished");
  },
);

export const onRoomBurstPlayer = onValueWritten(
  {
    ref: "/rooms/{roomId}/burstPlayerId",
    region,
  },
  async (event) => {
    if (event.data.after.val() == null) return;
    await runRoomSteward(event.params.roomId, "burst");
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
