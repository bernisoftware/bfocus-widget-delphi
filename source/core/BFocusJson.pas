unit BFocusJson;

{ JSON mínimo e próprio (Delphi 7+ e FPC não têm um JSON comum). Suficiente para o Host
  Protocol e a API do widget:
  - árvore com ordem de chaves preservada (o payload do usuário exige ordem fixa);
  - saída compacta idêntica ao JSON.stringify (não escapa não-ASCII nem "/");
  - strings guardadas como bytes UTF-8, sem perda mesmo no Delphi 7 (ANSI). }

{$I BFocusDefines.inc}

interface

uses
  SysUtils, Classes, BFocusText;

type
  TBFJsonKind = (jkNull, jkBool, jkNumber, jkString, jkArray, jkObject);

  EBFJson = class(Exception);

  TBFJson = class
  private
    FKind: TBFJsonKind;
    FText: TBFRaw;        // string (UTF-8) ou número (texto como veio)
    FBool: Boolean;
    FItems: TList;        // filhos de array/objeto
    FKeys: TStringList;   // chaves do objeto, na mesma ordem de FItems
    procedure NeedItems;
    procedure WriteTo(var Buf: TBFRaw; var Len: Integer);
  public
    constructor Create(AKind: TBFJsonKind);
    destructor Destroy; override;

    class function Parse(const Utf8: TBFRaw): TBFJson;
    { nil em vez de exceção quando o texto não é JSON. }
    class function TryParse(const Utf8: TBFRaw): TBFJson;
    class function NewObject: TBFJson;
    class function NewArray: TBFJson;
    class function NewNull: TBFJson;
    class function NewBool(V: Boolean): TBFJson;
    class function NewInt(V: Int64): TBFJson;
    class function NewStr(const S: string): TBFJson;
    class function NewUtf8(const R: TBFRaw): TBFJson;

    function Clone: TBFJson;
    function SameAs(Other: TBFJson): Boolean;  // igualdade profunda; objeto ignora a ordem
    function ToJson: TBFRaw;                   // compacto, UTF-8
    function ToJsonString: string;             // idem, como string nativa

    property Kind: TBFJsonKind read FKind;
    function IsNull: Boolean;
    function IsObject: Boolean;
    function IsArray: Boolean;
    function Count: Integer;
    function Item(I: Integer): TBFJson;
    function Key(I: Integer): string;
    function IndexOf(const AKey: string): Integer;
    function Has(const AKey: string): Boolean;
    { Filho pela chave (nil se ausente). Path aceita "a.b.c". }
    function Get(const AKey: string): TBFJson;
    function Path(const DottedPath: string): TBFJson;

    { Valor deste nó. Null = padrão; número em AsString devolve o texto. }
    function AsString: string;
    function AsUtf8: TBFRaw;
    function AsInt64(Default: Int64 = 0): Int64;
    function AsInteger(Default: Integer = 0): Integer;
    function AsFloat(Default: Double = 0): Double;
    function AsBool(Default: Boolean = False): Boolean;

    { Atalhos por chave (ausente ou null = padrão). }
    function StrOf(const AKey: string; const Default: string = ''): string;
    function Utf8Of(const AKey: string): TBFRaw;
    function IntOf(const AKey: string; Default: Int64 = 0): Int64;
    function BoolOf(const AKey: string; Default: Boolean = False): Boolean;
    function ObjOf(const AKey: string): TBFJson;  // só se for objeto
    function ArrOf(const AKey: string): TBFJson;  // só se for array
    function IsNullOrAbsent(const AKey: string): Boolean;

    { Construção. O nó passa a ser dono do filho. }
    function Add(V: TBFJson): TBFJson;
    function Put(const AKey: string; V: TBFJson): TBFJson;
    procedure PutStr(const AKey, Value: string);
    procedure PutUtf8(const AKey: string; const Value: TBFRaw);
    procedure PutInt(const AKey: string; Value: Int64);
    procedure PutBool(const AKey: string; Value: Boolean);
    procedure PutNull(const AKey: string);
    procedure AddStr(const Value: string);
    procedure Delete(I: Integer);
    procedure Remove(const AKey: string);
    procedure Clear;
    { Tira o filho sem liberá-lo (quem chamou vira dono). }
    function Extract(I: Integer): TBFJson;
    function ExtractKey(const AKey: string): TBFJson;
  end;

{ Escapa uma string UTF-8 como literal JSON (com aspas). }
function BFJsonQuote(const Utf8: TBFRaw): TBFRaw;

implementation

type
  TParser = class
  private
    S: TBFRaw;
    P, L: Integer;
    procedure Fail(const Msg: string);
    procedure SkipWs;
    function Peek: AnsiChar;
    function ParseValue(Depth: Integer): TBFJson;
    function ParseString: TBFRaw;
    function ParseNumber: TBFRaw;
    procedure Expect(const Word: TBFRaw);
  end;

const
  MAX_DEPTH = 256;

{ ── construtor rápido de bytes ───────────────────────────────────────────── }

procedure Append(var Buf: TBFRaw; var Len: Integer; const Part: TBFRaw);
var
  N, Cap: Integer;
begin
  N := Length(Part);
  if N = 0 then
    Exit;
  Cap := Length(Buf);
  if Len + N > Cap then
  begin
    Cap := Cap * 2;
    if Cap < Len + N then
      Cap := Len + N + 64;
    SetLength(Buf, Cap);
  end;
  Move(PAnsiChar(Part)^, PAnsiChar(@Buf[Len + 1])^, N);
  Inc(Len, N);
end;

procedure AppendChar(var Buf: TBFRaw; var Len: Integer; C: AnsiChar);
var
  Cap: Integer;
begin
  Cap := Length(Buf);
  if Len + 1 > Cap then
  begin
    Cap := Cap * 2 + 64;
    SetLength(Buf, Cap);
  end;
  Inc(Len);
  Buf[Len] := C;
end;

const
  HEXA: array[0..15] of AnsiChar = ('0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
    'a', 'b', 'c', 'd', 'e', 'f');

procedure AppendQuoted(var Buf: TBFRaw; var Len: Integer; const Utf8: TBFRaw);
var
  I: Integer;
  C: AnsiChar;
begin
  AppendChar(Buf, Len, '"');
  for I := 1 to Length(Utf8) do
  begin
    C := Utf8[I];
    case C of
      '"': begin AppendChar(Buf, Len, '\'); AppendChar(Buf, Len, '"'); end;
      '\': begin AppendChar(Buf, Len, '\'); AppendChar(Buf, Len, '\'); end;
      #8: begin AppendChar(Buf, Len, '\'); AppendChar(Buf, Len, 'b'); end;
      #9: begin AppendChar(Buf, Len, '\'); AppendChar(Buf, Len, 't'); end;
      #10: begin AppendChar(Buf, Len, '\'); AppendChar(Buf, Len, 'n'); end;
      #12: begin AppendChar(Buf, Len, '\'); AppendChar(Buf, Len, 'f'); end;
      #13: begin AppendChar(Buf, Len, '\'); AppendChar(Buf, Len, 'r'); end;
      #0..#7, #11, #14..#31:
        begin
          AppendChar(Buf, Len, '\');
          AppendChar(Buf, Len, 'u');
          AppendChar(Buf, Len, '0');
          AppendChar(Buf, Len, '0');
          AppendChar(Buf, Len, HEXA[Ord(C) shr 4]);
          AppendChar(Buf, Len, HEXA[Ord(C) and $0F]);
        end;
    else
      AppendChar(Buf, Len, C);
    end;
  end;
  AppendChar(Buf, Len, '"');
end;

function BFJsonQuote(const Utf8: TBFRaw): TBFRaw;
var
  Len: Integer;
begin
  Result := '';
  Len := 0;
  AppendQuoted(Result, Len, Utf8);
  SetLength(Result, Len);
end;

{ ── TBFJson ─────────────────────────────────────────────────────────────── }

constructor TBFJson.Create(AKind: TBFJsonKind);
begin
  inherited Create;
  FKind := AKind;
  if AKind in [jkArray, jkObject] then
    NeedItems;
end;

destructor TBFJson.Destroy;
begin
  Clear;
  FItems.Free;
  FKeys.Free;
  inherited Destroy;
end;

procedure TBFJson.NeedItems;
begin
  if FItems = nil then
    FItems := TList.Create;
  if (FKind = jkObject) and (FKeys = nil) then
  begin
    FKeys := TStringList.Create;
    FKeys.CaseSensitive := True;
  end;
end;

class function TBFJson.NewObject: TBFJson;
begin
  Result := TBFJson.Create(jkObject);
end;

class function TBFJson.NewArray: TBFJson;
begin
  Result := TBFJson.Create(jkArray);
end;

class function TBFJson.NewNull: TBFJson;
begin
  Result := TBFJson.Create(jkNull);
end;

class function TBFJson.NewBool(V: Boolean): TBFJson;
begin
  Result := TBFJson.Create(jkBool);
  Result.FBool := V;
end;

class function TBFJson.NewInt(V: Int64): TBFJson;
begin
  Result := TBFJson.Create(jkNumber);
  Result.FText := BFToUtf8(IntToStr(V));
end;

class function TBFJson.NewStr(const S: string): TBFJson;
begin
  Result := TBFJson.Create(jkString);
  Result.FText := BFToUtf8(S);
end;

class function TBFJson.NewUtf8(const R: TBFRaw): TBFJson;
begin
  Result := TBFJson.Create(jkString);
  Result.FText := R;
end;

function TBFJson.IsNull: Boolean;
begin
  Result := FKind = jkNull;
end;

function TBFJson.IsObject: Boolean;
begin
  Result := FKind = jkObject;
end;

function TBFJson.IsArray: Boolean;
begin
  Result := FKind = jkArray;
end;

function TBFJson.Count: Integer;
begin
  if FItems = nil then
    Result := 0
  else
    Result := FItems.Count;
end;

function TBFJson.Item(I: Integer): TBFJson;
begin
  if (FItems = nil) or (I < 0) or (I >= FItems.Count) then
    Result := nil
  else
    Result := TBFJson(FItems[I]);
end;

function TBFJson.Key(I: Integer): string;
begin
  if (FKeys = nil) or (I < 0) or (I >= FKeys.Count) then
    Result := ''
  else
    Result := FKeys[I];
end;

function TBFJson.IndexOf(const AKey: string): Integer;
var
  I: Integer;
begin
  Result := -1;
  if FKeys = nil then
    Exit;
  for I := 0 to FKeys.Count - 1 do
    if FKeys[I] = AKey then
    begin
      Result := I;
      Exit;
    end;
end;

function TBFJson.Has(const AKey: string): Boolean;
begin
  Result := IndexOf(AKey) >= 0;
end;

function TBFJson.Get(const AKey: string): TBFJson;
var
  I: Integer;
begin
  I := IndexOf(AKey);
  if I < 0 then
    Result := nil
  else
    Result := TBFJson(FItems[I]);
end;

function TBFJson.Path(const DottedPath: string): TBFJson;
var
  Parts: TBFStringArray;
  I: Integer;
begin
  Result := Self;
  Parts := BFSplit(DottedPath, '.');
  for I := 0 to High(Parts) do
  begin
    if (Result = nil) or (Result.FKind <> jkObject) then
    begin
      Result := nil;
      Exit;
    end;
    Result := Result.Get(Parts[I]);
  end;
end;

function TBFJson.AsUtf8: TBFRaw;
begin
  case FKind of
    jkString, jkNumber: Result := FText;
    jkBool: if FBool then Result := 'true' else Result := 'false';
  else
    Result := '';
  end;
end;

function TBFJson.AsString: string;
begin
  Result := BFFromUtf8(AsUtf8);
end;

function TBFJson.AsInt64(Default: Int64): Int64;
var
  D: Double;
  Code: Integer;
begin
  case FKind of
    jkNumber, jkString:
      begin
        Result := StrToInt64Def(string(FText), Default);
        if (Result = Default) and (FText <> '') then
        begin
          Val(string(FText), D, Code);
          if Code = 0 then
            Result := Trunc(D);
        end;
      end;
    jkBool: if FBool then Result := 1 else Result := 0;
  else
    Result := Default;
  end;
end;

function TBFJson.AsInteger(Default: Integer): Integer;
begin
  Result := Integer(AsInt64(Default));
end;

function TBFJson.AsFloat(Default: Double): Double;
var
  Code: Integer;
begin
  if FKind in [jkNumber, jkString] then
  begin
    Val(string(FText), Result, Code);
    if Code <> 0 then
      Result := Default;
  end
  else
    Result := Default;
end;

function TBFJson.AsBool(Default: Boolean): Boolean;
begin
  case FKind of
    jkBool: Result := FBool;
    jkNumber: Result := AsInt64(0) <> 0;
    jkString: Result := (FText = 'true') or (FText = '1');
  else
    Result := Default;
  end;
end;

function TBFJson.StrOf(const AKey, Default: string): string;
var
  V: TBFJson;
begin
  V := Get(AKey);
  if (V = nil) or (V.FKind in [jkNull, jkArray, jkObject]) then
    Result := Default
  else
    Result := V.AsString;
end;

function TBFJson.Utf8Of(const AKey: string): TBFRaw;
var
  V: TBFJson;
begin
  V := Get(AKey);
  if V = nil then
    Result := ''
  else
    Result := V.AsUtf8;
end;

function TBFJson.IntOf(const AKey: string; Default: Int64): Int64;
var
  V: TBFJson;
begin
  V := Get(AKey);
  if V = nil then
    Result := Default
  else
    Result := V.AsInt64(Default);
end;

function TBFJson.BoolOf(const AKey: string; Default: Boolean): Boolean;
var
  V: TBFJson;
begin
  V := Get(AKey);
  if V = nil then
    Result := Default
  else
    Result := V.AsBool(Default);
end;

function TBFJson.ObjOf(const AKey: string): TBFJson;
begin
  Result := Get(AKey);
  if (Result <> nil) and (Result.FKind <> jkObject) then
    Result := nil;
end;

function TBFJson.ArrOf(const AKey: string): TBFJson;
begin
  Result := Get(AKey);
  if (Result <> nil) and (Result.FKind <> jkArray) then
    Result := nil;
end;

function TBFJson.IsNullOrAbsent(const AKey: string): Boolean;
var
  V: TBFJson;
begin
  V := Get(AKey);
  Result := (V = nil) or (V.FKind = jkNull);
end;

function TBFJson.Add(V: TBFJson): TBFJson;
begin
  if FKind <> jkArray then
    raise EBFJson.Create('Add so em array');
  NeedItems;
  FItems.Add(V);
  Result := V;
end;

function TBFJson.Put(const AKey: string; V: TBFJson): TBFJson;
var
  I: Integer;
begin
  if FKind <> jkObject then
    raise EBFJson.Create('Put so em objeto');
  NeedItems;
  I := IndexOf(AKey);
  if I >= 0 then
  begin
    TBFJson(FItems[I]).Free;
    FItems[I] := V;
  end
  else
  begin
    FKeys.Add(AKey);
    FItems.Add(V);
  end;
  Result := V;
end;

procedure TBFJson.PutStr(const AKey, Value: string);
begin
  Put(AKey, TBFJson.NewStr(Value));
end;

procedure TBFJson.PutUtf8(const AKey: string; const Value: TBFRaw);
begin
  Put(AKey, TBFJson.NewUtf8(Value));
end;

procedure TBFJson.PutInt(const AKey: string; Value: Int64);
begin
  Put(AKey, TBFJson.NewInt(Value));
end;

procedure TBFJson.PutBool(const AKey: string; Value: Boolean);
begin
  Put(AKey, TBFJson.NewBool(Value));
end;

procedure TBFJson.PutNull(const AKey: string);
begin
  Put(AKey, TBFJson.NewNull);
end;

procedure TBFJson.AddStr(const Value: string);
begin
  Add(TBFJson.NewStr(Value));
end;

procedure TBFJson.Delete(I: Integer);
begin
  Extract(I).Free;
end;

procedure TBFJson.Remove(const AKey: string);
var
  I: Integer;
begin
  I := IndexOf(AKey);
  if I >= 0 then
    Delete(I);
end;

function TBFJson.Extract(I: Integer): TBFJson;
begin
  Result := Item(I);
  if Result = nil then
    Exit;
  FItems.Delete(I);
  if FKeys <> nil then
    FKeys.Delete(I);
end;

function TBFJson.ExtractKey(const AKey: string): TBFJson;
var
  I: Integer;
begin
  I := IndexOf(AKey);
  if I < 0 then
    Result := nil
  else
    Result := Extract(I);
end;

procedure TBFJson.Clear;
var
  I: Integer;
begin
  if FItems <> nil then
  begin
    for I := 0 to FItems.Count - 1 do
      TBFJson(FItems[I]).Free;
    FItems.Clear;
  end;
  if FKeys <> nil then
    FKeys.Clear;
end;

function TBFJson.Clone: TBFJson;
var
  I: Integer;
begin
  Result := TBFJson.Create(FKind);
  Result.FText := FText;
  Result.FBool := FBool;
  for I := 0 to Count - 1 do
    if FKind = jkObject then
      Result.Put(FKeys[I], Item(I).Clone)
    else
      Result.Add(Item(I).Clone);
end;

function TBFJson.SameAs(Other: TBFJson): Boolean;
var
  I: Integer;
  O: TBFJson;
begin
  Result := False;
  if Other = nil then
    Exit;
  if FKind <> Other.FKind then
    Exit;
  case FKind of
    jkNull: Result := True;
    jkBool: Result := FBool = Other.FBool;
    jkString: Result := FText = Other.FText;
    jkNumber: Result := (FText = Other.FText) or (AsFloat(0) = Other.AsFloat(0));
    jkArray:
      begin
        if Count <> Other.Count then
          Exit;
        for I := 0 to Count - 1 do
          if not Item(I).SameAs(Other.Item(I)) then
            Exit;
        Result := True;
      end;
    jkObject:
      begin
        if Count <> Other.Count then
          Exit;
        for I := 0 to Count - 1 do
        begin
          O := Other.Get(FKeys[I]);
          if (O = nil) or not Item(I).SameAs(O) then
            Exit;
        end;
        Result := True;
      end;
  end;
end;

procedure TBFJson.WriteTo(var Buf: TBFRaw; var Len: Integer);
var
  I: Integer;
begin
  case FKind of
    jkNull: Append(Buf, Len, 'null');
    jkBool: if FBool then Append(Buf, Len, 'true') else Append(Buf, Len, 'false');
    jkNumber: Append(Buf, Len, FText);
    jkString: AppendQuoted(Buf, Len, FText);
    jkArray:
      begin
        AppendChar(Buf, Len, '[');
        for I := 0 to Count - 1 do
        begin
          if I > 0 then
            AppendChar(Buf, Len, ',');
          Item(I).WriteTo(Buf, Len);
        end;
        AppendChar(Buf, Len, ']');
      end;
    jkObject:
      begin
        AppendChar(Buf, Len, '{');
        for I := 0 to Count - 1 do
        begin
          if I > 0 then
            AppendChar(Buf, Len, ',');
          AppendQuoted(Buf, Len, BFToUtf8(FKeys[I]));
          AppendChar(Buf, Len, ':');
          Item(I).WriteTo(Buf, Len);
        end;
        AppendChar(Buf, Len, '}');
      end;
  end;
end;

function TBFJson.ToJson: TBFRaw;
var
  Len: Integer;
begin
  Result := '';
  Len := 0;
  WriteTo(Result, Len);
  SetLength(Result, Len);
end;

function TBFJson.ToJsonString: string;
begin
  Result := BFFromUtf8(ToJson);
end;

class function TBFJson.Parse(const Utf8: TBFRaw): TBFJson;
var
  Parser: TParser;
begin
  Parser := TParser.Create;
  try
    Parser.S := Utf8;
    Parser.L := Length(Utf8);
    Parser.P := 1;
    // BOM do UTF-8 no começo é aceito e ignorado.
    if (Parser.L >= 3) and (Utf8[1] = #$EF) and (Utf8[2] = #$BB) and (Utf8[3] = #$BF) then
      Parser.P := 4;
    Result := Parser.ParseValue(0);
    try
      Parser.SkipWs;
      if Parser.P <= Parser.L then
        Parser.Fail('conteudo depois do fim');
    except
      Result.Free;
      raise;
    end;
  finally
    Parser.Free;
  end;
end;

class function TBFJson.TryParse(const Utf8: TBFRaw): TBFJson;
begin
  try
    Result := Parse(Utf8);
  except
    on EBFJson do
      Result := nil;
  end;
end;

{ ── parser ──────────────────────────────────────────────────────────────── }

procedure TParser.Fail(const Msg: string);
begin
  raise EBFJson.CreateFmt('JSON invalido na posicao %d: %s', [P, Msg]);
end;

procedure TParser.SkipWs;
begin
  while (P <= L) and (S[P] in [' ', #9, #10, #13]) do
    Inc(P);
end;

function TParser.Peek: AnsiChar;
begin
  if P <= L then
    Result := S[P]
  else
    Result := #0;
end;

procedure TParser.Expect(const Word: TBFRaw);
begin
  if Copy(S, P, Length(Word)) <> Word then
    Fail('esperado ' + string(Word));
  Inc(P, Length(Word));
end;

function TParser.ParseValue(Depth: Integer): TBFJson;
var
  Child: TBFJson;
  K: TBFRaw;
begin
  if Depth > MAX_DEPTH then
    Fail('aninhamento demais');
  SkipWs;
  Result := nil;
  case Peek of
    '{':
      begin
        Inc(P);
        Result := TBFJson.Create(jkObject);
        try
          SkipWs;
          if Peek = '}' then
            Inc(P)
          else
            while True do
            begin
              SkipWs;
              if Peek <> '"' then
                Fail('esperada chave');
              K := ParseString;
              SkipWs;
              if Peek <> ':' then
                Fail('esperado ":"');
              Inc(P);
              Child := ParseValue(Depth + 1);
              Result.Put(BFFromUtf8(K), Child);
              SkipWs;
              if Peek = ',' then
                Inc(P)
              else if Peek = '}' then
              begin
                Inc(P);
                Break;
              end
              else
                Fail('esperado "," ou "}"');
            end;
        except
          Result.Free;
          raise;
        end;
      end;
    '[':
      begin
        Inc(P);
        Result := TBFJson.Create(jkArray);
        try
          SkipWs;
          if Peek = ']' then
            Inc(P)
          else
            while True do
            begin
              Result.Add(ParseValue(Depth + 1));
              SkipWs;
              if Peek = ',' then
                Inc(P)
              else if Peek = ']' then
              begin
                Inc(P);
                Break;
              end
              else
                Fail('esperado "," ou "]"');
            end;
        except
          Result.Free;
          raise;
        end;
      end;
    '"':
      Result := TBFJson.NewUtf8(ParseString);
    't':
      begin
        Expect('true');
        Result := TBFJson.NewBool(True);
      end;
    'f':
      begin
        Expect('false');
        Result := TBFJson.NewBool(False);
      end;
    'n':
      begin
        Expect('null');
        Result := TBFJson.NewNull;
      end;
    '-', '0'..'9':
      begin
        Result := TBFJson.Create(jkNumber);
        Result.FText := ParseNumber;
      end;
  else
    Fail('valor inesperado');
  end;
end;

function TParser.ParseNumber: TBFRaw;
var
  Start: Integer;
begin
  Start := P;
  if Peek = '-' then
    Inc(P);
  if not (Peek in ['0'..'9']) then
    Fail('numero');
  while Peek in ['0'..'9'] do
    Inc(P);
  if Peek = '.' then
  begin
    Inc(P);
    if not (Peek in ['0'..'9']) then
      Fail('numero');
    while Peek in ['0'..'9'] do
      Inc(P);
  end;
  if Peek in ['e', 'E'] then
  begin
    Inc(P);
    if Peek in ['+', '-'] then
      Inc(P);
    if not (Peek in ['0'..'9']) then
      Fail('numero');
    while Peek in ['0'..'9'] do
      Inc(P);
  end;
  Result := Copy(S, Start, P - Start);
end;

function Utf8OfCodePoint(CP: Cardinal): TBFRaw;
begin
  if CP < $80 then
    Result := AnsiChar(CP)
  else if CP < $800 then
    Result := AnsiChar($C0 or (CP shr 6)) + AnsiChar($80 or (CP and $3F))
  else if CP < $10000 then
    Result := AnsiChar($E0 or (CP shr 12)) + AnsiChar($80 or ((CP shr 6) and $3F)) +
      AnsiChar($80 or (CP and $3F))
  else
    Result := AnsiChar($F0 or (CP shr 18)) + AnsiChar($80 or ((CP shr 12) and $3F)) +
      AnsiChar($80 or ((CP shr 6) and $3F)) + AnsiChar($80 or (CP and $3F));
end;

function TParser.ParseString: TBFRaw;
var
  Buf: TBFRaw;
  Len, I, V, Digit: Integer;
  C: AnsiChar;
  CP, Low: Cardinal;

  function Hex4: Cardinal;
  var
    J: Integer;
  begin
    Result := 0;
    for J := 1 to 4 do
    begin
      if P > L then
        Fail('escape \u incompleto');
      C := S[P];
      case C of
        '0'..'9': Digit := Ord(C) - Ord('0');
        'a'..'f': Digit := Ord(C) - Ord('a') + 10;
        'A'..'F': Digit := Ord(C) - Ord('A') + 10;
      else
        Digit := -1;
      end;
      if Digit < 0 then
        Fail('escape \u invalido');
      Result := Result * 16 + Cardinal(Digit);
      Inc(P);
    end;
  end;

begin
  Inc(P); // aspas de abertura
  Buf := '';
  Len := 0;
  while True do
  begin
    if P > L then
      Fail('string sem fim');
    C := S[P];
    if C = '"' then
    begin
      Inc(P);
      Break;
    end;
    if C = '\' then
    begin
      Inc(P);
      if P > L then
        Fail('escape incompleto');
      C := S[P];
      Inc(P);
      case C of
        '"': AppendChar(Buf, Len, '"');
        '\': AppendChar(Buf, Len, '\');
        '/': AppendChar(Buf, Len, '/');
        'b': AppendChar(Buf, Len, #8);
        'f': AppendChar(Buf, Len, #12);
        'n': AppendChar(Buf, Len, #10);
        'r': AppendChar(Buf, Len, #13);
        't': AppendChar(Buf, Len, #9);
        'u':
          begin
            CP := Hex4;
            if (CP >= $D800) and (CP <= $DBFF) then
            begin
              // Par substituto: 😀 → um code point.
              if (P + 1 <= L) and (S[P] = '\') and (S[P + 1] = 'u') then
              begin
                Inc(P, 2);
                Low := Hex4;
                if (Low >= $DC00) and (Low <= $DFFF) then
                  CP := $10000 + ((CP - $D800) shl 10) + (Low - $DC00)
                else
                  CP := $FFFD;
              end
              else
                CP := $FFFD;
            end
            else if (CP >= $DC00) and (CP <= $DFFF) then
              CP := $FFFD;
            Append(Buf, Len, Utf8OfCodePoint(CP));
          end;
      else
        Fail('escape desconhecido');
      end;
    end
    else
    begin
      if Ord(C) < $20 then
        Fail('caractere de controle na string');
      // Copia um trecho sem escapes de uma vez.
      I := P;
      while (I <= L) and (S[I] <> '"') and (S[I] <> '\') and (Ord(S[I]) >= $20) do
        Inc(I);
      V := I - P;
      Append(Buf, Len, Copy(S, P, V));
      P := I;
    end;
  end;
  SetLength(Buf, Len);
  Result := Buf;
end;

end.
