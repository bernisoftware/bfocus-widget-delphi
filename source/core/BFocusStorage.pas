unit BFocusStorage;

{ Persistência local do widget: last_seen do botão e a leitura local de cada chamado
  (o equivalente ao localStorage do web). Padrão: um INI no perfil do usuário. }

{$I BFocusDefines.inc}

interface

uses
  SysUtils, Classes, IniFiles;

type
  IBFocusStorage = interface
    ['{2C9D51E4-8B7A-4F3E-A0C6-91D5E27B4F08}']
    function ReadValue(const Key: string): string;
    procedure WriteValue(const Key, Value: string);
    procedure DeleteValue(const Key: string);
    procedure DeletePrefix(const Prefix: string);
  end;

  { Em memória (testes e apps que não querem arquivo). }
  TBFMemoryStorage = class(TInterfacedObject, IBFocusStorage)
  private
    FData: TStringList;
  public
    constructor Create;
    destructor Destroy; override;
    function ReadValue(const Key: string): string;
    procedure WriteValue(const Key, Value: string);
    procedure DeleteValue(const Key: string);
    procedure DeletePrefix(const Prefix: string);
  end;

  { INI em disco. As chaves são codificadas (RFC 3986) porque ids externos podem ter "=". }
  TBFIniStorage = class(TInterfacedObject, IBFocusStorage)
  private
    FFileName: string;
    FIni: TMemIniFile;
  public
    constructor Create(const FileName: string);
    destructor Destroy; override;
    function ReadValue(const Key: string): string;
    procedure WriteValue(const Key, Value: string);
    procedure DeleteValue(const Key: string);
    procedure DeletePrefix(const Prefix: string);
    property FileName: string read FFileName;
  end;

{ %APPDATA%\bFocus\widget.ini (Windows) ou ~/.config/bfocus/widget.ini. }
function BFDefaultStorageFile: string;
function BFDefaultStorage: IBFocusStorage;
function BFGetEnv(const Name: string): string;

implementation

uses
{$IFDEF MSWINDOWS}
  Windows,
{$ENDIF}
  BFocusText;

const
  SECTION = 'bfocus';

function BFGetEnv(const Name: string): string;
{$IFDEF MSWINDOWS}
var
  Buf: array[0..1023] of Char;
  N: DWORD;
begin
  N := GetEnvironmentVariable(PChar(Name), Buf, Length(Buf));
  if (N > 0) and (N < DWORD(Length(Buf))) then
    SetString(Result, Buf, N)
  else
    Result := '';
end;
{$ELSE}
begin
  Result := GetEnvironmentVariable(Name);
end;
{$ENDIF}

function BFDefaultStorageFile: string;
var
  Base: string;
begin
{$IFDEF MSWINDOWS}
  Base := BFGetEnv('APPDATA');
  if Base = '' then
    Base := ExtractFilePath(ParamStr(0));
  Result := IncludeTrailingPathDelimiter(Base) + 'bFocus' + PathDelim + 'widget.ini';
{$ELSE}
  Base := BFGetEnv('XDG_CONFIG_HOME');
  if Base = '' then
    Base := IncludeTrailingPathDelimiter(BFGetEnv('HOME')) + '.config';
  Result := IncludeTrailingPathDelimiter(Base) + 'bfocus' + PathDelim + 'widget.ini';
{$ENDIF}
end;

function BFDefaultStorage: IBFocusStorage;
begin
  Result := TBFIniStorage.Create(BFDefaultStorageFile);
end;

{ ── memória ────────────────────────────────────────────────────────────── }

constructor TBFMemoryStorage.Create;
begin
  inherited Create;
  FData := TStringList.Create;
end;

destructor TBFMemoryStorage.Destroy;
begin
  FData.Free;
  inherited Destroy;
end;

function TBFMemoryStorage.ReadValue(const Key: string): string;
var
  I: Integer;
begin
  I := FData.IndexOfName(BFUrlEncode(Key));
  if I >= 0 then
    Result := Copy(FData[I], Pos('=', FData[I]) + 1, MaxInt)
  else
    Result := '';
end;

procedure TBFMemoryStorage.WriteValue(const Key, Value: string);
var
  I: Integer;
begin
  // Sem Values[]: no FPC, Values[k] := '' cria "k=" em vez de apagar.
  I := FData.IndexOfName(BFUrlEncode(Key));
  if I >= 0 then
    FData[I] := BFUrlEncode(Key) + '=' + Value
  else
    FData.Add(BFUrlEncode(Key) + '=' + Value);
end;

procedure TBFMemoryStorage.DeleteValue(const Key: string);
var
  I: Integer;
begin
  I := FData.IndexOfName(BFUrlEncode(Key));
  if I >= 0 then
    FData.Delete(I);
end;

procedure TBFMemoryStorage.DeletePrefix(const Prefix: string);
var
  I: Integer;
  P: string;
begin
  P := BFUrlEncode(Prefix);
  for I := FData.Count - 1 downto 0 do
    if BFStartsWith(FData[I], P) then
      FData.Delete(I);
end;

{ ── INI ────────────────────────────────────────────────────────────────── }

constructor TBFIniStorage.Create(const FileName: string);
begin
  inherited Create;
  FFileName := FileName;
  try
    ForceDirectories(ExtractFilePath(FileName));
  except
    // Sem permissão: segue só em memória (o TMemIniFile não grava).
  end;
  FIni := TMemIniFile.Create(FileName);
end;

destructor TBFIniStorage.Destroy;
begin
  FIni.Free;
  inherited Destroy;
end;

function TBFIniStorage.ReadValue(const Key: string): string;
begin
  Result := FIni.ReadString(SECTION, BFUrlEncode(Key), '');
end;

procedure Save(Ini: TMemIniFile);
begin
  try
    Ini.UpdateFile;
  except
    // Disco cheio ou sem permissão: o estado local é só conveniência.
  end;
end;

procedure TBFIniStorage.WriteValue(const Key, Value: string);
begin
  FIni.WriteString(SECTION, BFUrlEncode(Key), Value);
  Save(FIni);
end;

procedure TBFIniStorage.DeleteValue(const Key: string);
begin
  FIni.DeleteKey(SECTION, BFUrlEncode(Key));
  Save(FIni);
end;

procedure TBFIniStorage.DeletePrefix(const Prefix: string);
var
  Keys: TStringList;
  I: Integer;
  P: string;
begin
  P := BFUrlEncode(Prefix);
  Keys := TStringList.Create;
  try
    FIni.ReadSection(SECTION, Keys);
    for I := 0 to Keys.Count - 1 do
      if BFStartsWith(Keys[I], P) then
        FIni.DeleteKey(SECTION, Keys[I]);
  finally
    Keys.Free;
  end;
  Save(FIni);
end;

end.
