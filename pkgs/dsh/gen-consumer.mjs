#!/usr/bin/env node
/**
 * Turn the packed dsh release tarballs into an installable consumer project.
 *
 * The CLI tarball becomes the project root and every `@deepseek-ai/*` package in
 * its dependency closure is rewritten to a `file:` URL into the packed output,
 * so npm resolves the release from the tarballs instead of the registry. The
 * third-party dependencies of those packages keep their published specs and
 * come from the registry as usual.
 *
 * The closure walk matters for two reasons: npm only deduplicates a transitive
 * dependency against a top-level one, and 0.2.2-rc.2 was never published, so
 * anything left to the registry would fail with ETARGET. It also must not add
 * every packed member — `@deepseek-ai/dsh-sdk-client` depends on the CLI, and as
 * a top-level dependency of the CLI's own package that would make npm look the
 * CLI up on the registry.
 */
import { execFileSync } from 'node:child_process'
import { readdirSync, readFileSync, writeFileSync } from 'node:fs'
import { join, resolve } from 'node:path'
import { pathToFileURL } from 'node:url'

const [appDir, ...tarballDirs] = process.argv.slice(2)
if (appDir === undefined || tarballDirs.length === 0) {
  throw new Error('usage: gen-consumer.mjs <app dir> <tarball dir>...')
}

/** Read one tarball's package.json without extracting the archive. */
function manifest(tarball) {
  return JSON.parse(execFileSync('tar', ['-xOzf', tarball, 'package/package.json'], { encoding: 'utf8' }))
}

/** npm `os`/`cpu` matching, the same rules npm applies when installing (scripts/npm-platform.ts upstream). */
function accepts(value, current) {
  if (value === undefined) return true
  if (!Array.isArray(value) || !value.every(tag => typeof tag === 'string')) {
    throw new Error('npm platform constraints must be arrays of strings')
  }
  let accepted = value.every(tag => tag.startsWith('!'))
  for (const tag of value) {
    if (tag === `!${current}`) return false
    if (tag === current || (tag === 'any' && value.length === 1)) accepted = true
  }
  return accepted
}

const packed = new Map()
for (const directory of tarballDirs.map(directory => resolve(directory))) {
  for (const entry of readdirSync(directory).filter(name => name.endsWith('.tgz')).sort()) {
    const tarball = join(directory, entry)
    const parsed = manifest(tarball)
    if (typeof parsed.name !== 'string' || typeof parsed.version !== 'string') {
      throw new Error(`${tarball} manifest lacks name/version`)
    }
    if (packed.has(parsed.name)) throw new Error(`${parsed.name} is packed twice`)
    packed.set(parsed.name, { parsed, tarball })
  }
}

const manifestPath = join(appDir, 'package.json')
const app = JSON.parse(readFileSync(manifestPath, 'utf8'))
const rootDependencies = app.dependencies ?? {}
const rootOptionalDependencies = app.optionalDependencies ?? {}

const closure = new Set()
const queue = [
  ...Object.keys(rootDependencies),
  ...Object.keys(rootOptionalDependencies),
  ...Object.keys(app.peerDependencies ?? {}),
]
while (queue.length > 0) {
  const name = queue.pop()
  if (closure.has(name)) continue
  const entry = packed.get(name)
  if (entry === undefined) continue // third-party: npm resolves it from the registry
  closure.add(name)
  for (const section of ['dependencies', 'optionalDependencies', 'peerDependencies']) {
    for (const dependency of Object.keys(entry.parsed[section] ?? {})) queue.push(dependency)
  }
}

const dependencies = {}
const optionalDependencies = {}
for (const name of [...closure].sort()) {
  if (name === app.name) continue // the CLI tarball is the project root itself
  const { parsed, tarball } = packed.get(name)
  const compatible = accepts(parsed.os, process.platform) && accepts(parsed.cpu, process.arch)
  ;(compatible ? dependencies : optionalDependencies)[name] = pathToFileURL(tarball).href
}
for (const [name, spec] of Object.entries(rootDependencies)) if (!packed.has(name)) dependencies[name] = spec
for (const [name, spec] of Object.entries(rootOptionalDependencies)) if (!packed.has(name)) optionalDependencies[name] = spec

app.dependencies = dependencies
if (Object.keys(optionalDependencies).length > 0) app.optionalDependencies = optionalDependencies
// The published manifest declares devDependencies and prepack scripts; neither
// belongs in an install (npm would skip devDependencies anyway, and scripts
// are disabled on the install, but removing them keeps the tree honest).
delete app.devDependencies
delete app.scripts
writeFileSync(manifestPath, `${JSON.stringify(app, null, 2)}\n`)
console.log(
  `gen-consumer: ${String(Object.keys(dependencies).length)} dependencies, `
  + `${String(Object.keys(optionalDependencies).length)} optional, `
  + `${String(closure.size)} packed package(s) in the CLI closure`,
)
