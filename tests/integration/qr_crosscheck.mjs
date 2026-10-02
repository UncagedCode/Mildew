// Cross-checks Mildew's GDScript QrEncoder against Kazuhiko Arase's QRCode encoder
// (MIT; vendored inside npm's qrcode-terminal). Forces the same version/EC level/mask and
// compares every module. Usage: node tests/integration/qr_crosscheck.mjs tests/output/qr_dump.json
import { createRequire } from 'module';
import fs from 'fs';
const require = createRequire(import.meta.url);
const base = process.env.QRCODE_VENDOR || '/opt/node22/lib/node_modules/npm/node_modules/qrcode-terminal/vendor/QRCode';
const QRCode = require(base + '/index.js');
const dump = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
let fails = 0, checked = 0;
for (const c of dump) {
  const qr = new QRCode(c.version, c.ecl);   // Arase ECL: L=1, M=0 (same numbering as spec format bits)
  qr.addData(c.text);
  qr.makeImpl(false, c.mask);
  const n = qr.getModuleCount();
  let diff = 0;
  for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) {
    const a = qr.isDark(y, x) ? '1' : '0';
    if (c.rows[y][x] !== a) diff++;
  }
  checked++;
  if (n !== c.rows.length || diff) { fails++; console.log(`MISMATCH v${c.version} ecl${c.ecl} mask${c.mask} diff=${diff} text=${c.text.slice(0,40)}`); }
}
console.log(`qr crosscheck: ${checked} matrices, ${fails} mismatches`);
process.exit(fails ? 1 : 0);
