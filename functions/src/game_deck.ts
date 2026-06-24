export interface Card {
  number: number;
  suit: string;
}

const NON_JOKER_SUITS = ["spade", "heart", "diamond", "club"] as const;

export function generateDeck(): Card[] {
  const deck: Card[] = [];
  for (const suit of NON_JOKER_SUITS) {
    for (let i = 1; i <= 13; i++) {
      deck.push({ number: i, suit });
    }
  }
  deck.push({ number: 0, suit: "joker" });
  deck.push({ number: 0, suit: "joker" });
  return deck;
}

export function shuffleInPlace<T>(items: T[]): void {
  for (let i = items.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [items[i], items[j]] = [items[j], items[i]];
  }
}

export function shuffledPlayerOrder(playerIds: string[]): string[] {
  const ordered = [...playerIds];
  shuffleInPlace(ordered);
  return ordered;
}

export function serializeCard(card: Card): Card {
  return { number: card.number, suit: card.suit };
}
