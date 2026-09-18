#!/usr/bin/env node
// Sobe o servidor simulado (porta livre), roda o binário de testes com --mock e derruba o
// servidor. Uso: node tests/run-tests.mjs <binário> [--mock-server <caminho>]
// O mock-server padrão é o do monorepo (../../conformance/mock-server.mjs); no espelho
// público o workflow baixa o kit de conformidade para tests/conformance/.
import { spawn } from 'node:child_process'
import { existsSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const args = process.argv.slice(2)
const bin = resolve(args[0] || join(here, 'BFocusTests'))
const idx = args.indexOf('--mock-server')
const candidates = [
  idx >= 0 ? resolve(args[idx + 1]) : null,
  join(here, 'conformance', 'mock-server.mjs'),
  resolve(here, '../../conformance/mock-server.mjs'),
].filter(Boolean)
const mockPath = candidates.find((p) => existsSync(p))
if (!mockPath) {
  console.error('mock-server.mjs não encontrado')
  process.exit(2)
}

const server = spawn(process.execPath, [mockPath, '0'], { stdio: ['ignore', 'pipe', 'inherit'] })
const url = await new Promise((ok, fail) => {
  let buf = ''
  const t = setTimeout(() => fail(new Error('mock-server não subiu')), 10000)
  server.stdout.on('data', (d) => {
    buf += d
    const m = buf.match(/http:\/\/127\.0\.0\.1:\d+/)
    if (m) {
      clearTimeout(t)
      ok(m[0])
    }
  })
})
console.log(`mock-server em ${url}`)
const tests = spawn(bin, ['--scenarios', join(here, 'scenarios.json'), '--mock', url], { stdio: 'inherit' })
tests.on('exit', (code) => {
  server.kill()
  process.exit(code ?? 1)
})
