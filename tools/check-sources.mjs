#!/usr/bin/env node
// Checagens que o compilador do CI (FPC) não pega, mas quebram no Delphi:
//  1. String literal com caractere não-ASCII: o Delphi 7 lê o .pas como ANSI e o Delphi
//     2009+ também (sem BOM) — acentos em literais viram lixo. Textos visíveis vêm do
//     BFocusI18n (gerado com #$XX) ou de BFFromUtf8(#$..).
//  2. "{" dentro de comentário { }: Pascal não aninha e o comentário termina antes.
//  3. Caracteres de controle soltos no fonte.
// Uso: node tools/check-sources.mjs [dir...]   (padrão: source examples)
import { readFileSync, readdirSync, statSync } from 'node:fs'
import { join, dirname, extname } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = dirname(dirname(fileURLToPath(import.meta.url)))
// tests/ fica de fora: os testes rodam no FPC (UTF-8); no Delphi 2009+ use dcc --codepage:65001.
const dirs = process.argv.slice(2).length ? process.argv.slice(2) : ['source', 'examples']
const EXT = new Set(['.pas', '.dpr', '.lpr', '.dpk', '.inc'])

function walk(d, out) {
  let entries = []
  try { entries = readdirSync(d) } catch { return out }
  for (const e of entries) {
    const p = join(d, e)
    if (statSync(p).isDirectory()) walk(p, out)
    else if (EXT.has(extname(p).toLowerCase())) out.push(p)
  }
  return out
}

let problems = 0
for (const file of dirs.flatMap((d) => walk(join(root, d), []))) {
  const s = readFileSync(file, 'utf8')
  const rel = file.slice(root.length + 1)
  let state = null
  let line = 1
  let lit = ''
  let litLine = 0
  for (let i = 0; i < s.length; i++) {
    const c = s[i]
    if (c === '\n') line++
    const code = c.charCodeAt(0)
    if (code < 32 && c !== '\n' && c !== '\r' && c !== '\t') {
      console.error(`${rel}:${line}: caractere de controle U+${code.toString(16).padStart(4, '0')}`)
      problems++
    }
    if (state === null) {
      if (c === "'") { state = 'str'; lit = ''; litLine = line }
      else if (c === '/' && s[i + 1] === '/') state = 'line'
      else if (c === '(' && s[i + 1] === '*') { state = 'paren'; i++ }
      else if (c === '{') state = 'brace'
    } else if (state === 'str') {
      if (c === "'") {
        if (s[i + 1] === "'") { i++; continue }
        state = null
        if (/[^\x00-\x7f]/.test(lit)) {
          console.error(`${rel}:${litLine}: literal não-ASCII: '${lit.slice(0, 60)}'`)
          problems++
        }
      } else lit += c
    } else if (state === 'line') {
      if (c === '\n') state = null
    } else if (state === 'paren') {
      if (c === '*' && s[i + 1] === ')') { state = null; i++ }
    } else if (state === 'brace') {
      if (c === '{') {
        console.error(`${rel}:${line}: "{" dentro de comentário { }`)
        problems++
      } else if (c === '}') state = null
    }
  }
}
if (problems) {
  console.error(`${problems} problema(s)`)
  process.exit(1)
}
console.log('fontes ok')
