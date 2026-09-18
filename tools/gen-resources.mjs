#!/usr/bin/env node
// Gera as units Pascal de textos e cores a partir da fonte única do widget web:
//   widget/src/shared/i18n/{pt_BR,en,es}.json  →  source/core/BFocusI18n.pas
//   widget/src/shared/tokens.json              →  source/core/BFocusTokens.pas
//
// Uso (a partir da raiz do monorepo ou de qualquer lugar):
//   node widgets-native/delphi/tools/gen-resources.mjs [--shared <dir>] [--check]
//
// O resultado é versionado: o espelho público (bfocus-widget-delphi) não enxerga o monorepo.
// A cópia do Lazarus é atualizada por widgets-native/lazarus/tools/sync-from-delphi.mjs.
//
// Os literais saem só com ASCII no fonte (Delphi 7 lê o .pas como ANSI):
//   - Delphi 2009+ (UNICODE): unidades UTF-16 em #$XXXX;
//   - Delphi 7 e FPC: bytes UTF-8 em #$XX, convertidos em tempo de execução por BFFromUtf8.
import { readFileSync, writeFileSync, existsSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join, resolve } from 'node:path'

const here = dirname(fileURLToPath(import.meta.url))
const pkgRoot = dirname(here)
const args = process.argv.slice(2)
const check = args.includes('--check')
const sharedIdx = args.indexOf('--shared')
const shared = sharedIdx >= 0 ? resolve(args[sharedIdx + 1]) : resolve(pkgRoot, '../../widget/src/shared')

if (!existsSync(join(shared, 'tokens.json'))) {
  console.error(`não achei ${join(shared, 'tokens.json')} (use --shared <dir>)`)
  process.exit(2)
}

const LOCALES = ['pt_BR', 'en', 'es']
const dicts = Object.fromEntries(
  LOCALES.map((l) => [l, JSON.parse(readFileSync(join(shared, 'i18n', `${l}.json`), 'utf8'))]),
)
const tokens = JSON.parse(readFileSync(join(shared, 'tokens.json'), 'utf8'))

// ── literais ──────────────────────────────────────────────────────────────────

/** Quebra um literal em pedaços curtos (Delphi 7 limita o literal a 255 elementos). */
function pieces(parts, max = 60) {
  const out = []
  let cur = ''
  let len = 0
  for (const p of parts) {
    if (len + p.length > max && cur) {
      out.push(cur)
      cur = ''
      len = 0
    }
    // Dois trechos entre aspas lado a lado viram um apóstrofo ('a''b'): junta com "+".
    cur += (cur.endsWith("'") && p.startsWith("'") ? ' + ' : '') + p
    len += p.length
  }
  if (cur || !out.length) out.push(cur || "''")
  return out
}

/** Tokens de um literal Pascal: trechos ASCII entre aspas e códigos #$XX. */
function tokensFor(units, hexWidth) {
  const parts = []
  let run = ''
  const flush = () => {
    if (run) {
      // trechos ASCII longos também são quebrados para caber no limite
      for (let i = 0; i < run.length; i += 50) parts.push(`'${run.slice(i, i + 50).replace(/'/g, "''")}'`)
      run = ''
    }
  }
  for (const u of units) {
    if (u >= 0x20 && u < 0x7f) run += String.fromCharCode(u)
    else {
      flush()
      parts.push('#$' + u.toString(16).toUpperCase().padStart(hexWidth, '0'))
    }
  }
  flush()
  return parts
}

function litUtf16(s) {
  const units = []
  for (let i = 0; i < s.length; i++) units.push(s.charCodeAt(i))
  return pieces(tokensFor(units, 4)).join(' +\n      ')
}

function litUtf8(s) {
  return pieces(tokensFor([...Buffer.from(s, 'utf8')], 2)).join(' +\n      ')
}

function arrayConst(name, type, values, lit) {
  const body = values.map((v) => '    ' + lit(v)).join(',\n')
  return `  ${name}: array[0..${values.length - 1}] of ${type} = (\n${body});\n`
}

// ── i18n ──────────────────────────────────────────────────────────────────────

function section(sec) {
  const keys = Object.keys(dicts.pt_BR[sec])
  for (const l of LOCALES) {
    for (const k of Object.keys(dicts[l][sec] || {})) {
      if (!keys.includes(k)) console.warn(`aviso: ${l}.${sec}.${k} não existe em pt_BR (ignorado)`)
    }
  }
  // Chave ausente no idioma = '' → cai para pt_BR em tempo de execução (igual ao web).
  const vals = Object.fromEntries(LOCALES.map((l) => [l, keys.map((k) => (dicts[l][sec] || {})[k] ?? '')]))
  return { keys, vals }
}

const tk = section('tickets')
const rn = section('releaseNotes')

function i18nConsts(prefix, sec) {
  let out = arrayConst(`${prefix}_KEYS`, 'string', sec.keys, (v) => `'${v}'`)
  out += '{$IFDEF BF_UNICODE}\n'
  for (const l of LOCALES) out += arrayConst(`${prefix}_${l.toUpperCase()}`, 'string', sec.vals[l], litUtf16)
  out += '{$ELSE}\n'
  for (const l of LOCALES) out += arrayConst(`${prefix}_${l.toUpperCase()}`, 'TBFRaw', sec.vals[l], litUtf8)
  out += '{$ENDIF}\n'
  return out
}

const HEADER = (src) => `{ GERADO por tools/gen-resources.mjs a partir de ${src}.
  NÃO EDITE: rode  node widgets-native/delphi/tools/gen-resources.mjs }
`

const i18nPas = `unit BFocusI18n;

${HEADER('widget/src/shared/i18n/*.json')}
{$I BFocusDefines.inc}

interface

const
  BF_LOCALE_COUNT = 3;
  BF_LOCALES: array[0..BF_LOCALE_COUNT - 1] of string = ('pt_BR', 'en', 'es');

{ Texto do widget de chamados (seção "tickets"). Chave ausente no idioma cai para pt_BR;
  chave desconhecida devolve a própria chave (mesma regra do makeT do web). }
function BFT(const Locale, Key: string): string;
{ Texto do widget de release notes (seção "releaseNotes"). }
function BFRN(const Locale, Key: string): string;
{ Interpola o marcador (nome entre chaves) numa string traduzida: BFFill(BFT(L, 'chat_queue_size'), 'n', '3'). }
function BFFill(const S, Name, Value: string): string;
{ Índice do idioma em BF_LOCALES (desconhecido = 0, pt_BR). }
function BFLocaleIndex(const Locale: string): Integer;
{ Quantidade de chaves (para testes). }
function BFTicketKeyCount: Integer;
function BFTicketKey(I: Integer): string;
function BFReleaseNotesKeyCount: Integer;
function BFReleaseNotesKey(I: Integer): string;

implementation

uses
  SysUtils, BFocusText;

const
${i18nConsts('TK', tk)}${i18nConsts('RN', rn)}
function BFLocaleIndex(const Locale: string): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to BF_LOCALE_COUNT - 1 do
    if BF_LOCALES[I] = Locale then
    begin
      Result := I;
      Exit;
    end;
end;

function IndexOfKey(const Keys: array of string; const Key: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(Keys) do
    if Keys[I] = Key then
    begin
      Result := I;
      Exit;
    end;
  Result := -1;
end;

{$IFDEF BF_UNICODE}
function Pick(const V: string): string;
begin
  Result := V;
end;
{$ELSE}
function Pick(const V: TBFRaw): string;
begin
  Result := BFFromUtf8(V);
end;
{$ENDIF}

function BFT(const Locale, Key: string): string;
var
  I: Integer;
begin
  I := IndexOfKey(TK_KEYS, Key);
  if I < 0 then
  begin
    Result := Key;
    Exit;
  end;
  case BFLocaleIndex(Locale) of
    1: Result := Pick(TK_EN[I]);
    2: Result := Pick(TK_ES[I]);
  else
    Result := '';
  end;
  if Result = '' then
    Result := Pick(TK_PT_BR[I]);
end;

function BFRN(const Locale, Key: string): string;
var
  I: Integer;
begin
  I := IndexOfKey(RN_KEYS, Key);
  if I < 0 then
  begin
    Result := Key;
    Exit;
  end;
  case BFLocaleIndex(Locale) of
    1: Result := Pick(RN_EN[I]);
    2: Result := Pick(RN_ES[I]);
  else
    Result := '';
  end;
  if Result = '' then
    Result := Pick(RN_PT_BR[I]);
end;

function BFFill(const S, Name, Value: string): string;
begin
  Result := StringReplace(S, '{' + Name + '}', Value, [rfReplaceAll]);
end;

function BFTicketKeyCount: Integer;
begin
  Result := Length(TK_KEYS);
end;

function BFTicketKey(I: Integer): string;
begin
  Result := TK_KEYS[I];
end;

function BFReleaseNotesKeyCount: Integer;
begin
  Result := Length(RN_KEYS);
end;

function BFReleaseNotesKey(I: Integer): string;
begin
  Result := RN_KEYS[I];
end;

end.
`

// ── tokens ────────────────────────────────────────────────────────────────────

const triples = []
for (const [group, val] of Object.entries(tokens)) {
  if (typeof val === 'string') triples.push(['', group, val])
  else for (const [name, color] of Object.entries(val)) triples.push([group, name, color])
}

const tokensPas = `unit BFocusTokens;

${HEADER('widget/src/shared/tokens.json')}
{$I BFocusDefines.inc}

interface

const
  BF_BRAND_FALLBACK = '${tokens.brandFallback}';

{ Cor '#rrggbb' do token (grupo: ticketStatus, chatStatus, priority, neutral).
  Desconhecido = Default. }
function BFTokenColor(const Group, Name: string; const Default: string = ''): string;
function BFTokenCount: Integer;

implementation

const
  TOKEN_COUNT = ${triples.length};
  TOKEN_GROUPS: array[0..TOKEN_COUNT - 1] of string = (
${triples.map((t) => `    '${t[0]}'`).join(',\n')});
  TOKEN_NAMES: array[0..TOKEN_COUNT - 1] of string = (
${triples.map((t) => `    '${t[1]}'`).join(',\n')});
  TOKEN_VALUES: array[0..TOKEN_COUNT - 1] of string = (
${triples.map((t) => `    '${t[2]}'`).join(',\n')});

function BFTokenColor(const Group, Name: string; const Default: string): string;
var
  I: Integer;
begin
  for I := 0 to TOKEN_COUNT - 1 do
    if (TOKEN_GROUPS[I] = Group) and (TOKEN_NAMES[I] = Name) then
    begin
      Result := TOKEN_VALUES[I];
      Exit;
    end;
  Result := Default;
end;

function BFTokenCount: Integer;
begin
  Result := TOKEN_COUNT;
end;

end.
`

// ── gravação ──────────────────────────────────────────────────────────────────

const outputs = [
  [join(pkgRoot, 'source/core/BFocusI18n.pas'), i18nPas],
  [join(pkgRoot, 'source/core/BFocusTokens.pas'), tokensPas],
]
let stale = 0
for (const [file, text] of outputs) {
  if (check) {
    if (!existsSync(file) || readFileSync(file, 'utf8') !== text) {
      console.error(`desatualizado: ${file}`)
      stale++
    }
  } else {
    writeFileSync(file, text)
    console.log(`gravado ${file}`)
  }
}
if (check) {
  if (stale) {
    console.error('Rode: node widgets-native/delphi/tools/gen-resources.mjs')
    process.exit(1)
  }
  console.log('units de textos/cores em dia')
}
