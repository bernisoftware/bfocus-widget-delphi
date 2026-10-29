unit BFocusApi;

{ Cliente completo da API do widget (/api/v1/widget/*), usado pela UI nativa e pelo
  launcher. Espelha widget/src/embed/api.ts:
  - toda chamada leva os headers de identidade (sem token de sessão);
  - envelope (code, data, message): devolve "data"; erro HTTP levanta EBFocusApiError com
    o código de máquina de "message" (ex.: CHAT_OFFLINE);
  - sem resposta (rede/tempo) levanta EBFocusNetworkError;
  - 15 s por chamada, 120 s no upload; GET tem 1 nova tentativa automática.
  Chamadas síncronas: a UI roda cada uma numa thread (BFocusAsync). O objeto é imutável
  depois de criado, então pode ser usado por várias threads; para trocar identidade,
  crie outro (Clone copia configuração e transporte). }

{$I BFocusDefines.inc}

interface

uses
  SysUtils, Classes, BFocusText, BFocusJson, BFocusHttp, BFocusConfig;

type
  EBFocusError = class(Exception);

  EBFocusApiError = class(EBFocusError)
  private
    FStatus: Integer;
    FCode: string;
    FBody: TBFRaw;
  public
    constructor CreateApi(AStatus: Integer; const AStatusText: string; const ABody: TBFRaw);
    { Reconstrói o erro fora da thread que o recebeu (BFocusAsync). }
    constructor CreateCode(AStatus: Integer; const ACode, AMessage: string);
    property Status: Integer read FStatus;
    { Código de máquina do envelope (message/detail), ex.: WIDGET_USER_HASH_INVALID. }
    property Code: string read FCode;
    property Body: TBFRaw read FBody;
  end;

  EBFocusNetworkError = class(EBFocusError)
  private
    FKind: TBFNetError;
  public
    constructor CreateNet(AKind: TBFNetError; const Msg: string);
    property Kind: TBFNetError read FKind;
  end;

  TBFocusApi = class
  private
    FConfig: TBFocusConfig;
    FHttp: IBFocusHttp;
    FBase: string;
    FRnQs: string;           // ?product=…&audience=…
    FProductQs: string;      // ?product=…
    function NewRequest(const Method, PathAndQuery: string; WithUser, Json: Boolean): TBFHttpRequest;
    function Send(Request: TBFHttpRequest; Retry: Boolean): TBFJson;
    procedure AddProduct(Body: TBFJson);
  public
    constructor Create(Config: TBFocusConfig; Http: IBFocusHttp);
    destructor Destroy; override;
    function Clone: TBFocusApi;

    { Chamada genérica: devolve "data" (dono: quem chama; pode ser nil ou um nó null).
      Body é liberado pela função. }
    function Call(const Method, PathAndQuery: string; Body: TBFJson = nil;
      WithUser: Boolean = True): TBFJson;

    // ── identidade e estado ──
    function GetConfig: TBFJson;
    function Session: TBFJson;
    function LauncherState: TBFJson;
    // ── chamados ──
    function ListTickets: TBFJson;
    { Attachments: array de objetos (url, filename, size?, content_type?) (liberado pela função). }
    function CreateTicket(const TypeName, Title, DescriptionHtml, Priority, DepartmentId: string;
      Attachments: TBFJson): TBFJson;
    function GetTicket(const TicketId: string): TBFJson;
    { Transcrições do chat do chamado; nil quando o servidor não tem a rota (404). }
    function ListTicketConversations(const TicketId: string): TBFJson;
    function AddInteraction(const TicketId, ContentHtml: string; Attachments: TBFJson): TBFJson;
    procedure SubmitSatisfaction(const TicketId: string; Rating: Integer; const Comment: string);
    // ── anexos ──
    function Upload(const FileName: string; Data: TStream; const ContentType: string = ''): TBFJson;
    function UploadFile(const Path: string): TBFJson;
    function DownloadInfo(const AttachmentId: string): TBFJson;
    { Baixa uma URL pré-assinada (sem headers do widget). }
    procedure DownloadTo(const Url: string; Dest: TStream);
    // ── release notes ──
    function ListReleaseNotes: TBFJson;
    procedure MarkReleaseNoteRead(const NoteId: string);
    function ReleaseNotesChangelog: TBFJson;
    function ReleaseNotesPending: TBFJson;
    procedure MarkReleaseNoteSeen(const NoteId: string);
    procedure AcknowledgeReleaseNote(const NoteId: string);
    // ── chat ao vivo ──
    function ChatAvailability: TBFJson;
    { Conversa em andamento ou nil. }
    function ChatActive: TBFJson;
    function ChatCreate(const ContentHtml: string; Attachments: TBFJson;
      const ContinueTicketId: string = ''; const DepartmentId: string = ''): TBFJson;
    function ChatGet(const ConversationId: string): TBFJson;
    function ChatSend(const ConversationId, ContentHtml: string; Attachments: TBFJson): TBFJson;
    function ChatClose(const ConversationId: string): TBFJson;
    { Conversa devolvida no corpo, ou nil. }
    function ChatHandoff(const ConversationId: string): TBFJson;
    function ChatStreamTicket(const ConversationId: string): TBFJson;
    function ChatEvents(const ConversationId: string; After: Int64): TBFJson;
    { URL do SSE (completude; a UI nativa usa o modo poll). }
    function ChatStreamUrl(const Ticket: string; LastEventId: Int64): string;
    // ── push (completude; desktop não usa) ──
    procedure PushRegister(const Token, Platform: string);
    procedure PushUnregister(const Token: string);

    property Config: TBFocusConfig read FConfig;
    property Http: IBFocusHttp read FHttp;
  end;

{ 401 de identidade verificada (HMAC). }
function BFIsIdentityError(E: Exception): Boolean;
{ Código de máquina de um erro da API ('' se não for). }
function BFErrorCode(E: Exception): string;
function BFErrorStatus(E: Exception): Integer;

implementation

uses
  BFocusModels;

{ ── erros ──────────────────────────────────────────────────────────────── }

constructor EBFocusApiError.CreateApi(AStatus: Integer; const AStatusText: string;
  const ABody: TBFRaw);
var
  Root, V: TBFJson;
begin
  FStatus := AStatus;
  FBody := ABody;
  FCode := '';
  Root := TBFJson.TryParse(ABody);
  try
    if (Root <> nil) and Root.IsObject then
    begin
      V := Root.Get('message');
      if (V = nil) or (V.Kind <> jkString) then
        V := Root.Get('detail');
      if (V <> nil) and (V.Kind = jkString) then
        FCode := V.AsString;
    end;
  finally
    Root.Free;
  end;
  inherited CreateFmt('%d %s: %s', [AStatus, AStatusText, BFFromUtf8(Copy(ABody, 1, 500))]);
end;

constructor EBFocusApiError.CreateCode(AStatus: Integer; const ACode, AMessage: string);
begin
  FStatus := AStatus;
  FCode := ACode;
  FBody := '';
  inherited Create(AMessage);
end;

constructor EBFocusNetworkError.CreateNet(AKind: TBFNetError; const Msg: string);
begin
  FKind := AKind;
  if AKind = neTimeout then
    inherited Create('Request timed out')
  else
    inherited Create('Network request failed: ' + Msg);
end;

function BFIsIdentityError(E: Exception): Boolean;
begin
  Result := (E is EBFocusApiError) and (EBFocusApiError(E).Status = 401) and
    ((EBFocusApiError(E).Code = 'WIDGET_USER_HASH_INVALID') or
     (EBFocusApiError(E).Code = 'WIDGET_USER_HASH_EXPIRED') or
     (EBFocusApiError(E).Code = 'WIDGET_VERIFIED_SESSION_REQUIRED'));
end;

function BFErrorCode(E: Exception): string;
begin
  if E is EBFocusApiError then
    Result := EBFocusApiError(E).Code
  else
    Result := '';
end;

function BFErrorStatus(E: Exception): Integer;
begin
  if E is EBFocusApiError then
    Result := EBFocusApiError(E).Status
  else
    Result := 0;
end;

{ ── TBFocusApi ─────────────────────────────────────────────────────────── }

function Qs(const Names, Values: array of string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(Names) do
    if Values[I] <> '' then
    begin
      if Result = '' then Result := '?' else Result := Result + '&';
      Result := Result + Names[I] + '=' + BFUrlEncode(Values[I]);
    end;
end;

constructor TBFocusApi.Create(Config: TBFocusConfig; Http: IBFocusHttp);
begin
  inherited Create;
  // Cópia própria: o integrador pode mexer na configuração dele sem afetar threads.
  FConfig := TBFocusConfig.Create;
  FConfig.Assign(Config);
  FHttp := Http;
  FBase := BFApiBase(FConfig);
  FRnQs := Qs(['product', 'audience'], [FConfig.Product, FConfig.Audience]);
  FProductQs := Qs(['product'], [FConfig.Product]);
end;

destructor TBFocusApi.Destroy;
begin
  FConfig.Free;
  inherited Destroy;
end;

function TBFocusApi.Clone: TBFocusApi;
begin
  Result := TBFocusApi.Create(FConfig, FHttp);
end;

function TBFocusApi.NewRequest(const Method, PathAndQuery: string;
  WithUser, Json: Boolean): TBFHttpRequest;
begin
  Result := TBFHttpRequest.Create(Method, FBase + PathAndQuery);
  BFApplyWidgetHeaders(FConfig, Result, WithUser, Json);
end;

function TBFocusApi.Send(Request: TBFHttpRequest; Retry: Boolean): TBFJson;
var
  Response: TBFHttpResponse;
  Attempts: Integer;
  Raw: TBFRaw;
  Root: TBFJson;
begin
  Result := nil;
  Response := TBFHttpResponse.Create;
  try
    if Retry then Attempts := 2 else Attempts := 1;
    while True do
    begin
      Response.Reset;
      FHttp.Execute(Request, Response);
      Dec(Attempts);
      // Nova tentativa só para falha de rede ou 5xx (4xx é definitivo).
      if (Attempts <= 0) or ((Response.Error = neNone) and (Response.Status < 500)) then
        Break;
    end;
    if Response.Error <> neNone then
      raise EBFocusNetworkError.CreateNet(Response.Error, Response.ErrorMessage);
    Raw := Response.BodyRaw;
    if (Response.Status < 200) or (Response.Status >= 300) then
      raise EBFocusApiError.CreateApi(Response.Status, Response.StatusText, Raw);
    if Trim(string(Raw)) = '' then
      Exit; // 204 / corpo vazio
    Root := TBFJson.TryParse(Raw);
    if Root = nil then
      raise EBFocusError.Create('Resposta invalida da API');
    if Root.IsObject and Root.Has('data') then
    begin
      Result := Root.ExtractKey('data');
      Root.Free;
    end
    else
      Result := Root;
  finally
    Response.Free;
  end;
end;

function TBFocusApi.Call(const Method, PathAndQuery: string; Body: TBFJson;
  WithUser: Boolean): TBFJson;
var
  Req: TBFHttpRequest;
begin
  try
    Req := NewRequest(Method, PathAndQuery, WithUser, True);
    try
      if Body <> nil then
        Req.SetBodyRaw(Body.ToJson)
      else if Method <> 'GET' then
        Req.SetBodyRaw('{}');
      Result := Send(Req, Method = 'GET');
    finally
      Req.Free;
    end;
  finally
    Body.Free;
  end;
end;

procedure TBFocusApi.AddProduct(Body: TBFJson);
begin
  // O produto do init classifica chamados e conversas no servidor.
  if FConfig.Product <> '' then
    Body.PutStr('product_slug', FConfig.Product);
end;

function Seg(const S: string): string;
begin
  Result := BFUrlEncode(S);
end;

function TBFocusApi.GetConfig: TBFJson;
var
  Req: TBFHttpRequest;
begin
  // /config não leva o usuário (é pública do tenant), só chave e origem.
  Req := NewRequest('GET', '/api/v1/widget/config', False, True);
  try
    Result := Send(Req, True);
  finally
    Req.Free;
  end;
end;

function TBFocusApi.Session: TBFJson;
begin
  Result := Call('POST', '/api/v1/widget/session');
end;

function TBFocusApi.LauncherState: TBFJson;
var
  Req: TBFHttpRequest;
begin
  Req := BFLauncherStateRequest(FConfig);
  try
    Result := Send(Req, False);
  finally
    Req.Free;
  end;
end;

function TBFocusApi.ListTickets: TBFJson;
begin
  Result := Call('GET', '/api/v1/widget/tickets?page_size=50');
end;

function TBFocusApi.CreateTicket(const TypeName, Title, DescriptionHtml, Priority,
  DepartmentId: string; Attachments: TBFJson): TBFJson;
var
  Body: TBFJson;
begin
  Body := TBFJson.NewObject;
  Body.PutStr('type', TypeName);
  Body.PutStr('title', Title);
  if DescriptionHtml <> '' then
    Body.PutStr('description', DescriptionHtml);
  Body.PutStr('priority', Priority);
  if DepartmentId <> '' then
    Body.PutStr('department_id', DepartmentId);
  if Attachments <> nil then
    Body.Put('attachments', Attachments)
  else
    Body.Put('attachments', TBFJson.NewArray);
  AddProduct(Body);
  Result := Call('POST', '/api/v1/widget/tickets', Body);
end;

function TBFocusApi.GetTicket(const TicketId: string): TBFJson;
begin
  Result := Call('GET', '/api/v1/widget/tickets/' + Seg(TicketId));
end;

function TBFocusApi.ListTicketConversations(const TicketId: string): TBFJson;
var
  Wrapped: TBFJson;
begin
  try
    Result := Call('GET', '/api/v1/widget/tickets/' + Seg(TicketId) + '/conversations');
  except
    on E: EBFocusApiError do
      if E.Status = 404 then
      begin
        Result := nil;
        Exit;
      end
      else
        raise;
  end;
  if (Result <> nil) and Result.IsObject then
  begin
    // Tolera {conversations: [...]}.
    Wrapped := Result.ExtractKey('conversations');
    Result.Free;
    if (Wrapped <> nil) and Wrapped.IsArray then
      Result := Wrapped
    else
    begin
      Wrapped.Free;
      Result := TBFJson.NewArray;
    end;
  end
  else if (Result = nil) or not Result.IsArray then
  begin
    Result.Free;
    Result := TBFJson.NewArray;
  end;
end;

function TBFocusApi.AddInteraction(const TicketId, ContentHtml: string;
  Attachments: TBFJson): TBFJson;
var
  Body: TBFJson;
begin
  Body := TBFJson.NewObject;
  Body.PutStr('content', ContentHtml);
  if Attachments <> nil then
    Body.Put('attachments', Attachments)
  else
    Body.Put('attachments', TBFJson.NewArray);
  Result := Call('POST', '/api/v1/widget/tickets/' + Seg(TicketId) + '/interactions', Body);
end;

procedure TBFocusApi.SubmitSatisfaction(const TicketId: string; Rating: Integer;
  const Comment: string);
var
  Body: TBFJson;
begin
  Body := TBFJson.NewObject;
  Body.PutInt('rating', Rating);
  if Trim(Comment) <> '' then
    Body.PutStr('comment', Trim(Comment))
  else
    Body.PutNull('comment');
  Call('POST', '/api/v1/widget/tickets/' + Seg(TicketId) + '/satisfaction', Body).Free;
end;

function TBFocusApi.Upload(const FileName: string; Data: TStream;
  const ContentType: string): TBFJson;
var
  Req: TBFHttpRequest;
  Parts: TBFMultipart;
begin
  // Multipart: sem Content-Type JSON; o tipo com boundary vem do corpo.
  Req := NewRequest('POST', '/api/v1/widget/upload', True, False);
  Parts := TBFMultipart.Create;
  try
    Parts.AddFile('file', FileName, ContentType, Data);
    Parts.Finish(Req.Body);
    Req.Headers.SetValue('Content-Type', Parts.ContentType);
    Req.TimeoutMs := BF_UPLOAD_TIMEOUT_MS;
    Result := Send(Req, False);
  finally
    Parts.Free;
    Req.Free;
  end;
end;

function TBFocusApi.UploadFile(const Path: string): TBFJson;
var
  F: TFileStream;
begin
  F := TFileStream.Create(Path, fmOpenRead or fmShareDenyWrite);
  try
    Result := Upload(ExtractFileName(Path), F, BFGuessMime(Path));
  finally
    F.Free;
  end;
end;

function TBFocusApi.DownloadInfo(const AttachmentId: string): TBFJson;
begin
  Result := Call('GET', '/api/v1/widget/attachments/' + Seg(AttachmentId) + '/download');
end;

procedure TBFocusApi.DownloadTo(const Url: string; Dest: TStream);
var
  Req: TBFHttpRequest;
  Resp: TBFHttpResponse;
begin
  if not BFUrlAllowed(Url) then
    raise EBFocusError.Create('URL de download recusada');
  Req := TBFHttpRequest.Create('GET', Url);
  Resp := TBFHttpResponse.Create;
  try
    Req.TimeoutMs := BF_UPLOAD_TIMEOUT_MS;
    FHttp.Execute(Req, Resp);
    if Resp.Error <> neNone then
      raise EBFocusNetworkError.CreateNet(Resp.Error, Resp.ErrorMessage);
    if (Resp.Status < 200) or (Resp.Status >= 300) then
      raise EBFocusApiError.CreateApi(Resp.Status, Resp.StatusText, '');
    Resp.Body.Position := 0;
    Dest.CopyFrom(Resp.Body, Resp.Body.Size);
  finally
    Resp.Free;
    Req.Free;
  end;
end;

function TBFocusApi.ListReleaseNotes: TBFJson;
begin
  // Splash dos chamados, por usuário: o product declarado cria o vínculo cliente↔produto
  // (sem ele, vale o único produto ativo da empresa) e o audience filtra o público.
  Result := Call('GET', '/api/v1/widget/release-notes' + FRnQs);
end;

procedure TBFocusApi.MarkReleaseNoteRead(const NoteId: string);
begin
  Call('POST', '/api/v1/widget/release-notes/' + Seg(NoteId) + '/mark-read').Free;
end;

function TBFocusApi.ReleaseNotesChangelog: TBFJson;
begin
  Result := Call('GET', '/api/v1/widget/release-notes/changelog' + FRnQs);
end;

function TBFocusApi.ReleaseNotesPending: TBFJson;
begin
  Result := Call('GET', '/api/v1/widget/release-notes/pending' + FRnQs);
end;

procedure TBFocusApi.MarkReleaseNoteSeen(const NoteId: string);
begin
  Call('POST', '/api/v1/widget/release-notes/' + Seg(NoteId) + '/seen').Free;
end;

procedure TBFocusApi.AcknowledgeReleaseNote(const NoteId: string);
begin
  Call('POST', '/api/v1/widget/release-notes/' + Seg(NoteId) + '/acknowledge').Free;
end;

function TBFocusApi.ChatAvailability: TBFJson;
begin
  Result := Call('GET', '/api/v1/widget/chat/availability' + FProductQs);
end;

function TBFocusApi.ChatActive: TBFJson;
begin
  Result := Call('GET', '/api/v1/widget/chat/conversations/active');
  if (Result <> nil) and not Result.IsObject then
    FreeAndNil(Result);
end;

function TBFocusApi.ChatCreate(const ContentHtml: string; Attachments: TBFJson;
  const ContinueTicketId, DepartmentId: string): TBFJson;
var
  Body: TBFJson;
begin
  Body := TBFJson.NewObject;
  Body.PutStr('content', ContentHtml);
  if Attachments <> nil then
    Body.Put('attachments', Attachments)
  else
    Body.Put('attachments', TBFJson.NewArray);
  if DepartmentId <> '' then
    Body.PutStr('department_id', DepartmentId);
  Body.PutNull('origin_url');
  if ContinueTicketId <> '' then
    Body.PutStr('continue_ticket_id', ContinueTicketId)
  else
    Body.PutNull('continue_ticket_id');
  AddProduct(Body);
  Result := Call('POST', '/api/v1/widget/chat/conversations', Body);
end;

function TBFocusApi.ChatGet(const ConversationId: string): TBFJson;
begin
  Result := Call('GET', '/api/v1/widget/chat/conversations/' + Seg(ConversationId));
end;

function TBFocusApi.ChatSend(const ConversationId, ContentHtml: string;
  Attachments: TBFJson): TBFJson;
var
  Body: TBFJson;
begin
  Body := TBFJson.NewObject;
  Body.PutStr('content', ContentHtml);
  if Attachments <> nil then
    Body.Put('attachments', Attachments)
  else
    Body.Put('attachments', TBFJson.NewArray);
  Result := Call('POST', '/api/v1/widget/chat/conversations/' + Seg(ConversationId) +
    '/messages', Body);
end;

function TBFocusApi.ChatClose(const ConversationId: string): TBFJson;
begin
  Result := Call('POST', '/api/v1/widget/chat/conversations/' + Seg(ConversationId) + '/close');
end;

function TBFocusApi.ChatHandoff(const ConversationId: string): TBFJson;
var
  Res, Conv: TBFJson;
begin
  Result := nil;
  Res := Call('POST', '/api/v1/widget/chat/conversations/' + Seg(ConversationId) + '/handoff');
  try
    if (Res = nil) or not Res.IsObject then
      Exit;
    Conv := Res.ObjOf('conversation');
    if (Conv <> nil) and (Conv.StrOf('id') <> '') then
      Result := Res.ExtractKey('conversation')
    else if (Res.StrOf('id') <> '') and (Res.StrOf('status') <> '') then
    begin
      Result := Res;
      Res := nil;
    end;
  finally
    Res.Free;
  end;
end;

function TBFocusApi.ChatStreamTicket(const ConversationId: string): TBFJson;
var
  Body: TBFJson;
begin
  Body := TBFJson.NewObject;
  Body.PutStr('conversation_id', ConversationId);
  Result := Call('POST', '/api/v1/widget/chat/stream-ticket', Body);
end;

function TBFocusApi.ChatEvents(const ConversationId: string; After: Int64): TBFJson;
begin
  if After < 0 then
    After := 0;
  Result := Call('GET', '/api/v1/widget/chat/conversations/' + Seg(ConversationId) +
    '/events?after=' + IntToStr(After));
end;

function TBFocusApi.ChatStreamUrl(const Ticket: string; LastEventId: Int64): string;
begin
  // O ticket (opaco, uso único) vai na query; a identidade nunca vai na URL.
  Result := FBase + '/api/v1/stream?ticket=' + BFUrlEncode(Ticket);
  if LastEventId >= 0 then
    Result := Result + '&last_event_id=' + IntToStr(LastEventId);
end;

procedure TBFocusApi.PushRegister(const Token, Platform: string);
var
  Req: TBFHttpRequest;
begin
  Req := BFPushRegisterRequest(FConfig, Token, Platform);
  try
    Send(Req, False).Free;
  finally
    Req.Free;
  end;
end;

procedure TBFocusApi.PushUnregister(const Token: string);
var
  Req: TBFHttpRequest;
begin
  Req := BFPushUnregisterRequest(FConfig, Token);
  try
    Send(Req, False).Free;
  finally
    Req.Free;
  end;
end;

end.
