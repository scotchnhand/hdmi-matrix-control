'use strict';

const GIT_SHA_PATTERN = /^[0-9a-f]{40}$/i;

function unavailableUpdate() {
  return { state: 'unavailable', label: 'Update check unavailable.', url: null };
}

function versionParts(version) {
  if (typeof version !== 'string') return null;
  const match = version.trim().replace(/^v/i, '').match(
    /^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$/
  );
  return match ? [Number(match[1]), Number(match[2]), Number(match[3]), match[4] || ''] : null;
}

function isNewerVersion(latest, running) {
  const latestParts = versionParts(latest);
  const runningParts = versionParts(running);
  if (!latestParts || !runningParts) return null;
  for (let index = 0; index < 3; index += 1) {
    if (latestParts[index] !== runningParts[index]) return latestParts[index] > runningParts[index];
  }
  return Boolean(runningParts[3]) && !latestParts[3];
}

function githubUrl(value) {
  if (typeof value !== 'string') return null;
  try {
    const url = new URL(value);
    return url.protocol === 'https:'
      && url.hostname === 'github.com'
      && !url.username
      && !url.password
      && (!url.port || url.port === '443')
      ? url.href
      : null;
  } catch {
    return null;
  }
}

function evaluateStableUpdate(runningVersion, release) {
  if (!release || typeof release !== 'object' || release.draft || release.prerelease) {
    return unavailableUpdate();
  }
  const releaseUrl = githubUrl(release.html_url);
  const newer = isNewerVersion(release.tag_name, runningVersion);
  if (!releaseUrl || newer === null) return unavailableUpdate();
  if (!newer) return { state: 'current', label: 'No newer stable release found.', url: releaseUrl };

  const availableVersion = release.tag_name.trim().replace(/^v/i, '');
  return {
    state: 'available',
    label: `Version ${availableVersion} is available.`,
    url: releaseUrl,
  };
}

function evaluateDevUpdate(runningRevision, workflowRuns) {
  if (typeof runningRevision !== 'string' || !GIT_SHA_PATTERN.test(runningRevision)) {
    return unavailableUpdate();
  }
  if (!workflowRuns || !Array.isArray(workflowRuns.workflow_runs)) return unavailableUpdate();

  const publishedRun = workflowRuns.workflow_runs.find((run) =>
    run && run.head_branch === 'dev' && run.status === 'completed' && run.conclusion === 'success'
  );
  if (!publishedRun || typeof publishedRun.head_sha !== 'string' || !GIT_SHA_PATTERN.test(publishedRun.head_sha)) {
    return unavailableUpdate();
  }
  const runUrl = githubUrl(publishedRun.html_url);
  if (!runUrl) return unavailableUpdate();

  if (publishedRun.head_sha.toLowerCase() === runningRevision.toLowerCase()) {
    return { state: 'current', label: 'This is the latest published dev image.', url: runUrl };
  }
  return { state: 'available', label: 'A newer published dev image is available.', url: runUrl };
}

const updateCheck = { evaluateStableUpdate, evaluateDevUpdate, unavailableUpdate };
if (typeof module !== 'undefined' && module.exports) module.exports = updateCheck;
if (typeof globalThis !== 'undefined') globalThis.HdmiMatrixUpdateCheck = updateCheck;
