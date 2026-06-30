import test from 'node:test';
import assert from 'node:assert/strict';

import {
  buildAppMetaPayload,
  parsePubspecVersion,
} from './update_app_meta.mjs';

test('parsePubspecVersion', () => {
  assert.deepEqual(
    parsePubspecVersion('name: mori_game\nversion: 1.0.0+2\n'),
    { versionName: '1.0.0', buildNumber: 2 },
  );
  assert.deepEqual(
    parsePubspecVersion('version: 1.2.3+15\n'),
    { versionName: '1.2.3', buildNumber: 15 },
  );
  assert.throws(() => parsePubspecVersion('version: 1.0.0\n'));
});

test('buildAppMetaPayload merges optional config', () => {
  const payload = buildAppMetaPayload(
    { versionName: '1.0.0', buildNumber: 3 },
    {
      updateMessage: '重要な更新',
      androidStoreUrl: 'https://example.com/android',
      ignoredKey: 'skip',
    },
  );
  assert.equal(payload.minVersion, '1.0.0');
  assert.equal(payload.minBuildNumber, 3);
  assert.equal(payload.updateMessage, '重要な更新');
  assert.equal(payload.androidStoreUrl, 'https://example.com/android');
  assert.equal(payload.ignoredKey, undefined);
});
