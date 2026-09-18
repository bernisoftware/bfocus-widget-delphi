unit BFocusText;

{ Utilitários de texto do núcleo: UTF-8 explícito, URL (RFC 3986), base64, datas ISO 8601
  e origem de URL. Tudo o que vai para a rede passa por aqui como bytes UTF-8 (TBFRaw),
  porque no Delphi 7 "string" é ANSI e no Delphi 2009+ é UTF-16. }

{$I BFocusDefines.inc}

interface

uses
  SysUtils, Classes;

type
  { Bytes crus (UTF-8 na rede). No Delphi Unicode é RawByteString e SEMPRE rotulado com a
    página padrão, para que concatenações nunca convertam os bytes. }
  {$IFDEF BF_UNICODE}
  TBFRaw = RawByteString;
  {$ELSE}
  TBFRaw = AnsiString;
  {$ENDIF}

  TBFStringArray = array of string;

{ string nativa → bytes UTF-8. FPC/Lazarus: a string já é UTF-8 (convenção do LCL). }
function BFToUtf8(const S: string): TBFRaw;
{ bytes UTF-8 → string nativa. Delphi 7: caracteres fora da página ANSI viram '?'. }
function BFFromUtf8(const R: TBFRaw): string;
{ Bytes → TBFRaw a partir de um buffer (sem conversão de página de código). }
function BFRawFromBuffer(P: Pointer; Len: Integer): TBFRaw;
function BFRawFromStream(Stream: TStream): TBFRaw;
procedure BFRawToStream(const R: TBFRaw; Stream: TStream);

{ RFC 3986: só [A-Za-z0-9-._~] ficam; o resto vira %XX maiúsculo sobre os bytes UTF-8
  (igual a encodeURIComponent + [!'()*]). }
function BFUrlEncode(const S: string): string;
function BFUrlDecode(const S: string): string;

{ Base64 padrão (+ / =) sobre bytes. }
function BFBase64Encode(const R: TBFRaw): string;
function BFBase64Decode(const S: string): TBFRaw;

function BFTrimRightSlashes(const S: string): string;
function BFSplit(const S: string; Sep: Char): TBFStringArray;
function BFStartsWith(const S, Prefix: string): Boolean;
function BFStartsText(const S, Prefix: string): Boolean;
function BFEndsWith(const S, Suffix: string): Boolean;
function BFLowerAscii(const S: string): string;
function BFUpperAscii(const S: string): string;
function BFIsBlank(const S: string): Boolean;
function BFIntToStr(V: Int64): string;

{ ISO 8601 → milissegundos Unix (UTC). Comparação como instante, nunca como texto. }
function BFIsoToUnixMs(const S: string; out Ms: Int64): Boolean;
function BFIsoToUnixMsDef(const S: string; Default: Int64 = 0): Int64;
{ Milissegundos Unix → ISO 8601 UTC com milissegundos (igual a Date.toISOString). }
function BFUnixMsToIso(Ms: Int64): string;
function BFNowUnixMs: Int64;
{ Diferença local − UTC, em minutos (UTC−3 = −180). }
function BFLocalOffsetMinutes: Integer;
{ Instante Unix (ms) → TDateTime local. }
function BFUnixMsToLocal(Ms: Int64): TDateTime;

{ Origem "esquema://host[:porta]" em minúsculas, sem porta padrão. '' se inválida. }
function BFOriginOf(const Url: string): string;
function BFUrlScheme(const Url: string): string;
function BFUrlHost(const Url: string): string;
{ http:// só é aceito para 127.0.0.1/localhost (testes). }
function BFUrlAllowed(const Url: string): Boolean;

{ '#rrggbb' (ou '#rgb') → componentes. }
function BFParseHexColor(const Hex: string; out R, G, B: Byte): Boolean;

implementation

{$IFDEF MSWINDOWS}
uses
  Windows;
{$ELSE}
  {$IFNDEF FPC}
uses
  DateUtils;
  {$ENDIF}
{$ENDIF}

// ── UTF-8 ──────────────────────────────────────────────────────────────────────

function BFRawFromBuffer(P: Pointer; Len: Integer): TBFRaw;
begin
  SetLength(Result, Len);
  if Len > 0 then
    Move(P^, PAnsiChar(Result)^, Len);
end;

function BFRawFromStream(Stream: TStream): TBFRaw;
var
  Len: Integer;
begin
  Stream.Position := 0;
  Len := Integer(Stream.Size);
  SetLength(Result, Len);
  if Len > 0 then
    Stream.ReadBuffer(PAnsiChar(Result)^, Len);
end;

procedure BFRawToStream(const R: TBFRaw; Stream: TStream);
begin
  if Length(R) > 0 then
    Stream.WriteBuffer(PAnsiChar(R)^, Length(R));
end;

function BFToUtf8(const S: string): TBFRaw;
{$IFDEF BF_UNICODE}
var
  U: UTF8String;
begin
  U := UTF8Encode(S);
  // Copia os bytes para um TBFRaw com o rótulo padrão (sem conversão).
  Result := BFRawFromBuffer(PAnsiChar(U), Length(U));
end;
{$ELSE}
  {$IFDEF BF_FPC}
begin
  Result := S;
end;
  {$ELSE}
begin
  Result := UTF8Encode(WideString(S));
end;
  {$ENDIF}
{$ENDIF}

function BFFromUtf8(const R: TBFRaw): string;
{$IFDEF BF_UNICODE}
begin
  Result := UTF8ToString(R);
end;
{$ELSE}
  {$IFDEF BF_FPC}
begin
  Result := R;
end;
  {$ELSE}
begin
  Result := string(UTF8Decode(R));
end;
  {$ENDIF}
{$ENDIF}

// ── URL ────────────────────────────────────────────────────────────────────────

const
  HEX_DIGITS: array[0..15] of Char = ('0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
    'A', 'B', 'C', 'D', 'E', 'F');

function BFUrlEncode(const S: string): string;
var
  R: TBFRaw;
  I: Integer;
  B: Byte;
  C: AnsiChar;
begin
  R := BFToUtf8(S);
  Result := '';
  for I := 1 to Length(R) do
  begin
    C := R[I];
    if C in ['A'..'Z', 'a'..'z', '0'..'9', '-', '.', '_', '~'] then
      Result := Result + Char(C)
    else
    begin
      B := Ord(C);
      Result := Result + '%' + HEX_DIGITS[B shr 4] + HEX_DIGITS[B and $0F];
    end;
  end;
end;

function HexVal(C: Char): Integer;
begin
  case C of
    '0'..'9': Result := Ord(C) - Ord('0');
    'A'..'F': Result := Ord(C) - Ord('A') + 10;
    'a'..'f': Result := Ord(C) - Ord('a') + 10;
  else
    Result := -1;
  end;
end;

function BFUrlDecode(const S: string): string;
var
  R: TBFRaw;
  I, H, L: Integer;
begin
  R := '';
  I := 1;
  while I <= Length(S) do
  begin
    if (S[I] = '%') and (I + 2 <= Length(S)) then
    begin
      H := HexVal(S[I + 1]);
      L := HexVal(S[I + 2]);
      if (H >= 0) and (L >= 0) then
      begin
        R := R + AnsiChar(H * 16 + L);
        Inc(I, 3);
        Continue;
      end;
    end;
    if S[I] = '+' then
      R := R + ' '
    else
      R := R + BFToUtf8(S[I]);
    Inc(I);
  end;
  Result := BFFromUtf8(R);
end;

// ── base64 ─────────────────────────────────────────────────────────────────────

const
  B64: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

function BFBase64Encode(const R: TBFRaw): string;
var
  I, Len, N: Integer;
  B0, B1, B2: Byte;
begin
  Len := Length(R);
  SetLength(Result, ((Len + 2) div 3) * 4);
  N := 0;
  I := 1;
  while I <= Len do
  begin
    B0 := Ord(R[I]);
    if I + 1 <= Len then B1 := Ord(R[I + 1]) else B1 := 0;
    if I + 2 <= Len then B2 := Ord(R[I + 2]) else B2 := 0;
    Result[N + 1] := B64[(B0 shr 2) + 1];
    Result[N + 2] := B64[(((B0 and $03) shl 4) or (B1 shr 4)) + 1];
    if I + 1 <= Len then
      Result[N + 3] := B64[(((B1 and $0F) shl 2) or (B2 shr 6)) + 1]
    else
      Result[N + 3] := '=';
    if I + 2 <= Len then
      Result[N + 4] := B64[(B2 and $3F) + 1]
    else
      Result[N + 4] := '=';
    Inc(N, 4);
    Inc(I, 3);
  end;
end;

function B64Val(C: Char): Integer;
begin
  case C of
    'A'..'Z': Result := Ord(C) - Ord('A');
    'a'..'z': Result := Ord(C) - Ord('a') + 26;
    '0'..'9': Result := Ord(C) - Ord('0') + 52;
    '+', '-': Result := 62;
    '/', '_': Result := 63;
  else
    Result := -1;
  end;
end;

function BFBase64Decode(const S: string): TBFRaw;
var
  I, V, Acc, Bits: Integer;
begin
  Result := '';
  Acc := 0;
  Bits := 0;
  for I := 1 to Length(S) do
  begin
    V := B64Val(S[I]);
    if V < 0 then
      Continue; // '=' e espaços
    Acc := (Acc shl 6) or V;
    Inc(Bits, 6);
    if Bits >= 8 then
    begin
      Dec(Bits, 8);
      Result := Result + AnsiChar((Acc shr Bits) and $FF);
    end;
  end;
end;

// ── strings ────────────────────────────────────────────────────────────────────

function BFTrimRightSlashes(const S: string): string;
var
  L: Integer;
begin
  L := Length(S);
  while (L > 0) and (S[L] = '/') do
    Dec(L);
  Result := Copy(S, 1, L);
end;

function BFSplit(const S: string; Sep: Char): TBFStringArray;
var
  I, Start, N: Integer;
begin
  Result := nil;
  if S = '' then
    Exit;
  N := 0;
  Start := 1;
  for I := 1 to Length(S) + 1 do
    if (I > Length(S)) or (S[I] = Sep) then
    begin
      SetLength(Result, N + 1);
      Result[N] := Copy(S, Start, I - Start);
      Inc(N);
      Start := I + 1;
    end;
end;

function BFStartsWith(const S, Prefix: string): Boolean;
begin
  Result := (Length(S) >= Length(Prefix)) and (Copy(S, 1, Length(Prefix)) = Prefix);
end;

function BFStartsText(const S, Prefix: string): Boolean;
begin
  Result := (Length(S) >= Length(Prefix)) and
    (BFLowerAscii(Copy(S, 1, Length(Prefix))) = BFLowerAscii(Prefix));
end;

function BFEndsWith(const S, Suffix: string): Boolean;
begin
  Result := (Length(S) >= Length(Suffix)) and
    (Copy(S, Length(S) - Length(Suffix) + 1, Length(Suffix)) = Suffix);
end;

function BFLowerAscii(const S: string): string;
var
  I: Integer;
begin
  Result := S;
  for I := 1 to Length(Result) do
    if (Result[I] >= 'A') and (Result[I] <= 'Z') then
      Result[I] := Char(Ord(Result[I]) + 32);
end;

function BFUpperAscii(const S: string): string;
var
  I: Integer;
begin
  Result := S;
  for I := 1 to Length(Result) do
    if (Result[I] >= 'a') and (Result[I] <= 'z') then
      Result[I] := Char(Ord(Result[I]) - 32);
end;

function BFIsBlank(const S: string): Boolean;
begin
  Result := Trim(S) = '';
end;

function BFIntToStr(V: Int64): string;
begin
  Result := IntToStr(V);
end;

// ── datas ──────────────────────────────────────────────────────────────────────

{ Dias desde 1970-01-01 para uma data civil (algoritmo de Howard Hinnant). }
function DaysFromCivil(Y, M, D: Int64): Int64;
var
  Era, Yoe, Doy, Doe, MM: Int64;
begin
  if M <= 2 then
    Dec(Y);
  if Y >= 0 then Era := Y div 400 else Era := (Y - 399) div 400;
  Yoe := Y - Era * 400;
  if M > 2 then MM := M - 3 else MM := M + 9;
  Doy := (153 * MM + 2) div 5 + D - 1;
  Doe := Yoe * 365 + Yoe div 4 - Yoe div 100 + Doy;
  Result := Era * 146097 + Doe - 719468;
end;

procedure CivilFromDays(Z: Int64; out Y, M, D: Int64);
var
  Era, Doe, Yoe, Doy, Mp: Int64;
begin
  Z := Z + 719468;
  if Z >= 0 then Era := Z div 146097 else Era := (Z - 146096) div 146097;
  Doe := Z - Era * 146097;
  Yoe := (Doe - Doe div 1460 + Doe div 36524 - Doe div 146096) div 365;
  Y := Yoe + Era * 400;
  Doy := Doe - (365 * Yoe + Yoe div 4 - Yoe div 100);
  Mp := (5 * Doy + 2) div 153;
  D := Doy - (153 * Mp + 2) div 5 + 1;
  if Mp < 10 then M := Mp + 3 else M := Mp - 9;
  if M <= 2 then
    Inc(Y);
end;

function ReadDigits(const S: string; var P: Integer; Count: Integer; out V: Integer): Boolean;
var
  I: Integer;
begin
  V := 0;
  Result := False;
  for I := 1 to Count do
  begin
    if (P > Length(S)) or not ((S[P] >= '0') and (S[P] <= '9')) then
      Exit;
    V := V * 10 + Ord(S[P]) - Ord('0');
    Inc(P);
  end;
  Result := True;
end;

function BFIsoToUnixMs(const S: string; out Ms: Int64): Boolean;
var
  P, Y, Mo, D, H, Mi, Se, Frac, FracDigits, OH, OM, Sign: Integer;
  Days: Int64;
begin
  Result := False;
  Ms := 0;
  P := 1;
  H := 0; Mi := 0; Se := 0; Frac := 0; OH := 0; OM := 0; Sign := 0;
  if not ReadDigits(S, P, 4, Y) then Exit;
  if (P > Length(S)) or (S[P] <> '-') then Exit;
  Inc(P);
  if not ReadDigits(S, P, 2, Mo) then Exit;
  if (P > Length(S)) or (S[P] <> '-') then Exit;
  Inc(P);
  if not ReadDigits(S, P, 2, D) then Exit;
  if (Mo < 1) or (Mo > 12) or (D < 1) or (D > 31) then Exit;
  if (P <= Length(S)) and ((S[P] = 'T') or (S[P] = 't') or (S[P] = ' ')) then
  begin
    Inc(P);
    if not ReadDigits(S, P, 2, H) then Exit;
    if (P > Length(S)) or (S[P] <> ':') then Exit;
    Inc(P);
    if not ReadDigits(S, P, 2, Mi) then Exit;
    if (P <= Length(S)) and (S[P] = ':') then
    begin
      Inc(P);
      if not ReadDigits(S, P, 2, Se) then Exit;
      if (P <= Length(S)) and ((S[P] = '.') or (S[P] = ',')) then
      begin
        Inc(P);
        FracDigits := 0;
        while (P <= Length(S)) and (S[P] >= '0') and (S[P] <= '9') do
        begin
          // Só os milissegundos importam; o resto da fração é descartado.
          if FracDigits < 3 then
            Frac := Frac * 10 + Ord(S[P]) - Ord('0');
          Inc(FracDigits);
          Inc(P);
        end;
        while FracDigits < 3 do
        begin
          Frac := Frac * 10;
          Inc(FracDigits);
        end;
      end;
    end;
    if P <= Length(S) then
    begin
      if (S[P] = 'Z') or (S[P] = 'z') then
        Inc(P)
      else if (S[P] = '+') or (S[P] = '-') then
      begin
        if S[P] = '+' then Sign := 1 else Sign := -1;
        Inc(P);
        if not ReadDigits(S, P, 2, OH) then Exit;
        if (P <= Length(S)) and (S[P] = ':') then
          Inc(P);
        if P <= Length(S) then
          if not ReadDigits(S, P, 2, OM) then Exit;
      end;
    end;
  end;
  if P <= Length(S) then
    Exit; // lixo no fim
  if (H > 24) or (Mi > 59) or (Se > 60) then Exit;
  Days := DaysFromCivil(Y, Mo, D);
  Ms := ((Days * 24 + H) * 60 + Mi) * 60000 + Int64(Se) * 1000 + Frac;
  // Sem fuso explícito o servidor manda UTC; com fuso, desfaz o deslocamento.
  Ms := Ms - Int64(Sign) * (Int64(OH) * 60 + OM) * 60000;
  Result := True;
end;

function BFIsoToUnixMsDef(const S: string; Default: Int64): Int64;
begin
  if not BFIsoToUnixMs(S, Result) then
    Result := Default;
end;

function Pad(V: Int64; W: Integer): string;
begin
  Result := IntToStr(V);
  while Length(Result) < W do
    Result := '0' + Result;
end;

function BFUnixMsToIso(Ms: Int64): string;
var
  Days, Rem, Y, M, D: Int64;
begin
  if Ms >= 0 then
    Days := Ms div 86400000
  else
    Days := -((-Ms + 86399999) div 86400000);
  Rem := Ms - Days * 86400000;
  CivilFromDays(Days, Y, M, D);
  Result := Pad(Y, 4) + '-' + Pad(M, 2) + '-' + Pad(D, 2) + 'T' +
    Pad(Rem div 3600000, 2) + ':' + Pad((Rem div 60000) mod 60, 2) + ':' +
    Pad((Rem div 1000) mod 60, 2) + '.' + Pad(Rem mod 1000, 3) + 'Z';
end;

function BFLocalOffsetMinutes: Integer;
{$IFDEF MSWINDOWS}
var
  TZ: TTimeZoneInformation;
  R: DWORD;
begin
  R := GetTimeZoneInformation(TZ);
  Result := -TZ.Bias;
  if R = TIME_ZONE_ID_DAYLIGHT then
    Result := Result - TZ.DaylightBias
  else if R = TIME_ZONE_ID_STANDARD then
    Result := Result - TZ.StandardBias;
end;
{$ELSE}
  {$IFDEF FPC}
begin
  // FPC: GetLocalTimeOffset = UTC − local (UTC−3 → 180).
  Result := -GetLocalTimeOffset;
end;
  {$ELSE}
begin
  Result := Round(TTimeZone.Local.UtcOffset.TotalMinutes);
end;
  {$ENDIF}
{$ENDIF}

const
  UNIX_EPOCH: TDateTime = 25569.0; // 1970-01-01 em TDateTime

function BFNowUnixMs: Int64;
begin
  Result := Round((Now - UNIX_EPOCH) * 86400000.0) - Int64(BFLocalOffsetMinutes) * 60000;
end;

function BFUnixMsToLocal(Ms: Int64): TDateTime;
begin
  Result := UNIX_EPOCH + (Ms + Int64(BFLocalOffsetMinutes) * 60000) / 86400000.0;
end;

// ── URL: origem ────────────────────────────────────────────────────────────────

function BFUrlScheme(const Url: string): string;
var
  P: Integer;
begin
  P := Pos('://', Url);
  if P <= 1 then
    Result := ''
  else
    Result := BFLowerAscii(Copy(Url, 1, P - 1));
end;

{ host[:porta] da URL, em minúsculas, sem credenciais. }
function Authority(const Url: string): string;
var
  P, I, At: Integer;
  Rest: string;
begin
  Result := '';
  P := Pos('://', Url);
  if P <= 1 then
    Exit;
  Rest := Copy(Url, P + 3, MaxInt);
  for I := 1 to Length(Rest) do
    if (Rest[I] = '/') or (Rest[I] = '?') or (Rest[I] = '#') then
    begin
      Rest := Copy(Rest, 1, I - 1);
      Break;
    end;
  At := Pos('@', Rest);
  if At > 0 then
    Rest := Copy(Rest, At + 1, MaxInt);
  Result := BFLowerAscii(Rest);
end;

function BFUrlHost(const Url: string): string;
var
  A: string;
  P: Integer;
begin
  A := Authority(Url);
  if (A <> '') and (A[1] = '[') then
  begin
    P := Pos(']', A);
    Result := Copy(A, 1, P);
    Exit;
  end;
  P := Pos(':', A);
  if P > 0 then
    Result := Copy(A, 1, P - 1)
  else
    Result := A;
end;

function BFOriginOf(const Url: string): string;
var
  Scheme, A: string;
begin
  Result := '';
  Scheme := BFUrlScheme(Url);
  A := Authority(Url);
  if (Scheme = '') or (A = '') then
    Exit;
  if (Scheme = 'https') and BFEndsWith(A, ':443') then
    A := Copy(A, 1, Length(A) - 4)
  else if (Scheme = 'http') and BFEndsWith(A, ':80') then
    A := Copy(A, 1, Length(A) - 3);
  Result := Scheme + '://' + A;
end;

function BFUrlAllowed(const Url: string): Boolean;
var
  Scheme, Host: string;
begin
  Scheme := BFUrlScheme(Url);
  Host := BFUrlHost(Url);
  Result := (Scheme = 'https') or
    ((Scheme = 'http') and ((Host = '127.0.0.1') or (Host = 'localhost') or (Host = '[::1]')));
end;

function BFParseHexColor(const Hex: string; out R, G, B: Byte): Boolean;
var
  S: string;
  I: Integer;
  V: array[0..5] of Integer;
begin
  Result := False;
  R := 0; G := 0; B := 0;
  S := Trim(Hex);
  if (S <> '') and (S[1] = '#') then
    Delete(S, 1, 1);
  if Length(S) = 3 then
    S := S[1] + S[1] + S[2] + S[2] + S[3] + S[3];
  if Length(S) <> 6 then
    Exit;
  for I := 0 to 5 do
  begin
    V[I] := HexVal(S[I + 1]);
    if V[I] < 0 then
      Exit;
  end;
  R := V[0] * 16 + V[1];
  G := V[2] * 16 + V[3];
  B := V[4] * 16 + V[5];
  Result := True;
end;

end.
