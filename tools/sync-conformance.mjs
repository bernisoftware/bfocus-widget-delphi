#!/usr/bin/env node
// Copia o kit de conformidade do monorepo (widgets-native/conformance/) para
// tests/conformance/, para o espelho público rodar a integração HTTP sozinho.
// O scenarios.json de tests/ continua sendo a cópia oficial do generate.mjs.
//   node tools/sync-conformance.mjs [--check]
import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const pkg = dirname(dirname(fileURLToPath(import.meta.url)))
const kit = resolve(pkg, '../conformance')
const dest = join(pkg, 'tests', 'conformance')
const FILES = ['mock-server.mjs', 'mock-embed.html', 'scenarios.json']
const check = process.argv.includes('--check')

if (!existsSync(kit)) {
  // Fora do monorepo (espelho): a cópia versionada é a verdade.
  console.log('kit de conformidade fora do alcance; mantendo tests/conformance/')
  process.exit(0)
}
let stale = 0
mkdirSync(dest, { recursive: true })
for (const f of FILES) {
  const src = readFileSync(join(kit, f))
  const out = join(dest, f)
  if (check) {
    if (!existsSync(out) || !readFileSync(out).equals(src)) {
      console.error(`desatualizado: ${out}`)
      stale++
    }
  } else writeFileSync(out, src)
}
if (stale) process.exit(1)
console.log(check ? 'kit de conformidade em dia' : `copiado para ${dest}`)
