unit BFocusFormat;

{ Formatação e HTML sem UI: datas (como o toLocaleString do web), tamanho de arquivo,
  ícone por tipo, texto → HTML do composer do chat, "HTML vazio", HTML → texto (para o
  renderizador reserva sem HtmlViewer) e a marcação leve do editor nativo (§10). }

{$I BFocusDefines.inc}

interface

uses
  SysUtils, Classes, BFocusText;

{ Data e hora curtas no formato do sistema (equivale ao toLocaleString sem locale). }
function BFFormatDateTime(const Iso: string): string;
function BFFormatDay(const Iso: string): string;
{ Chat: só a hora quando é hoje; senão data e hora. }
function BFFormatChatTime(const Iso: string): string;
{ Histórico de release notes: "14 de set. de 2026" / "Sep 14, 2026" / "14 sept 2026". }
function BFFormatHistoryDate(const Iso, Locale: string): string;
{ 512 B, 1.5 KB, 2.0 MB (um decimal, ponto como no toFixed). Negativo = ''. }
function BFPrettyBytes(Bytes: Int64): string;
{ Ícone do anexo pelo tipo MIME (emoji; no Delphi 7 ANSI, uma sigla). }
function BFAttachmentIcon(const Mime: string): string;
function BFIsImageMime(const Mime: string): Boolean;

function BFEscapeHtml(const S: string): string;
{ Composer do chat: cada linha vira <p>; vazio = ''. }
function BFTextToHtml(const Text: string): string;
{ Sem texto visível e sem imagem. }
function BFIsHtmlEmpty(const Html: string): Boolean;
{ HTML sanitizado → texto legível (listas com "• ", blocos em linhas). }
function BFHtmlToText(const Html: string): string;
{ Marcação leve do editor nativo → HTML: **negrito**, *itálico* ou _itálico_, ~~riscado~~,
  `código`, [texto](url), linhas "> " (citação), "- " (lista) e "1. " (lista numerada).
  O resto vira parágrafo. }
function BFMarkupToHtml(const Text: string): string;
{ Endereço digitado no campo de link do editor: sem esquema vira https://. }
function BFNormalizeLinkUrl(const Url: string): string;
{ Iniciais (até 2) para o avatar sem foto. }
function BFInitials(const Name: string): string;
{ Compara versões "4.2.0" (aceita "v"). }
function BFSemverCompare(const A, B: string): Integer;

implementation

uses
  BFocusModels;

function DateOf(const Iso: string; out D: TDateTime): Boolean;
var
  Ms: Int64;
begin
  Result := BFIsoToUnixMs(Iso, Ms);
  if Result then
    D := BFUnixMsToLocal(Ms);
end;

function BFFormatDateTime(const Iso: string): string;
var
  D: TDateTime;
begin
  if DateOf(Iso, D) then
    Result := FormatDateTime('ddddd t', D)
  else
    Result := Iso;
end;

function BFFormatDay(const Iso: string): string;
var
  D: TDateTime;
begin
  if DateOf(Iso, D) then
    Result := FormatDateTime('ddddd', D)
  else
    Result := Iso;
end;

function BFFormatChatTime(const Iso: string): string;
var
  D: TDateTime;
begin
  if not DateOf(Iso, D) then
    Result := ''
  else if Trunc(D) = Trunc(Now) then
    Result := FormatDateTime('t', D)
  else
    Result := FormatDateTime('ddddd t', D);
end;

const
  MONTHS_PT: array[1..12] of string = ('jan.', 'fev.', 'mar.', 'abr.', 'mai.', 'jun.',
    'jul.', 'ago.', 'set.', 'out.', 'nov.', 'dez.');
  MONTHS_EN: array[1..12] of string = ('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul',
    'Aug', 'Sep', 'Oct', 'Nov', 'Dec');
  MONTHS_ES: array[1..12] of string = ('ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul',
    'ago', 'sept', 'oct', 'nov', 'dic');

function BFFormatHistoryDate(const Iso, Locale: string): string;
var
  D: TDateTime;
  Y, M, Dd: Word;
  DayStr: string;
begin
  Result := '';
  if (Iso = '') or not DateOf(Iso, D) then
    Exit;
  DecodeDate(D, Y, M, Dd);
  DayStr := Format('%.2d', [Dd]);
  if Locale = 'en' then
    Result := MONTHS_EN[M] + ' ' + DayStr + ', ' + IntToStr(Y)
  else if Locale = 'es' then
    Result := DayStr + ' ' + MONTHS_ES[M] + ' ' + IntToStr(Y)
  else
    Result := DayStr + ' de ' + MONTHS_PT[M] + ' de ' + IntToStr(Y);
end;

function OneDecimal(V: Double): string;
var
  T: Int64;
begin
  T := Round(V * 10);
  Result := IntToStr(T div 10) + '.' + IntToStr(T mod 10);
end;

function BFPrettyBytes(Bytes: Int64): string;
begin
  if Bytes < 0 then
    Result := ''
  else if Bytes < 1024 then
    Result := IntToStr(Bytes) + ' B'
  else if Bytes < 1024 * 1024 then
    Result := OneDecimal(Bytes / 1024) + ' KB'
  else
    Result := OneDecimal(Bytes / (1024 * 1024)) + ' MB';
end;

function BFIsImageMime(const Mime: string): Boolean;
begin
  Result := BFStartsWith(BFLowerAscii(Mime), 'image/');
end;

{$IFDEF BF_UNICODE}
  {$DEFINE BF_EMOJI}
{$ENDIF}
{$IFDEF BF_FPC}
  {$DEFINE BF_EMOJI}
{$ENDIF}

function BFAttachmentIcon(const Mime: string): string;
var
  M: string;
begin
  M := BFLowerAscii(Mime);
{$IFDEF BF_EMOJI}
  if M = '' then Result := BFFromUtf8(#$F0#$9F#$93#$84)
  else if BFStartsWith(M, 'image/') then Result := BFFromUtf8(#$F0#$9F#$96#$BC#$EF#$B8#$8F)
  else if BFStartsWith(M, 'video/') then Result := BFFromUtf8(#$F0#$9F#$8E#$AC)
  else if BFStartsWith(M, 'audio/') then Result := BFFromUtf8(#$F0#$9F#$8E#$B5)
  else if Pos('pdf', M) > 0 then Result := BFFromUtf8(#$F0#$9F#$93#$95)
  else if (Pos('zip', M) > 0) or (Pos('compressed', M) > 0) then
    Result := BFFromUtf8(#$F0#$9F#$97#$9C#$EF#$B8#$8F)
  else if (Pos('sheet', M) > 0) or (Pos('excel', M) > 0) then Result := BFFromUtf8(#$F0#$9F#$93#$8A)
  else if (Pos('word', M) > 0) or (Pos('document', M) > 0) then
    Result := BFFromUtf8(#$F0#$9F#$93#$9D)
  else Result := BFFromUtf8(#$F0#$9F#$93#$84);
{$ELSE}
  // Delphi 7 (ANSI) não desenha emoji: sigla curta no lugar.
  if BFStartsWith(M, 'image/') then Result := 'IMG'
  else if BFStartsWith(M, 'video/') then Result := 'VID'
  else if BFStartsWith(M, 'audio/') then Result := 'AUD'
  else if Pos('pdf', M) > 0 then Result := 'PDF'
  else if (Pos('zip', M) > 0) or (Pos('compressed', M) > 0) then Result := 'ZIP'
  else if (Pos('sheet', M) > 0) or (Pos('excel', M) > 0) then Result := 'XLS'
  else if (Pos('word', M) > 0) or (Pos('document', M) > 0) then Result := 'DOC'
  else Result := 'ARQ';
{$ENDIF}
end;

function BFEscapeHtml(const S: string): string;
begin
  Result := StringReplace(S, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
  Result := StringReplace(Result, '''', '&#39;', [rfReplaceAll]);
end;

function NormalizeNewlines(const S: string): string;
begin
  Result := StringReplace(S, #13#10, #10, [rfReplaceAll]);
  Result := StringReplace(Result, #13, #10, [rfReplaceAll]);
end;

function BFTextToHtml(const Text: string): string;
var
  T: string;
  Lines: TBFStringArray;
  I: Integer;
begin
  T := NormalizeNewlines(Text);
  // Tira linhas vazias do começo e do fim (igual ao replace do textToHtml).
  while (T <> '') and ((T[1] = #10) or ((T[1] = ' ') and (Pos(#10, T) > 0) and
    (Trim(Copy(T, 1, Pos(#10, T) - 1)) = ''))) do
    Delete(T, 1, Pos(#10, T + #10));
  while (T <> '') and (T[Length(T)] = #10) do
    Delete(T, Length(T), 1);
  Result := '';
  if Trim(T) = '' then
    Exit;
  Lines := BFSplit(T, #10);
  for I := 0 to High(Lines) do
    if Trim(Lines[I]) <> '' then
      Result := Result + '<p>' + BFEscapeHtml(Lines[I]) + '</p>'
    else
      Result := Result + '<p></p>';
end;

function StripTags(const Html: string): string;
var
  I: Integer;
  InTag: Boolean;
begin
  Result := '';
  InTag := False;
  for I := 1 to Length(Html) do
    if Html[I] = '<' then
      InTag := True
    else if Html[I] = '>' then
      InTag := False
    else if not InTag then
      Result := Result + Html[I];
end;

function BFIsHtmlEmpty(const Html: string): Boolean;
begin
  if Html = '' then
  begin
    Result := True;
    Exit;
  end;
  if Pos('<img', BFLowerAscii(Html)) > 0 then
  begin
    Result := False;
    Exit;
  end;
  Result := Trim(StringReplace(StripTags(Html), '&nbsp;', '', [rfReplaceAll])) = '';
end;

{ Uma entidade HTML (&amp; &#231; &#xE7; &nbsp;) → texto nativo. }
function DecodeEntity(const Ent: string): string;
var
  Code: Integer;
  E: string;
  R: TBFRaw;
  CP: Cardinal;
begin
  E := BFLowerAscii(Ent);
  if E = 'amp' then Result := '&'
  else if E = 'lt' then Result := '<'
  else if E = 'gt' then Result := '>'
  else if E = 'quot' then Result := '"'
  else if (E = '#39') or (E = 'apos') then Result := ''''
  else if E = 'nbsp' then Result := ' '
  else if (E <> '') and (E[1] = '#') then
  begin
    if (Length(E) > 1) and (E[2] = 'x') then
      Code := StrToIntDef('$' + Copy(E, 3, 8), -1)
    else
      Code := StrToIntDef(Copy(E, 2, 8), -1);
    if Code <= 0 then
    begin
      Result := '';
      Exit;
    end;
    CP := Cardinal(Code);
    if CP < $80 then R := AnsiChar(CP)
    else if CP < $800 then
      R := AnsiChar($C0 or (CP shr 6)) + AnsiChar($80 or (CP and $3F))
    else if CP < $10000 then
      R := AnsiChar($E0 or (CP shr 12)) + AnsiChar($80 or ((CP shr 6) and $3F)) +
        AnsiChar($80 or (CP and $3F))
    else
      R := AnsiChar($F0 or (CP shr 18)) + AnsiChar($80 or ((CP shr 12) and $3F)) +
        AnsiChar($80 or ((CP shr 6) and $3F)) + AnsiChar($80 or (CP and $3F));
    Result := BFFromUtf8(R);
  end
  else
    Result := '&' + Ent + ';';
end;

function DecodeEntities(const S: string): string;
var
  I, J: Integer;
begin
  Result := '';
  I := 1;
  while I <= Length(S) do
  begin
    if S[I] = '&' then
    begin
      J := I + 1;
      while (J <= Length(S)) and (J - I <= 10) and (S[J] <> ';') and (S[J] <> '&') and
        (S[J] <> ' ') do
        Inc(J);
      if (J <= Length(S)) and (S[J] = ';') then
      begin
        Result := Result + DecodeEntity(Copy(S, I + 1, J - I - 1));
        I := J + 1;
        Continue;
      end;
    end;
    Result := Result + S[I];
    Inc(I);
  end;
end;

{ Valor de um atributo numa tag crua (href="..."). }
function AttrValue(const Tag, Attr: string): string;
var
  L: string;
  P, Q: Integer;
  Quote: Char;
begin
  Result := '';
  L := BFLowerAscii(Tag);
  P := Pos(Attr + '=', L);
  if P = 0 then
    Exit;
  P := P + Length(Attr) + 1;
  if P > Length(Tag) then
    Exit;
  Quote := Tag[P];
  if (Quote = '"') or (Quote = '''') then
  begin
    Q := P + 1;
    while (Q <= Length(Tag)) and (Tag[Q] <> Quote) do
      Inc(Q);
    Result := Copy(Tag, P + 1, Q - P - 1);
  end
  else
  begin
    Q := P;
    while (Q <= Length(Tag)) and (Tag[Q] <> ' ') do
      Inc(Q);
    Result := Copy(Tag, P, Q - P);
  end;
  Result := StringReplace(Result, '&amp;', '&', [rfReplaceAll]);
end;

function BFHtmlToText(const Html: string): string;
var
  I, J, AnchorStart: Integer;
  Tag, Name, Buf, Href: string;
  Closing: Boolean;
  Lines: TStringList;
  OrderedStack: array[0..15] of Integer; // contador de <ol> aninhados (0 = <ul>)
  Depth: Integer;
begin
  Buf := '';
  Href := '';
  AnchorStart := 0;
  Depth := 0;
  I := 1;
  while I <= Length(Html) do
  begin
    if Html[I] = '<' then
    begin
      J := I + 1;
      while (J <= Length(Html)) and (Html[J] <> '>') do
        Inc(J);
      Tag := Copy(Html, I + 1, J - I - 1);
      I := J + 1;
      Closing := (Tag <> '') and (Tag[1] = '/');
      if Closing then
        Delete(Tag, 1, 1);
      Name := '';
      J := 1;
      while (J <= Length(Tag)) and (Tag[J] in ['a'..'z', 'A'..'Z', '0'..'9']) do
      begin
        Name := Name + Tag[J];
        Inc(J);
      end;
      Name := BFLowerAscii(Name);
      if (Name = 'br') then
        Buf := Buf + #10
      else if (Name = 'p') or (Name = 'div') or (Name = 'blockquote') or (Name = 'pre') or
        (Name = 'h1') or (Name = 'h2') or (Name = 'h3') or (Name = 'h4') or (Name = 'tr') then
      begin
        if (Buf <> '') and (Buf[Length(Buf)] <> #10) then
          Buf := Buf + #10;
      end
      else if (Name = 'ul') or (Name = 'ol') then
      begin
        if Closing then
        begin
          if Depth > 0 then
            Dec(Depth);
        end
        else if Depth < High(OrderedStack) then
        begin
          Inc(Depth);
          if Name = 'ol' then OrderedStack[Depth] := 1 else OrderedStack[Depth] := 0;
        end;
        if (Buf <> '') and (Buf[Length(Buf)] <> #10) then
          Buf := Buf + #10;
      end
      else if (Name = 'li') and not Closing then
      begin
        if (Buf <> '') and (Buf[Length(Buf)] <> #10) then
          Buf := Buf + #10;
        if (Depth > 0) and (OrderedStack[Depth] > 0) then
        begin
          Buf := Buf + IntToStr(OrderedStack[Depth]) + '. ';
          Inc(OrderedStack[Depth]);
        end
        else
          Buf := Buf + BFBadgeDot + ' ';
      end
      else if (Name = 'img') then
        Buf := Buf + '[img]'
      else if (Name = 'a') then
      begin
        // Sem renderizador de HTML o endereço do link fica visível entre parênteses.
        if not Closing then
        begin
          Href := AttrValue(Tag, 'href');
          AnchorStart := Length(Buf);
        end
        else if (Href <> '') and (Copy(Buf, AnchorStart + 1, MaxInt) <> Href) then
        begin
          Buf := Buf + ' (' + Href + ')';
          Href := '';
        end;
      end;
      Continue;
    end;
    // Espaços em branco do HTML colapsam.
    if Html[I] in [#9, #10, #13] then
    begin
      if (Buf <> '') and not (Buf[Length(Buf)] in [' ', #10]) then
        Buf := Buf + ' ';
    end
    else
      Buf := Buf + Html[I];
    Inc(I);
  end;
  Buf := DecodeEntities(Buf);
  Lines := TStringList.Create;
  try
    Lines.Text := Buf;
    for I := Lines.Count - 1 downto 0 do
      Lines[I] := TrimRight(Lines[I]);
    // No máximo uma linha em branco seguida, e nenhuma nas pontas.
    for I := Lines.Count - 1 downto 1 do
      if (Lines[I] = '') and (Lines[I - 1] = '') then
        Lines.Delete(I);
    while (Lines.Count > 0) and (Lines[0] = '') do
      Lines.Delete(0);
    while (Lines.Count > 0) and (Lines[Lines.Count - 1] = '') do
      Lines.Delete(Lines.Count - 1);
    Result := '';
    for I := 0 to Lines.Count - 1 do
    begin
      if I > 0 then
        Result := Result + sLineBreak;
      Result := Result + Lines[I];
    end;
  finally
    Lines.Free;
  end;
end;

{ Troca pares de marcador (ex.: "**") por tags, só quando fecham na mesma linha. }
function ReplacePairs(const S, Marker, OpenTag, CloseTag: string): string;
var
  P, Q: Integer;
  Rest: string;
begin
  Result := '';
  Rest := S;
  while True do
  begin
    P := Pos(Marker, Rest);
    if P = 0 then
      Break;
    Q := Pos(Marker, Copy(Rest, P + Length(Marker), MaxInt));
    if Q <= 1 then
      Break; // sem fechamento ou vazio
    Result := Result + Copy(Rest, 1, P - 1) + OpenTag +
      Copy(Rest, P + Length(Marker), Q - 1) + CloseTag;
    Rest := Copy(Rest, P + Length(Marker) + Q - 1 + Length(Marker), MaxInt);
  end;
  Result := Result + Rest;
end;

{ Sem esquema vira https:// (mesma regra do campo de link do editor web). }
function BFNormalizeLinkUrl(const Url: string): string;
var
  U: string;
begin
  U := Trim(Url);
  if U = '' then
    Result := ''
  else if (Pos('://', U) > 0) or BFStartsText(U, 'mailto:') or BFStartsText(U, 'tel:') then
    Result := U
  else
    Result := 'https://' + U;
end;

{ [texto](url) → <a href="url">texto</a>, sobre o texto já escapado. Só http(s), mailto e
  tel viram link (javascript: e afins ficam como texto). }
function ReplaceLinks(const S: string): string;
var
  P, Q, R: Integer;
  Rest, Txt, Url: string;
begin
  Result := '';
  Rest := S;
  while True do
  begin
    P := Pos('[', Rest);
    if P = 0 then Break;
    Q := Pos('](', Copy(Rest, P, MaxInt));
    if Q = 0 then Break;
    Q := P + Q - 1;
    R := Pos(')', Copy(Rest, Q + 2, MaxInt));
    if R = 0 then Break;
    R := Q + 1 + R;
    Txt := Copy(Rest, P + 1, Q - P - 1);
    Url := Copy(Rest, Q + 2, R - Q - 2);
    if (Txt = '') or ((BFUrlScheme(Url) <> 'https') and (BFUrlScheme(Url) <> 'http') and
      not BFStartsText(Url, 'mailto:') and not BFStartsText(Url, 'tel:')) then
    begin
      Result := Result + Copy(Rest, 1, P);
      Rest := Copy(Rest, P + 1, MaxInt);
      Continue;
    end;
    Result := Result + Copy(Rest, 1, P - 1) + '<a href="' + Url + '">' + Txt + '</a>';
    Rest := Copy(Rest, R + 1, MaxInt);
  end;
  Result := Result + Rest;
end;

function Inline(const Line: string): string;
begin
  Result := BFEscapeHtml(Line);
  Result := ReplacePairs(Result, '`', '<code>', '</code>');
  Result := ReplaceLinks(Result);
  Result := ReplacePairs(Result, '**', '<strong>', '</strong>');
  Result := ReplacePairs(Result, '~~', '<s>', '</s>');
  Result := ReplacePairs(Result, '*', '<em>', '</em>');
  Result := ReplacePairs(Result, '_', '<em>', '</em>');
end;

function OrderedItem(const Line: string; out Content: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  I := 1;
  while (I <= Length(Line)) and (Line[I] >= '0') and (Line[I] <= '9') do
    Inc(I);
  if (I > 1) and (I + 1 <= Length(Line)) and (Line[I] = '.') and (Line[I + 1] = ' ') then
  begin
    Content := Copy(Line, I + 2, MaxInt);
    Result := True;
  end;
end;

function BFMarkupToHtml(const Text: string): string;
var
  Lines: TBFStringArray;
  I: Integer;
  L, Content, OpenList: string;

  procedure CloseList;
  begin
    if OpenList <> '' then
    begin
      Result := Result + '</' + OpenList + '>';
      OpenList := '';
    end;
  end;

begin
  Result := '';
  OpenList := '';
  if Trim(Text) = '' then
    Exit;
  Lines := BFSplit(NormalizeNewlines(Text), #10);
  for I := 0 to High(Lines) do
  begin
    L := TrimRight(Lines[I]);
    if Copy(L, 1, 2) = '> ' then
    begin
      CloseList;
      Result := Result + '<blockquote><p>' + Inline(Copy(L, 3, MaxInt)) + '</p></blockquote>';
    end
    else if (Copy(L, 1, 2) = '- ') or (Copy(L, 1, 2) = '* ') then
    begin
      if OpenList <> 'ul' then
      begin
        CloseList;
        Result := Result + '<ul>';
        OpenList := 'ul';
      end;
      Result := Result + '<li>' + Inline(Copy(L, 3, MaxInt)) + '</li>';
    end
    else if OrderedItem(L, Content) then
    begin
      if OpenList <> 'ol' then
      begin
        CloseList;
        Result := Result + '<ol>';
        OpenList := 'ol';
      end;
      Result := Result + '<li>' + Inline(Content) + '</li>';
    end
    else
    begin
      CloseList;
      if Trim(L) = '' then
        Result := Result + '<p></p>'
      else
        Result := Result + '<p>' + Inline(L) + '</p>';
    end;
  end;
  CloseList;
  // Parágrafos vazios nas pontas não carregam nada.
  while BFStartsWith(Result, '<p></p>') do
    Delete(Result, 1, 7);
  while BFEndsWith(Result, '<p></p>') do
    Delete(Result, Length(Result) - 6, 7);
end;

function BFInitials(const Name: string): string;
var
  Parts: TBFStringArray;
  I: Integer;
begin
  Result := '';
  Parts := BFSplit(Trim(Name), ' ');
  for I := 0 to High(Parts) do
    if (Parts[I] <> '') and (Length(Result) < 2) then
      Result := Result + Parts[I][1];
  if Result = '' then
    Result := '?';
  Result := AnsiUpperCase(Result);
end;

function BFSemverCompare(const A, B: string): Integer;
var
  PA, PB: TBFStringArray;
  I, VA, VB: Integer;
  SA, SB: string;
begin
  SA := A;
  SB := B;
  if (SA <> '') and (SA[1] in ['v', 'V']) then Delete(SA, 1, 1);
  if (SB <> '') and (SB[1] in ['v', 'V']) then Delete(SB, 1, 1);
  PA := BFSplit(SA, '.');
  PB := BFSplit(SB, '.');
  Result := 0;
  for I := 0 to 2 do
  begin
    if I <= High(PA) then VA := StrToIntDef(PA[I], 0) else VA := 0;
    if I <= High(PB) then VB := StrToIntDef(PB[I], 0) else VB := 0;
    if VA <> VB then
    begin
      Result := VA - VB;
      Exit;
    end;
  end;
end;

end.
