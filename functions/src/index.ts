import { initializeApp } from "firebase-admin/app";
import { getDatabase } from "firebase-admin/database";
import { onValueWritten } from "firebase-functions/v2/database";
import { logger } from "firebase-functions";
import { settleRoomSeries } from "./settle_room";

initializeApp();

const db = getDatabase();

export const onRoomSettlementRequested = onValueWritten(
  {
    ref: "/rooms/{roomId}/settlementRequested",
    region: "asia-southeast1",
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
