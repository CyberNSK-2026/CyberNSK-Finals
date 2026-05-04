export type GameKey = "puzzle" | "petfarm" | "alchemy" | "cards";

export interface User {
  id: number;
  username: string;
  passwordHash: string;
  createdAt: string;
}

export interface Session {
  token: string;
  userId: number;
  createdAt: string;
}

export interface UserStats {
  totalRuns: number;
  completedRuns: number;
  averageScore: number;
}