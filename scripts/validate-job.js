#!/usr/bin/env node
/**
 * Validates a generated job.json against the constraints the publish stage relies on.
 * Zero dependencies — runs on the portable Node in C:\Users\kamal\tools\node.
 *
 * Usage: node validate-job.js <path-to-job.json>
 * Exits 0 if valid, 1 with a list of problems otherwise.
 */
const fs = require('fs');
const path = require('path');

// Platform hard limits. Exceeding these makes the upload fail at publish time,
// so we catch it here rather than after a render has already happened.
const LIMITS = {
  ytTitle: 100,
  ytDescription: 5000,
  ytTagsTotal: 500,   // YouTube counts the combined length of all tags
  fbCaption: 5000,
};

const problems = [];
const fail = (msg) => problems.push(msg);

function str(obj, keyPath, { max, min = 1 } = {}) {
  const val = keyPath.split('.').reduce((o, k) => (o == null ? o : o[k]), obj);
  if (typeof val !== 'string') return fail(`${keyPath}: missing or not a string`);
  const trimmed = val.trim();
  if (trimmed.length < min) {
    return fail(min > 1
      ? `${keyPath}: ${trimmed.length} chars, needs at least ${min}`
      : `${keyPath}: empty`);
  }
  if (max && trimmed.length > max) {
    fail(`${keyPath}: ${trimmed.length} chars, max ${max}`);
  }
  return trimmed;
}

function arr(obj, keyPath, { minItems = 1 } = {}) {
  const val = keyPath.split('.').reduce((o, k) => (o == null ? o : o[k]), obj);
  if (!Array.isArray(val)) return fail(`${keyPath}: missing or not an array`);
  if (val.length < minItems) fail(`${keyPath}: needs at least ${minItems} item(s)`);
  if (val.some((v) => typeof v !== 'string' || !v.trim())) {
    fail(`${keyPath}: contains empty or non-string entries`);
  }
  return val;
}

function main() {
  const jobPath = process.argv[2];
  if (!jobPath) {
    console.error('usage: node validate-job.js <path-to-job.json>');
    process.exit(2);
  }

  let job;
  try {
    job = JSON.parse(fs.readFileSync(jobPath, 'utf8'));
  } catch (e) {
    console.error(`INVALID: ${jobPath} is not parseable JSON\n  ${e.message}`);
    process.exit(1);
  }

  str(job, 'slug');
  str(job, 'seed_keyword');
  str(job, 'longtail_keyword');
  str(job, 'reasoning', { min: 40 });   // force actual justification, not a stub

  // YouTube long-form
  str(job, 'youtube.long.title', { max: LIMITS.ytTitle });
  str(job, 'youtube.long.description', { max: LIMITS.ytDescription });
  const longTags = arr(job, 'youtube.long.tags', { minItems: 5 });
  if (Array.isArray(longTags)) {
    const total = longTags.join('').length;
    if (total > LIMITS.ytTagsTotal) {
      fail(`youtube.long.tags: combined ${total} chars, max ${LIMITS.ytTagsTotal}`);
    }
  }

  // YouTube Shorts
  const shortTitle = str(job, 'youtube.short.title', { max: LIMITS.ytTitle });
  str(job, 'youtube.short.description', { max: LIMITS.ytDescription });
  arr(job, 'youtube.short.tags', { minItems: 3 });
  if (shortTitle && !/#shorts/i.test(shortTitle + (job.youtube?.short?.description || ''))) {
    fail('youtube.short: neither title nor description contains #Shorts');
  }

  // Facebook
  str(job, 'facebook.feed.caption', { max: LIMITS.fbCaption });
  arr(job, 'facebook.feed.hashtags', { minItems: 3 });
  str(job, 'facebook.reel.caption', { max: LIMITS.fbCaption });
  arr(job, 'facebook.reel.hashtags', { minItems: 3 });

  // Research provenance — proves the agent actually used the Nexlev tools
  // instead of inventing a keyword from its own priors.
  const refs = arr(job, 'research.reference_thumbnails', { minItems: 1 });
  if (Array.isArray(refs)) {
    refs.forEach((u, i) => {
      if (!/^https:\/\//.test(u)) fail(`research.reference_thumbnails[${i}]: not an https URL`);
    });
  }
  if (!Array.isArray(job.research?.outlier_references) || job.research.outlier_references.length < 1) {
    fail('research.outlier_references: needs at least 1 entry (proof the research tools ran)');
  }

  // Thumbnail must exist on disk next to the job file
  const thumbRel = job.thumbnail?.generated_path;
  if (typeof thumbRel !== 'string' || !thumbRel.trim()) {
    fail('thumbnail.generated_path: missing');
  } else {
    const thumbAbs = path.resolve(path.dirname(jobPath), thumbRel);
    if (!fs.existsSync(thumbAbs)) {
      fail(`thumbnail.generated_path: file not found at ${thumbAbs}`);
    } else if (fs.statSync(thumbAbs).size < 10 * 1024) {
      fail(`thumbnail.generated_path: file is suspiciously small (<10 KB) — download may have failed`);
    }
  }

  if (problems.length) {
    console.error(`INVALID: ${problems.length} problem(s) in ${jobPath}`);
    problems.forEach((p) => console.error(`  - ${p}`));
    process.exit(1);
  }

  console.log(`VALID: ${job.slug}`);
  console.log(`  longtail: ${job.longtail_keyword}`);
  console.log(`  yt long:  ${job.youtube.long.title}`);
  console.log(`  yt short: ${job.youtube.short.title}`);
  process.exit(0);
}

main();
