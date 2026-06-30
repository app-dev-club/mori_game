#!/usr/bin/env node
/**
 * pubspec.yaml の version を RTDB appMeta に反映する。
 * firebase deploy --only hosting の predeploy から呼ばれる。
 */
import { spawnSync } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const rootDir = join(dirname(fileURLToPath(import.meta.url)), '..');
const pubspecPath = join(rootDir, 'pubspec.yaml');
const configPath = join(rootDir, 'scripts', 'app_meta_config.json');

const databaseUrl =
  'https://mori-game-default-rtdb.asia-southeast1.firebasedatabase.app';

export function parsePubspecVersion(pubspecText) {
  const match = pubspecText.match(/^version:\s*([0-9.]+)\+(\d+)\s*$/m);
  if (!match) {
    throw new Error('pubspec.yaml の version が "1.0.0+1" 形式ではありません');
  }
  const versionName = match[1];
  const buildNumber = Number.parseInt(match[2], 10);
  if (!Number.isFinite(buildNumber) || buildNumber <= 0) {
    throw new Error(`ビルド番号が不正です: ${match[2]}`);
  }
  return { versionName, buildNumber };
}

export function buildAppMetaPayload({ versionName, buildNumber }, optionalConfig = {}) {
  const allowedKeys = new Set([
    'updateMessage',
    'androidStoreUrl',
    'iosStoreUrl',
    'storeUrl',
  ]);
  const extras = {};
  for (const [key, value] of Object.entries(optionalConfig)) {
    if (!allowedKeys.has(key)) continue;
    if (typeof value === 'string' && value.trim().length > 0) {
      extras[key] = value.trim();
    }
  }

  return {
    minVersion: versionName,
    minBuildNumber: buildNumber,
    updatedAt: Date.now(),
    ...extras,
  };
}

function readOptionalConfig() {
  if (!existsSync(configPath)) return {};
  const parsed = JSON.parse(readFileSync(configPath, 'utf8'));
  if (parsed == null || typeof parsed !== 'object' || Array.isArray(parsed)) {
    throw new Error('scripts/app_meta_config.json は JSON オブジェクトである必要があります');
  }
  return parsed;
}

function readProjectId() {
  const firebasercPath = join(rootDir, '.firebaserc');
  if (!existsSync(firebasercPath)) return 'mori-game';
  const firebaserc = JSON.parse(readFileSync(firebasercPath, 'utf8'));
  return firebaserc?.projects?.default ?? 'mori-game';
}

function updateViaFirebaseCli(projectId, payload) {
  const tempDir = mkdtempSync(join(tmpdir(), 'mori-app-meta-'));
  const payloadPath = join(tempDir, 'payload.json');
  writeFileSync(payloadPath, JSON.stringify(payload, null, 2), 'utf8');

  try {
    const result = spawnSync(
      'firebase',
      [
        'database:update',
        '/appMeta',
        `@${payloadPath}`,
        '--project',
        projectId,
        '--force',
      ],
      {
        cwd: rootDir,
        stdio: 'inherit',
        shell: true,
        env: process.env,
      },
    );
    if (result.status !== 0) {
      throw new Error('firebase database:update が失敗しました（firebase login を確認してください）');
    }
  } finally {
    rmSync(tempDir, { recursive: true, force: true });
  }
}

function main() {
  const pubspecText = readFileSync(pubspecPath, 'utf8');
  const version = parsePubspecVersion(pubspecText);
  const optionalConfig = readOptionalConfig();
  const payload = buildAppMetaPayload(version, optionalConfig);
  const projectId = readProjectId();

  if (process.env.DRY_RUN === '1') {
    console.log('[dry-run] appMeta payload:', JSON.stringify(payload, null, 2));
    return;
  }

  console.log(
    `appMeta を更新します: minVersion=${payload.minVersion}, minBuildNumber=${payload.minBuildNumber}`,
  );
  console.log(`project=${projectId}, database=${databaseUrl}`);

  updateViaFirebaseCli(projectId, payload);
  console.log('appMeta の更新が完了しました。');
}

try {
  if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
    main();
  }
} catch (error) {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
}
