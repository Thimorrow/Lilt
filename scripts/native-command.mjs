import { readFile, writeFile, rename, mkdir, copyFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { resolve, join } from 'node:path';

const [directory, scriptFile, evidenceName, target, windowSize] = process.argv.slice(2);
if (!directory || !scriptFile) throw new Error('Usage: node scripts/native-command.mjs TEST_DIRECTORY SCRIPT_FILE [EVIDENCE_NAME]');
const dir = resolve(directory);
await mkdir(dir, { recursive: true });
const id = randomUUID();
const script = await readFile(resolve(scriptFile), 'utf8');
const dimensions = windowSize?.match(/^(\d+)x(\d+)$/);
if (windowSize && (!dimensions || target !== 'settings')) throw new Error('Window size requires target settings and WIDTHxHEIGHT.');
const settingsSize = dimensions ? { width: Number(dimensions[1]), height: Number(dimensions[2]) } : undefined;
await writeFile(join(dir, 'command.next.json'), JSON.stringify({ id, script, snapshot: Boolean(evidenceName), target, settingsSize }));
await rename(join(dir, 'command.next.json'), join(dir, 'command.json'));
const deadline = Date.now() + 30_000;
let response;
while (Date.now() < deadline) {
  try {
    const next = JSON.parse(await readFile(join(dir, 'response.json'), 'utf8'));
    if (next.id === id) { response = next; break; }
  } catch {}
  await new Promise(resolve => setTimeout(resolve, 100));
}
if (!response) throw new Error('Native app did not respond within 30 seconds.');
if (evidenceName) {
  const folder = resolve('docs/evidence');
  await mkdir(folder, { recursive: true });
  await writeFile(join(folder, `${evidenceName}.json`), JSON.stringify(response, null, 2));
  await copyFile(join(dir, 'capture.png'), join(folder, `${evidenceName}.png`));
}
console.log(JSON.stringify(response, null, 2));
if (response.error || response.nativeChecks?.some(check => !check.pass) || response.result?.checks?.some(check => !check.pass)) process.exitCode = 1;
