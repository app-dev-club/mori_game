export const BOT_ID_PREFIX = "bot_";
export const MAX_BOT_SLOT = 7;
export const DEFAULT_STARTING_BALANCE = 10;
export const BOT_FIXED_BALANCE = 5;

export function isBot(playerId: string): boolean {
  return playerId.startsWith(BOT_ID_PREFIX);
}

export function botDisplayName(botId: string): string {
  const slot = botId.replace(BOT_ID_PREFIX, "");
  return `Bot ${slot}`;
}

export function resolveMatchCount(value: unknown): number {
  if (typeof value === "number" && Number.isFinite(value)) {
    const n = Math.round(value);
    if (n >= 1) return n;
  }
  return 1;
}

export function resolveNonNegativeInt(value: unknown, fallback = 0): number {
  if (typeof value === "number" && Number.isFinite(value)) {
    const n = Math.round(value);
    if (n >= 0) return n;
  }
  return fallback;
}

export function resolveMorrieRate(value: unknown): number {
  if (typeof value === "number" && Number.isFinite(value)) {
    const n = Math.round(value);
    if (n >= 0) return n;
  }
  return 0;
}

export function asStringMap(raw: unknown): Record<string, string> {
  if (!raw || typeof raw !== "object") return {};
  const out: Record<string, string> = {};
  for (const [key, value] of Object.entries(raw as Record<string, unknown>)) {
    if (value != null) out[key] = String(value);
  }
  return out;
}

export function asIntMap(raw: unknown): Record<string, number> {
  if (!raw || typeof raw !== "object") return {};
  const out: Record<string, number> = {};
  for (const [key, value] of Object.entries(raw as Record<string, unknown>)) {
    if (typeof value === "number" && Number.isFinite(value)) {
      out[key] = Math.round(value);
    }
  }
  return out;
}

export function asStringList(raw: unknown): string[] {
  if (!Array.isArray(raw)) return [];
  return raw.map((e) => String(e));
}
