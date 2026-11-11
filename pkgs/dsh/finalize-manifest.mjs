#!/usr/bin/env node
/**
 * Rewrite the consumer manifest back into a published-looking one.
 *
 * gen-consumer.mjs points every packed package at a `file:` URL so npm installs
 * from the release tarballs. Those URLs name build-time store paths, and the
 * install is a fixed-output derivation: its output may not reference other
 * store paths, so the specs are replaced with the versions npm actually
 * installed. Third-party specs are left as the release published them.
 *
 * An optional dependency npm skipped for this platform (the macOS-only CUA
 * package) has no installed version and is dropped: it cannot be used here.
 */
import { readFileSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'

const [appDir] = process.argv.slice(2)
if (appDir === undefined) throw new Error('usage: finalize-manifest.mjs <app dir>')

const manifestPath = join(appDir, 'package.json')
const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'))

/** Version npm installed for one package, or undefined when it is not present. */
function installedVersion(name) {
  try {
    return JSON.parse(readFileSync(join(appDir, 'node_modules', name, 'package.json'), 'utf8')).version
  } catch {
    return undefined
  }
}

let rewritten = 0
for (const section of ['dependencies', 'optionalDependencies']) {
  if (manifest[section] === undefined) continue
  const entries = {}
  for (const [name, spec] of Object.entries(manifest[section])) {
    if (!spec.startsWith('file:')) {
      entries[name] = spec
      continue
    }
    const version = installedVersion(name)
    if (version === undefined) continue
    entries[name] = version
    rewritten += 1
  }
  manifest[section] = entries
}

if (JSON.stringify(manifest).includes('file:')) throw new Error('finalize-manifest: a file: spec survived')
writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`)
console.log(`finalize-manifest: ${String(rewritten)} packed dependency spec(s) rewritten to versions`)
