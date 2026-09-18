unit BFocusHttp;

{ Transporte HTTP do núcleo, atrás de uma interface para trocar a implementação por
  compilador sem mexer no resto:
  - FPC (Linux/macOS): fphttpclient + OpenSSL      → BFocusHttpFpc
  - Windows (Delphi 7…10.3 e FPC): WinInet          → BFocusHttpWinInet
  - Delphi 10.4+: System.Net.HttpClient             → BFocusHttpNet
  O corpo vai e volta como TMemoryStream (bytes), nunca como string, para que anexos
  binários não passem por conversão de página de código. }

{$I BFocusDefines.inc}

interface

uses
  SysUtils, Classes, BFocusText;

const
  BF_TIMEOUT_MS = 15000;        // chamada comum
  BF_UPLOAD_TIMEOUT_MS = 120000; // upload

type
  TBFNetError = (neNone, neTimeout, neNetwork);

  TBFHeaders = class
  private
    FNames: TStringList;
    FValues: TStringList;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    procedure Assign(Source: TBFHeaders);
    procedure SetValue(const Name, Value: string);
    function GetValue(const Name: string): string;
    function IndexOf(const Name: string): Integer;
    function Count: Integer;
    function Name(I: Integer): string;
    function Value(I: Integer): string;
    { Linha "Nome: valor" (resposta crua). }
    procedure AddLine(const Line: string);
  end;

  TBFHttpRequest = class
  public
    Method: string;
    Url: string;
    Headers: TBFHeaders;
    Body: TMemoryStream;
    TimeoutMs: Integer;
    constructor Create(const AMethod, AUrl: string);
    destructor Destroy; override;
    procedure SetBodyRaw(const R: TBFRaw);
    function BodyRaw: TBFRaw;
  end;

  TBFHttpResponse = class
  public
    Status: Integer;
    StatusText: string;
    Headers: TBFHeaders;
    Body: TMemoryStream;
    Error: TBFNetError;      // neNone = houve resposta HTTP (qualquer status)
    ErrorMessage: string;
    constructor Create;
    destructor Destroy; override;
    procedure Reset;
    function BodyRaw: TBFRaw;
  end;

  { Transporte. Execute NUNCA levanta exceção: falha de rede ou tempo esgotado vira
    Response.Error; qualquer status HTTP volta em Response.Status. Tem de ser seguro
    para chamar de threads diferentes ao mesmo tempo (a UI nativa usa threads). }
  IBFocusHttp = interface
    ['{7F3B2A8C-5D14-4E6B-9A21-3C8E0F4D6B15}']
    procedure Execute(Request: TBFHttpRequest; Response: TBFHttpResponse);
  end;

  { Corpo multipart/form-data montado em bytes (upload). }
  TBFMultipart = class
  private
    FBoundary: string;
    FBody: TMemoryStream;
    procedure WriteRaw(const R: TBFRaw);
  public
    constructor Create;
    destructor Destroy; override;
    procedure AddFile(const Field, FileName, ContentType: string; Data: TStream);
    procedure AddField(const Field, Value: string);
    function ContentType: string;
    { Fecha o corpo e copia para Dest. }
    procedure Finish(Dest: TStream);
    property Boundary: string read FBoundary;
  end;

{ Tipo MIME pelo nome do arquivo (os tipos aceitos pelo /upload; resto = octet-stream). }
function BFGuessMime(const FileName: string): string;

implementation

{ ── TBFHeaders ─────────────────────────────────────────────────────────── }

constructor TBFHeaders.Create;
begin
  inherited Create;
  FNames := TStringList.Create;
  FValues := TStringList.Create;
end;

destructor TBFHeaders.Destroy;
begin
  FNames.Free;
  FValues.Free;
  inherited Destroy;
end;

procedure TBFHeaders.Clear;
begin
  FNames.Clear;
  FValues.Clear;
end;

procedure TBFHeaders.Assign(Source: TBFHeaders);
begin
  FNames.Assign(Source.FNames);
  FValues.Assign(Source.FValues);
end;

function TBFHeaders.IndexOf(const Name: string): Integer;
var
  I: Integer;
begin
  for I := 0 to FNames.Count - 1 do
    if BFLowerAscii(FNames[I]) = BFLowerAscii(Name) then
    begin
      Result := I;
      Exit;
    end;
  Result := -1;
end;

procedure TBFHeaders.SetValue(const Name, Value: string);
var
  I: Integer;
begin
  I := IndexOf(Name);
  if I >= 0 then
    FValues[I] := Value
  else
  begin
    FNames.Add(Name);
    FValues.Add(Value);
  end;
end;

function TBFHeaders.GetValue(const Name: string): string;
var
  I: Integer;
begin
  I := IndexOf(Name);
  if I >= 0 then
    Result := FValues[I]
  else
    Result := '';
end;

function TBFHeaders.Count: Integer;
begin
  Result := FNames.Count;
end;

function TBFHeaders.Name(I: Integer): string;
begin
  Result := FNames[I];
end;

function TBFHeaders.Value(I: Integer): string;
begin
  Result := FValues[I];
end;

procedure TBFHeaders.AddLine(const Line: string);
var
  P: Integer;
begin
  P := Pos(':', Line);
  if P > 1 then
    SetValue(Trim(Copy(Line, 1, P - 1)), Trim(Copy(Line, P + 1, MaxInt)));
end;

{ ── TBFHttpRequest / Response ──────────────────────────────────────────── }

constructor TBFHttpRequest.Create(const AMethod, AUrl: string);
begin
  inherited Create;
  Method := AMethod;
  Url := AUrl;
  Headers := TBFHeaders.Create;
  Body := TMemoryStream.Create;
  TimeoutMs := BF_TIMEOUT_MS;
end;

destructor TBFHttpRequest.Destroy;
begin
  Headers.Free;
  Body.Free;
  inherited Destroy;
end;

procedure TBFHttpRequest.SetBodyRaw(const R: TBFRaw);
begin
  Body.Clear;
  BFRawToStream(R, Body);
  Body.Position := 0;
end;

function TBFHttpRequest.BodyRaw: TBFRaw;
begin
  Result := BFRawFromStream(Body);
  Body.Position := 0;
end;

constructor TBFHttpResponse.Create;
begin
  inherited Create;
  Headers := TBFHeaders.Create;
  Body := TMemoryStream.Create;
end;

destructor TBFHttpResponse.Destroy;
begin
  Headers.Free;
  Body.Free;
  inherited Destroy;
end;

procedure TBFHttpResponse.Reset;
begin
  Status := 0;
  StatusText := '';
  Headers.Clear;
  Body.Clear;
  Error := neNone;
  ErrorMessage := '';
end;

function TBFHttpResponse.BodyRaw: TBFRaw;
begin
  Result := BFRawFromStream(Body);
end;

{ ── multipart ──────────────────────────────────────────────────────────── }

constructor TBFMultipart.Create;
var
  I: Integer;
begin
  inherited Create;
  FBody := TMemoryStream.Create;
  Randomize;
  FBoundary := '----bFocusWidgetBoundary';
  for I := 1 to 16 do
    FBoundary := FBoundary + IntToHex(Random(16), 1);
end;

destructor TBFMultipart.Destroy;
begin
  FBody.Free;
  inherited Destroy;
end;

procedure TBFMultipart.WriteRaw(const R: TBFRaw);
begin
  BFRawToStream(R, FBody);
end;

{ Nome do arquivo no cabeçalho da parte: UTF-8 cru (como os navegadores enviam), sem
  aspas nem quebras de linha que quebrariam o cabeçalho. }
function SafeFileName(const FileName: string): TBFRaw;
var
  R: TBFRaw;
  I: Integer;
begin
  R := BFToUtf8(ExtractFileName(FileName));
  Result := '';
  for I := 1 to Length(R) do
    case R[I] of
      '"': Result := Result + '%22';
      #13, #10: Result := Result + ' ';
    else
      Result := Result + R[I];
    end;
  if Result = '' then
    Result := 'arquivo';
end;

procedure TBFMultipart.AddFile(const Field, FileName, ContentType: string; Data: TStream);
var
  Mime: string;
begin
  Mime := ContentType;
  if Mime = '' then
    Mime := BFGuessMime(FileName);
  WriteRaw(BFToUtf8('--' + FBoundary) + #13#10);
  WriteRaw(BFToUtf8('Content-Disposition: form-data; name="' + Field + '"; filename="') +
    SafeFileName(FileName) + '"'#13#10);
  WriteRaw(BFToUtf8('Content-Type: ' + Mime) + #13#10#13#10);
  Data.Position := 0;
  if Data.Size > 0 then
    FBody.CopyFrom(Data, Data.Size);
  WriteRaw(#13#10);
end;

procedure TBFMultipart.AddField(const Field, Value: string);
begin
  WriteRaw(BFToUtf8('--' + FBoundary) + #13#10);
  WriteRaw(BFToUtf8('Content-Disposition: form-data; name="' + Field + '"') + #13#10#13#10);
  WriteRaw(BFToUtf8(Value) + #13#10);
end;

function TBFMultipart.ContentType: string;
begin
  Result := 'multipart/form-data; boundary=' + FBoundary;
end;

procedure TBFMultipart.Finish(Dest: TStream);
begin
  WriteRaw(BFToUtf8('--' + FBoundary + '--') + #13#10);
  FBody.Position := 0;
  Dest.CopyFrom(FBody, FBody.Size);
  Dest.Position := 0;
end;

function BFGuessMime(const FileName: string): string;
var
  Ext: string;
begin
  Ext := BFLowerAscii(ExtractFileExt(FileName));
  if Ext = '.png' then Result := 'image/png'
  else if (Ext = '.jpg') or (Ext = '.jpeg') then Result := 'image/jpeg'
  else if Ext = '.gif' then Result := 'image/gif'
  else if Ext = '.webp' then Result := 'image/webp'
  else if Ext = '.pdf' then Result := 'application/pdf'
  else if Ext = '.txt' then Result := 'text/plain'
  else if Ext = '.csv' then Result := 'text/csv'
  else if Ext = '.zip' then Result := 'application/zip'
  else if Ext = '.doc' then Result := 'application/msword'
  else if Ext = '.docx' then
    Result := 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
  else if Ext = '.xls' then Result := 'application/vnd.ms-excel'
  else if Ext = '.xlsx' then
    Result := 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
  else Result := 'application/octet-stream';
end;

end.
