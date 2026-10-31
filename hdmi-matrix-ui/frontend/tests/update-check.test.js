'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const {
  evaluateStableUpdate,
  evaluateDevUpdate,
  unavailableUpdate,
} = require('../update-check.js');

const RUNNING_SHA = '1111111111111111111111111111111111111111';
const PUBLISHED_SHA = '2222222222222222222222222222222222222222';
const RUN_URL = 'https://github.com/scotchnhand/hdmi-matrix-control/actions/runs/123456789';

test('stable update is available when GitHub has a newer release', () => {
  const result = evaluateStableUpdate('1.4.0', {
    tag_name: 'v1.5.0',
    draft: false,
    prerelease: false,
    html_url: 'https://github.com/scotchnhand/hdmi-matrix-control/releases/tag/v1.5.0',
  });

  assert.deepEqual(result, {
    state: 'available',
    label: 'Version 1.5.0 is available.',
    url: 'https://github.com/scotchnhand/hdmi-matrix-control/releases/tag/v1.5.0',
  });
});

test('stable update is current when the running release matches latest', () => {
  const result = evaluateStableUpdate('1.5.0', {
    tag_name: 'v1.5.0',
    draft: false,
    prerelease: false,
    html_url: 'https://github.com/scotchnhand/hdmi-matrix-control/releases/tag/v1.5.0',
  });

  assert.equal(result.state, 'current');
  assert.equal(result.label, 'No newer stable release found.');
});

test('dev update is available for a different successful dev image revision', () => {
  const result = evaluateDevUpdate(RUNNING_SHA, {
    workflow_runs: [{
      head_branch: 'dev',
      head_sha: PUBLISHED_SHA,
      status: 'completed',
      conclusion: 'success',
      html_url: RUN_URL,
    }],
  });

  assert.deepEqual(result, {
    state: 'available',
    label: 'A newer published dev image is available.',
    url: RUN_URL,
  });
});

test('dev update is current when the successful image revision matches', () => {
  const result = evaluateDevUpdate(RUNNING_SHA, {
    workflow_runs: [{
      head_branch: 'dev',
      head_sha: RUNNING_SHA,
      status: 'completed',
      conclusion: 'success',
      html_url: RUN_URL,
    }],
  });

  assert.equal(result.state, 'current');
  assert.equal(result.label, 'This is the latest published dev image.');
});

test('a newer dev commit without successful publication is not an available update', () => {
  const result = evaluateDevUpdate(RUNNING_SHA, {
    workflow_runs: [
      {
        head_branch: 'dev',
        head_sha: PUBLISHED_SHA,
        status: 'in_progress',
        conclusion: null,
        html_url: RUN_URL,
      },
      {
        head_branch: 'dev',
        head_sha: RUNNING_SHA,
        status: 'completed',
        conclusion: 'success',
        html_url: RUN_URL,
      },
    ],
  });

  assert.equal(result.state, 'current');
});

test('missing dev revision or successful run is unavailable', () => {
  assert.equal(evaluateDevUpdate('', { workflow_runs: [] }).state, 'unavailable');
  assert.equal(evaluateDevUpdate(RUNNING_SHA, null).state, 'unavailable');
  assert.equal(evaluateDevUpdate(RUNNING_SHA, { workflow_runs: [] }).state, 'unavailable');
  assert.equal(evaluateDevUpdate(RUNNING_SHA, {
    workflow_runs: [{ head_branch: 'dev', head_sha: PUBLISHED_SHA, status: 'in_progress' }],
  }).state, 'unavailable');
});

test('malformed successful dev run data is unavailable', () => {
  assert.equal(evaluateDevUpdate(RUNNING_SHA, {
    workflow_runs: [{
      head_branch: 'dev',
      head_sha: 'not-a-git-sha',
      status: 'completed',
      conclusion: 'success',
      html_url: RUN_URL,
    }],
  }).state, 'unavailable');
});

test('update links reject GitHub URLs with misleading authority components', () => {
  assert.equal(evaluateStableUpdate('1.4.0', {
    tag_name: 'v1.5.0',
    draft: false,
    prerelease: false,
    html_url: 'https://attacker@github.com/scotchnhand/hdmi-matrix-control/releases/tag/v1.5.0',
  }).state, 'unavailable');
});

test('an API or network failure has an unavailable result', () => {
  assert.deepEqual(unavailableUpdate(), {
    state: 'unavailable',
    label: 'Update check unavailable.',
    url: null,
  });
});

test('classic browser scripts load together in one global lexical environment', () => {
  const context = vm.createContext({
    document: {
      getElementById() {
        throw new Error('app.js reached its first DOM lookup');
      },
    },
  });
  const helperSource = readFileSync(path.join(__dirname, '../update-check.js'), 'utf8');
  const appSource = readFileSync(path.join(__dirname, '../app.js'), 'utf8');

  new vm.Script(helperSource, { filename: 'update-check.js' }).runInContext(context);
  assert.throws(
    () => new vm.Script(appSource, { filename: 'app.js' }).runInContext(context),
    /app\.js reached its first DOM lookup/
  );
});
