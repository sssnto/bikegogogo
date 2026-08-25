import { generateTOTPSecret, hashPassword } from "./security.js";

const [username, password] = process.argv.slice(2);
if (!username || !password || password.length < 16) {
  console.error("Usage: npm run bootstrap -- <username> <password-at-least-16-characters>");
  process.exit(1);
}

const secret = generateTOTPSecret();
const passwordHash = await hashPassword(password);
const issuer = encodeURIComponent("BikeGoGo Admin");
const account = encodeURIComponent(username);

console.log(`ADMIN_INITIAL_USERNAME=${username}`);
console.log(`ADMIN_INITIAL_PASSWORD_HASH=${passwordHash}`);
console.log(`ADMIN_INITIAL_TOTP_SECRET=${secret}`);
console.log(`TOTP_URI=otpauth://totp/${issuer}:${account}?secret=${secret}&issuer=${issuer}&algorithm=SHA1&digits=6&period=30`);
