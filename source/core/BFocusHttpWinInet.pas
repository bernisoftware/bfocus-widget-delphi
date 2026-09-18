unit BFocusHttpWinInet;

{ Transporte HTTP via WinInet (Windows): Delphi 7 até 10.3 e Lazarus/FPC no Windows.
  Usa as funções ANSI declaradas aqui mesmo (URL, host e cabeçalhos do widget são ASCII:
  a identidade vai em base64), o que evita diferenças entre o WinInet.pas do Delphi 7, do
  Delphi Unicode e do FPC. HTTPS usa o Schannel do Windows, sem DLL extra. }

{$I BFocusDefines.inc}

interface

uses
  SysUtils, Classes, BFocusHttp;

type
  TBFWinInetHttp = class(TInterfacedObject, IBFocusHttp)
  public
    procedure Execute(Request: TBFHttpRequest; Response: TBFHttpResponse);
  end;

implementation

uses
  Windows, BFocusText, BFocusConfig;

type
  HINTERNET = Pointer;

const
  WININET_DLL = 'wininet.dll';
  INTERNET_OPEN_TYPE_PRECONFIG = 0;
  INTERNET_SERVICE_HTTP = 3;
  INTERNET_FLAG_RELOAD = $80000000;
  INTERNET_FLAG_SECURE = $00800000;
  INTERNET_FLAG_NO_CACHE_WRITE = $04000000;
  INTERNET_FLAG_NO_COOKIES = $00080000;
  INTERNET_FLAG_NO_UI = $00000200;
  INTERNET_FLAG_PRAGMA_NOCACHE = $00000100;
  INTERNET_OPTION_CONNECT_TIMEOUT = 2;
  INTERNET_OPTION_SEND_TIMEOUT = 5;
  INTERNET_OPTION_RECEIVE_TIMEOUT = 6;
  HTTP_QUERY_STATUS_CODE = 19;
  HTTP_QUERY_STATUS_TEXT = 20;
  HTTP_QUERY_RAW_HEADERS_CRLF = 22;
  HTTP_QUERY_FLAG_NUMBER = $20000000;
  ERROR_INTERNET_TIMEOUT = 12002;

function InternetOpenA(lpszAgent: PAnsiChar; dwAccessType: DWORD; lpszProxy,
  lpszProxyBypass: PAnsiChar; dwFlags: DWORD): HINTERNET; stdcall; external WININET_DLL;
function InternetConnectA(hInet: HINTERNET; lpszServerName: PAnsiChar; nServerPort: Word;
  lpszUserName, lpszPassword: PAnsiChar; dwService, dwFlags: DWORD;
  dwContext: Pointer): HINTERNET; stdcall; external WININET_DLL;
function HttpOpenRequestA(hConnect: HINTERNET; lpszVerb, lpszObjectName, lpszVersion,
  lpszReferrer: PAnsiChar; lplpszAcceptTypes: Pointer; dwFlags: DWORD;
  dwContext: Pointer): HINTERNET; stdcall; external WININET_DLL;
function HttpSendRequestA(hRequest: HINTERNET; lpszHeaders: PAnsiChar; dwHeadersLength: DWORD;
  lpOptional: Pointer; dwOptionalLength: DWORD): BOOL; stdcall; external WININET_DLL;
function HttpQueryInfoA(hRequest: HINTERNET; dwInfoLevel: DWORD; lpBuffer: Pointer;
  var lpdwBufferLength: DWORD; var lpdwIndex: DWORD): BOOL; stdcall; external WININET_DLL;
function InternetReadFile(hFile: HINTERNET; lpBuffer: Pointer; dwNumberOfBytesToRead: DWORD;
  var lpdwNumberOfBytesRead: DWORD): BOOL; stdcall; external WININET_DLL;
function InternetSetOptionA(hInet: HINTERNET; dwOption: DWORD; lpBuffer: Pointer;
  dwBufferLength: DWORD): BOOL; stdcall; external WININET_DLL;
function InternetCloseHandle(hInet: HINTERNET): BOOL; stdcall; external WININET_DLL;

procedure SplitUrl(const Url: string; out Secure: Boolean; out Host: AnsiString;
  out Port: Word; out Path: AnsiString);
var
  Rest, HostPort: string;
  P, I: Integer;
begin
  Secure := BFUrlScheme(Url) = 'https';
  P := Pos('://', Url);
  Rest := Copy(Url, P + 3, MaxInt);
  I := 1;
  while (I <= Length(Rest)) and (Rest[I] <> '/') and (Rest[I] <> '?') do
    Inc(I);
  HostPort := Copy(Rest, 1, I - 1);
  Path := AnsiString(Copy(Rest, I, MaxInt));
  // O fragmento nunca vai para o servidor.
  P := Pos('#', string(Path));
  if P > 0 then
    Path := Copy(Path, 1, P - 1);
  if Path = '' then
    Path := '/'
  else if Path[1] = '?' then
    Path := '/' + Path;
  P := Pos('@', HostPort);
  if P > 0 then
    HostPort := Copy(HostPort, P + 1, MaxInt);
  P := Pos(':', HostPort);
  if (P > 0) and (Pos(']', HostPort) < P) then
  begin
    Port := StrToIntDef(Copy(HostPort, P + 1, MaxInt), 0);
    HostPort := Copy(HostPort, 1, P - 1);
  end
  else if Secure then
    Port := 443
  else
    Port := 80;
  Host := AnsiString(HostPort);
end;

procedure Fail(Response: TBFHttpResponse; Code: DWORD);
begin
  if Code = ERROR_INTERNET_TIMEOUT then
    Response.Error := neTimeout
  else
    Response.Error := neNetwork;
  Response.ErrorMessage := 'WinInet ' + IntToStr(Code);
  Response.Status := 0;
end;

procedure TBFWinInetHttp.Execute(Request: TBFHttpRequest; Response: TBFHttpResponse);
var
  Session, Connection, Req: HINTERNET;
  Secure: Boolean;
  Host, Path, Headers, Agent, Method: AnsiString;
  Port: Word;
  Flags, Timeout, Code, Len, Idx, Got: DWORD;
  Buf: array[0..16383] of Byte;
  Raw: AnsiString;
  Lines: TStringList;
  I: Integer;
begin
  Response.Reset;
  SplitUrl(Request.Url, Secure, Host, Port, Path);
  Agent := AnsiString('bFocusWidget/' + BF_PACKAGE_VERSION);
  Session := InternetOpenA(PAnsiChar(Agent), INTERNET_OPEN_TYPE_PRECONFIG, nil, nil, 0);
  if Session = nil then
  begin
    Fail(Response, GetLastError);
    Exit;
  end;
  Connection := nil;
  Req := nil;
  try
    Timeout := DWORD(Request.TimeoutMs);
    InternetSetOptionA(Session, INTERNET_OPTION_CONNECT_TIMEOUT, @Timeout, SizeOf(Timeout));
    InternetSetOptionA(Session, INTERNET_OPTION_SEND_TIMEOUT, @Timeout, SizeOf(Timeout));
    InternetSetOptionA(Session, INTERNET_OPTION_RECEIVE_TIMEOUT, @Timeout, SizeOf(Timeout));
    Connection := InternetConnectA(Session, PAnsiChar(Host), Port, nil, nil,
      INTERNET_SERVICE_HTTP, 0, nil);
    if Connection = nil then
    begin
      Fail(Response, GetLastError);
      Exit;
    end;
    // Sem cache nem cookies: cada chamada do widget é autenticada sozinha.
    Flags := INTERNET_FLAG_RELOAD or INTERNET_FLAG_NO_CACHE_WRITE or INTERNET_FLAG_NO_COOKIES or
      INTERNET_FLAG_NO_UI or INTERNET_FLAG_PRAGMA_NOCACHE;
    if Secure then
      Flags := Flags or INTERNET_FLAG_SECURE;
    Method := AnsiString(Request.Method);
    Req := HttpOpenRequestA(Connection, PAnsiChar(Method), PAnsiChar(Path), nil, nil, nil,
      Flags, nil);
    if Req = nil then
    begin
      Fail(Response, GetLastError);
      Exit;
    end;
    Headers := '';
    for I := 0 to Request.Headers.Count - 1 do
      Headers := Headers + AnsiString(Request.Headers.Name(I) + ': ' + Request.Headers.Value(I)) +
        #13#10;
    if not HttpSendRequestA(Req, PAnsiChar(Headers), DWORD(Length(Headers)),
      Request.Body.Memory, DWORD(Request.Body.Size)) then
    begin
      Fail(Response, GetLastError);
      Exit;
    end;
    Code := 0;
    Len := SizeOf(Code);
    Idx := 0;
    if HttpQueryInfoA(Req, HTTP_QUERY_STATUS_CODE or HTTP_QUERY_FLAG_NUMBER, @Code, Len, Idx) then
      Response.Status := Integer(Code);
    // Cabeçalhos crus ("Nome: valor" por linha).
    Len := 0;
    Idx := 0;
    HttpQueryInfoA(Req, HTTP_QUERY_RAW_HEADERS_CRLF, nil, Len, Idx);
    if Len > 0 then
    begin
      SetLength(Raw, Len);
      Idx := 0;
      if HttpQueryInfoA(Req, HTTP_QUERY_RAW_HEADERS_CRLF, PAnsiChar(Raw), Len, Idx) then
      begin
        SetLength(Raw, Len);
        Lines := TStringList.Create;
        try
          Lines.Text := string(Raw);
          if Lines.Count > 0 then
            Response.StatusText := Trim(Copy(Lines[0], Pos(' ', Lines[0]) + 4, MaxInt));
          for I := 1 to Lines.Count - 1 do
            Response.Headers.AddLine(Lines[I]);
        finally
          Lines.Free;
        end;
      end;
    end;
    repeat
      Got := 0;
      if not InternetReadFile(Req, @Buf, SizeOf(Buf), Got) then
      begin
        Fail(Response, GetLastError);
        Exit;
      end;
      if Got > 0 then
        Response.Body.WriteBuffer(Buf, Got);
    until Got = 0;
  finally
    if Req <> nil then InternetCloseHandle(Req);
    if Connection <> nil then InternetCloseHandle(Connection);
    InternetCloseHandle(Session);
    Response.Body.Position := 0;
    Request.Body.Position := 0;
  end;
end;

end.
