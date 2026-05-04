import bcrypt from "bcryptjs";

export async function hashPassword(password: string): Promise<string> {
  const salt = await bcrypt.genSalt(10);
  return bcrypt.hash(password, salt);
}

export async function verifyPassword(password: string, hash: string): Promise<boolean> {
  return bcrypt.compare(password, hash);
}

export function validateCredentials(username: string, password: string): string | null {
  if (!/^[a-zA-Z0-9_]{3,32}$/.test(username)) {
    return "Username must be 3..32 chars and use [a-zA-Z0-9_]";
  }
  if (password.length < 8 || password.length > 128) {
    return "Password must be 8..128 chars";
  }
  return null;
}