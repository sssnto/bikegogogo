import {
  createCipheriv,
  createDecipheriv,
  createHash,
  createHmac,
  randomBytes,
  timingSafeEqual
} from "node:crypto";
import { Algorithm, hash, verify } from "@node-rs/argon2";

const base32Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

export const sha256 = (value: string) =>
  createHash("sha256").update(value).digest("hex");

export const randomToken = (bytes = 32) => randomBytes(bytes).toString("base64url");

export const hashPassword = (password: string) => hash(password, {
  algorithm: Algorithm.Argon2id,
  memoryCost: 19_456,
  timeCost: 2,
  parallelism: 1,
  outputLen: 32
});

export const verifyPassword = (passwordHash: string, password: string) =>
  verify(passwordHash, password);

export const generateTOTPSecret = (bytes = 20): string => {
  const source = randomBytes(bytes);
  let bits = "";
  for (const byte of source) bits += byte.toString(2).padStart(8, "0");
  let result = "";
  for (let index = 0; index < bits.length; index += 5) {
    const chunk = bits.slice(index, index + 5).padEnd(5, "0");
    result += base32Alphabet[Number.parseInt(chunk, 2)];
  }
  return result;
};

const decodeBase32 = (input: string): Buffer => {
  const normalized = input.toUpperCase().replace(/=|\s/g, "");
  let bits = "";
  for (const character of normalized) {
    const value = base32Alphabet.indexOf(character);
    if (value < 0) throw new Error("Invalid TOTP secret");
    bits += value.toString(2).padStart(5, "0");
  }
  const bytes: number[] = [];
  for (let index = 0; index + 8 <= bits.length; index += 8) {
    bytes.push(Number.parseInt(bits.slice(index, index + 8), 2));
  }
  return Buffer.from(bytes);
};

export const totpCode = (secret: string, now = Date.now()): string => {
  const counter = Math.floor(now / 30_000);
  const buffer = Buffer.alloc(8);
  buffer.writeBigUInt64BE(BigInt(counter));
  const digest = createHmac("sha1", decodeBase32(secret)).update(buffer).digest();
  const offset = digest[digest.length - 1] & 0x0f;
  const value = (digest.readUInt32BE(offset) & 0x7fffffff) % 1_000_000;
  return value.toString().padStart(6, "0");
};

export const verifyTOTP = (secret: string, code: string, now = Date.now()): boolean => {
  if (!/^\d{6}$/.test(code)) return false;
  return [-1, 0, 1].some((offset) => {
    const expected = Buffer.from(totpCode(secret, now + offset * 30_000));
    const received = Buffer.from(code);
    return expected.length === received.length && timingSafeEqual(expected, received);
  });
};

const encryptionKey = (secret: string) => createHash("sha256").update(secret).digest();

export const encryptSecret = (value: string, keySecret: string): string => {
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", encryptionKey(keySecret), iv);
  const encrypted = Buffer.concat([cipher.update(value, "utf8"), cipher.final()]);
  return [iv, cipher.getAuthTag(), encrypted].map((part) => part.toString("base64url")).join(".");
};

export const decryptSecret = (value: string, keySecret: string): string => {
  const [ivValue, tagValue, encryptedValue] = value.split(".");
  if (!ivValue || !tagValue || !encryptedValue) throw new Error("Invalid encrypted secret");
  const decipher = createDecipheriv(
    "aes-256-gcm",
    encryptionKey(keySecret),
    Buffer.from(ivValue, "base64url")
  );
  decipher.setAuthTag(Buffer.from(tagValue, "base64url"));
  return Buffer.concat([
    decipher.update(Buffer.from(encryptedValue, "base64url")),
    decipher.final()
  ]).toString("utf8");
};

export const parseCookies = (header?: string): Record<string, string> =>
  Object.fromEntries((header ?? "").split(";").flatMap((item) => {
    const separator = item.indexOf("=");
    if (separator < 1) return [];
    return [[
      decodeURIComponent(item.slice(0, separator).trim()),
      decodeURIComponent(item.slice(separator + 1).trim())
    ]];
  }));

export const cookie = (
  name: string,
  value: string,
  options: { httpOnly?: boolean; secure: boolean; maxAge?: number }
) => {
  const parts = [`${encodeURIComponent(name)}=${encodeURIComponent(value)}`, "Path=/", "SameSite=Strict"];
  if (options.httpOnly) parts.push("HttpOnly");
  if (options.secure) parts.push("Secure");
  if (options.maxAge !== undefined) parts.push(`Max-Age=${options.maxAge}`);
  return parts.join("; ");
};
