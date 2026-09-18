unit BFocusVMTickets;

{ View-models dos chamados (behavior spec §3), sem UI: leitura local ("não lido"), lista,
  novo chamado e detalhe. As telas VCL/LCL só desenham o que estes objetos dizem; os
  testes rodam a mesma lógica com dados fixos. Métodos Apply* recebem o "data" da API e
  passam a ser donos dele. }

{$I BFocusDefines.inc}

interface

uses
  SysUtils, Classes, BFocusText, BFocusJson, BFocusStorage, BFocusFormat, BFocusI18n,
  BFocusTokens;

const
  BF_TITLE_MAX = 500;
  BF_PRIORITIES: array[0..3] of string = ('low', 'medium', 'high', 'critical');

type
  { Leitura local por chamado (readState.ts): chave bf:read:<escopo>:<id> = ms Unix. }
  TBFReadState = class
  private
    FStorage: IBFocusStorage;
    FScope: string;
    function KeyOf(const TicketId: string): string;
  public
    constructor Create(Storage: IBFocusStorage; const Scope: string);
    function LastRead(const TicketId: string): Int64;
    procedure MarkRead(const TicketId, AtIso: string);
    { Não lido: last_event_at maior que a última leitura. Nunca aberto: só quando
      last_event_at passa 1 s de created_at. }
    function IsUnread(const TicketId, LastEventAt, CreatedAt: string): Boolean;
    property Scope: string read FScope;
  end;

  TBFTicketListVM = class
  private
    FReadState: TBFReadState;
    FLocale: string;
    FTickets: TBFJson;
  public
    Loading: Boolean;
    Failed: Boolean;
    constructor Create(ReadState: TBFReadState; const Locale: string);
    destructor Destroy; override;
    procedure ApplyList(Data: TBFJson);
    procedure ApplyError;
    function Loaded: Boolean;
    function Count: Integer;
    function Ticket(I: Integer): TBFJson;
    function IsUnread(I: Integer): Boolean;
    function UnreadCount: Integer;
    function StatusText(I: Integer): string;
    function StatusColor(I: Integer): string;
    function DateText(I: Integer): string;
    function IsEmpty: Boolean;
  end;

  TBFNewTicketVM = class
  private
    FConfig: TBFJson;    // /config (não é dono)
    FLocale: string;
    FUploads: TBFJson;
    FTitle: string;
    procedure SetTitle(const Value: string);
  public
    TypeName: string;
    Priority: string;
    DepartmentId: string;
    DescriptionHtml: string;
    Notice: string;        // aviso do pré-preenchimento (chat offline)
    Submitting: Boolean;
    Uploading: Boolean;
    SubmitFailed: Boolean;
    UploadError: string;
    constructor Create(WidgetConfig: TBFJson; const Locale: string);
    destructor Destroy; override;
    function TypeCount: Integer;
    function TypeAt(I: Integer): string;
    function TypeLabel(const T: string): string;
    function PriorityLabel(const P: string): string;
    function PriorityColor(const P: string): string;
    function ShowDepartments: Boolean;
    function DepartmentCount: Integer;
    function DepartmentId_(I: Integer): string;
    function DepartmentName(I: Integer): string;
    function CanSubmit: Boolean;
    { Pré-preenche (chat caiu para offline). Attachments é copiado. }
    procedure ApplyPrefill(const Html: string; Attachments: TBFJson; const ANotice: string);
    { Resposta do /upload (url, filename, size, mime) → anexo do chamado. Dono: a função. }
    procedure ApplyUpload(Res: TBFJson);
    procedure RemoveUpload(I: Integer);
    function UploadCount: Integer;
    function Upload(I: Integer): TBFJson;
    { Cópia dos anexos para o corpo do POST (quem recebe é dono). }
    function AttachmentsForSend: TBFJson;
    function DescriptionForSend: string;
    property Title: string read FTitle write SetTitle;
  end;

  TBFBubble = record
    Author: string;
    Html: TBFRaw;          // HTML sanitizado do servidor, em UTF-8
    IsStaff: Boolean;
    Timestamp: string;
    Attachments: TBFJson;  // array (referência; dono é o VM)
  end;
  TBFBubbles = array of TBFBubble;

  TBFTicketDetailVM = class
  private
    FReadState: TBFReadState;
    FLocale: string;
    FTicketId: string;
    FData: TBFJson;          // {ticket, interactions, attachments}
    FConversations: TBFJson; // array (mais nova primeiro) ou nil = servidor sem a rota
    FExpanded: TStringList;
  public
    Loading: Boolean;
    Failed: Boolean;
    ConversationsFailed: Boolean;
    Sending: Boolean;
    SendFailed: Boolean;
    constructor Create(ReadState: TBFReadState; const Locale, TicketId: string);
    destructor Destroy; override;
    procedure ApplyTicket(Data: TBFJson);
    procedure ApplyConversations(Data: TBFJson);
    { 409 TICKET_CLOSED na resposta: recarregar para trocar a caixa pelo aviso. }
    function NeedsReloadAfterSendError(Status: Integer): Boolean;
    function Loaded: Boolean;
    function Ticket: TBFJson;
    function Status: string;
    function StatusText: string;
    function StatusColor: string;
    function IsClosed: Boolean;
    function IsResolved: Boolean;
    function ReopenHint: string;
    function ClosedNotice: string;
    function PreviousId: string;
    function ContinuationText: string;
    { Descrição inicial ("Você") e interações públicas. }
    function Bubbles: TBFBubbles;
    function ShowNoMessages: Boolean;
    function HasChat: Boolean;
    function HasLiveConversation: Boolean;
    function ConversationCount: Integer;
    function Conversation(I: Integer): TBFJson;
    function ConversationTitle(I: Integer): string;
    function ConversationSubtitle(I: Integer): string;
    { Mensagens da transcrição em ordem cronológica. }
    function TranscriptBubbles(I: Integer): TBFBubbles;
    function IsExpanded(I: Integer): Boolean;
    procedure ToggleExpanded(I: Integer);
    function ShowInteractionsTitle: Boolean;
    { Evento mais recente visto nesta tela (interações + chat) → marca como lido. }
    function LastEventAt: string;
    procedure MarkRead;
    function CanSend(const DraftHtml: string; PendingCount: Integer): Boolean;
    property TicketId: string read FTicketId;
  end;

function BFTicketStatusColor(const Status: string): string;
function BFTicketStatusText(const Locale, Status: string): string;

implementation

uses
  BFocusModels;

const
  MUTED = '#64748b';

function BFTicketStatusColor(const Status: string): string;
begin
  Result := BFTokenColor('ticketStatus', Status, MUTED);
end;

function BFTicketStatusText(const Locale, Status: string): string;
begin
  Result := BFT(Locale, 'status_' + Status);
end;

{ ── leitura local ──────────────────────────────────────────────────────── }

constructor TBFReadState.Create(Storage: IBFocusStorage; const Scope: string);
begin
  inherited Create;
  FStorage := Storage;
  FScope := Scope;
end;

function TBFReadState.KeyOf(const TicketId: string): string;
begin
  Result := 'bf:read:' + FScope + ':' + TicketId;
end;

function TBFReadState.LastRead(const TicketId: string): Int64;
begin
  if FStorage = nil then
    Result := 0
  else
    Result := StrToInt64Def(FStorage.ReadValue(KeyOf(TicketId)), 0);
end;

procedure TBFReadState.MarkRead(const TicketId, AtIso: string);
var
  Ms: Int64;
begin
  if (FStorage = nil) or (AtIso = '') or not BFIsoToUnixMs(AtIso, Ms) then
    Exit;
  FStorage.WriteValue(KeyOf(TicketId), IntToStr(Ms));
end;

function TBFReadState.IsUnread(const TicketId, LastEventAt, CreatedAt: string): Boolean;
var
  LastMs, Seen, CreatedMs: Int64;
begin
  Result := False;
  if (LastEventAt = '') or not BFIsoToUnixMs(LastEventAt, LastMs) then
    Exit;
  Seen := LastRead(TicketId);
  if Seen > 0 then
  begin
    Result := LastMs > Seen;
    Exit;
  end;
  if (CreatedAt = '') or not BFIsoToUnixMs(CreatedAt, CreatedMs) then
    Exit;
  Result := LastMs > CreatedMs + 1000; // 1 s de folga sobre a criação
end;

{ ── lista ──────────────────────────────────────────────────────────────── }

constructor TBFTicketListVM.Create(ReadState: TBFReadState; const Locale: string);
begin
  inherited Create;
  FReadState := ReadState;
  FLocale := Locale;
  Loading := True;
end;

destructor TBFTicketListVM.Destroy;
begin
  FTickets.Free;
  inherited Destroy;
end;

procedure TBFTicketListVM.ApplyList(Data: TBFJson);
begin
  FTickets.Free;
  if (Data <> nil) and Data.IsArray then
    FTickets := Data
  else
  begin
    Data.Free;
    FTickets := TBFJson.NewArray;
  end;
  Loading := False;
  Failed := False;
end;

procedure TBFTicketListVM.ApplyError;
begin
  Loading := False;
  // Com dados já na tela, a falha de uma atualização não apaga a lista.
  Failed := FTickets = nil;
end;

function TBFTicketListVM.Loaded: Boolean;
begin
  Result := FTickets <> nil;
end;

function TBFTicketListVM.Count: Integer;
begin
  if FTickets = nil then Result := 0 else Result := FTickets.Count;
end;

function TBFTicketListVM.Ticket(I: Integer): TBFJson;
begin
  Result := FTickets.Item(I);
end;

function TBFTicketListVM.IsUnread(I: Integer): Boolean;
var
  T: TBFJson;
begin
  T := Ticket(I);
  Result := FReadState.IsUnread(T.StrOf('id'), T.StrOf('last_event_at'), T.StrOf('created_at'));
end;

function TBFTicketListVM.UnreadCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to Count - 1 do
    if IsUnread(I) then
      Inc(Result);
end;

function TBFTicketListVM.StatusText(I: Integer): string;
begin
  Result := BFTicketStatusText(FLocale, Ticket(I).StrOf('status'));
end;

function TBFTicketListVM.StatusColor(I: Integer): string;
begin
  Result := BFTicketStatusColor(Ticket(I).StrOf('status'));
end;

function TBFTicketListVM.DateText(I: Integer): string;
var
  T: TBFJson;
begin
  T := Ticket(I);
  Result := BFFormatDateTime(T.StrOf('last_event_at', T.StrOf('updated_at')));
end;

function TBFTicketListVM.IsEmpty: Boolean;
begin
  Result := Loaded and (Count = 0);
end;

{ ── novo chamado ───────────────────────────────────────────────────────── }

constructor TBFNewTicketVM.Create(WidgetConfig: TBFJson; const Locale: string);
var
  Defaults: TBFJson;
begin
  inherited Create;
  FConfig := WidgetConfig;
  FLocale := Locale;
  FUploads := TBFJson.NewArray;
  Priority := 'medium';
  TypeName := 'support';
  if FConfig <> nil then
  begin
    Defaults := FConfig.ObjOf('defaults');
    if Defaults <> nil then
    begin
      if Defaults.StrOf('type') <> '' then
        TypeName := Defaults.StrOf('type');
      DepartmentId := Defaults.StrOf('department_id');
    end;
  end;
end;

destructor TBFNewTicketVM.Destroy;
begin
  FUploads.Free;
  inherited Destroy;
end;

procedure TBFNewTicketVM.SetTitle(const Value: string);
begin
  // Mesmo limite do input do web (maxLength=500).
  FTitle := Copy(Value, 1, BF_TITLE_MAX);
end;

function TBFNewTicketVM.TypeCount: Integer;
var
  A: TBFJson;
begin
  Result := 0;
  if FConfig <> nil then
  begin
    A := FConfig.ArrOf('types');
    if A <> nil then
      Result := A.Count;
  end;
end;

function TBFNewTicketVM.TypeAt(I: Integer): string;
begin
  Result := FConfig.ArrOf('types').Item(I).AsString;
end;

function TBFNewTicketVM.TypeLabel(const T: string): string;
begin
  Result := BFT(FLocale, 'type_' + T);
end;

function TBFNewTicketVM.PriorityLabel(const P: string): string;
begin
  Result := BFT(FLocale, 'priority_' + P);
end;

function TBFNewTicketVM.PriorityColor(const P: string): string;
begin
  Result := BFTokenColor('priority', P, MUTED);
end;

function TBFNewTicketVM.DepartmentCount: Integer;
var
  A: TBFJson;
begin
  Result := 0;
  if FConfig <> nil then
  begin
    A := FConfig.ArrOf('departments');
    if A <> nil then
      Result := A.Count;
  end;
end;

function TBFNewTicketVM.ShowDepartments: Boolean;
begin
  // Só quando há o que escolher (mais de um departamento).
  Result := DepartmentCount > 1;
end;

function TBFNewTicketVM.DepartmentId_(I: Integer): string;
begin
  Result := FConfig.ArrOf('departments').Item(I).StrOf('id');
end;

function TBFNewTicketVM.DepartmentName(I: Integer): string;
begin
  Result := FConfig.ArrOf('departments').Item(I).StrOf('name');
end;

function TBFNewTicketVM.CanSubmit: Boolean;
begin
  Result := (Trim(FTitle) <> '') and not Submitting and not Uploading;
end;

procedure TBFNewTicketVM.ApplyPrefill(const Html: string; Attachments: TBFJson;
  const ANotice: string);
var
  I: Integer;
begin
  DescriptionHtml := Html;
  Notice := ANotice;
  if Attachments <> nil then
    for I := 0 to Attachments.Count - 1 do
      FUploads.Add(Attachments.Item(I).Clone);
end;

procedure TBFNewTicketVM.ApplyUpload(Res: TBFJson);
var
  A: TBFJson;
begin
  try
    if (Res = nil) or not Res.IsObject then
      Exit;
    A := FUploads.Add(TBFJson.NewObject);
    A.PutUtf8('url', Res.Utf8Of('url'));
    A.PutUtf8('filename', Res.Utf8Of('filename'));
    A.PutInt('size', Res.IntOf('size'));
    if Res.StrOf('mime') <> '' then
      A.PutUtf8('content_type', Res.Utf8Of('mime'))
    else if Res.StrOf('content_type') <> '' then
      A.PutUtf8('content_type', Res.Utf8Of('content_type'));
  finally
    Res.Free;
  end;
end;

procedure TBFNewTicketVM.RemoveUpload(I: Integer);
begin
  FUploads.Delete(I);
end;

function TBFNewTicketVM.UploadCount: Integer;
begin
  Result := FUploads.Count;
end;

function TBFNewTicketVM.Upload(I: Integer): TBFJson;
begin
  Result := FUploads.Item(I);
end;

function TBFNewTicketVM.AttachmentsForSend: TBFJson;
begin
  Result := FUploads.Clone;
end;

function TBFNewTicketVM.DescriptionForSend: string;
begin
  if BFIsHtmlEmpty(DescriptionHtml) then
    Result := ''
  else
    Result := DescriptionHtml;
end;

{ ── detalhe ────────────────────────────────────────────────────────────── }

constructor TBFTicketDetailVM.Create(ReadState: TBFReadState; const Locale, TicketId: string);
begin
  inherited Create;
  FReadState := ReadState;
  FLocale := Locale;
  FTicketId := TicketId;
  FExpanded := TStringList.Create;
  Loading := True;
end;

destructor TBFTicketDetailVM.Destroy;
begin
  FData.Free;
  FConversations.Free;
  FExpanded.Free;
  inherited Destroy;
end;

procedure TBFTicketDetailVM.ApplyTicket(Data: TBFJson);
begin
  Loading := False;
  if (Data = nil) or not Data.IsObject or (Data.ObjOf('ticket') = nil) then
  begin
    Data.Free;
    Failed := FData = nil;
    Exit;
  end;
  FData.Free;
  FData := Data;
  Failed := False;
end;

procedure TBFTicketDetailVM.ApplyConversations(Data: TBFJson);
begin
  FConversations.Free;
  FConversations := Data; // nil = servidor sem a rota: a seção some
  ConversationsFailed := False;
end;

function TBFTicketDetailVM.NeedsReloadAfterSendError(Status: Integer): Boolean;
begin
  Result := Status = 409;
end;

function TBFTicketDetailVM.Loaded: Boolean;
begin
  Result := FData <> nil;
end;

function TBFTicketDetailVM.Ticket: TBFJson;
begin
  if FData = nil then Result := nil else Result := FData.ObjOf('ticket');
end;

function TBFTicketDetailVM.Status: string;
begin
  if Ticket = nil then Result := '' else Result := Ticket.StrOf('status');
end;

function TBFTicketDetailVM.StatusText: string;
begin
  Result := BFTicketStatusText(FLocale, Status);
end;

function TBFTicketDetailVM.StatusColor: string;
begin
  Result := BFTicketStatusColor(Status);
end;

function TBFTicketDetailVM.IsClosed: Boolean;
begin
  // Fechado/cancelado é final: sem caixa de resposta.
  Result := (Status = 'closed') or (Status = 'cancelled');
end;

function TBFTicketDetailVM.IsResolved: Boolean;
begin
  Result := Status = 'resolved';
end;

function TBFTicketDetailVM.ReopenHint: string;
var
  AutoClose: string;
begin
  Result := '';
  if not IsResolved then
    Exit;
  AutoClose := Ticket.StrOf('auto_close_at');
  if AutoClose <> '' then
    Result := BFFill(BFT(FLocale, 'detail_reopen_hint'), 'date', BFFormatDay(AutoClose))
  else
    Result := BFT(FLocale, 'detail_reopen_hint_nodate');
end;

function TBFTicketDetailVM.ClosedNotice: string;
begin
  if IsClosed then
    Result := BFT(FLocale, 'detail_closed_notice')
  else
    Result := '';
end;

function TBFTicketDetailVM.PreviousId: string;
var
  P: TBFJson;
begin
  Result := '';
  if Ticket = nil then Exit;
  P := Ticket.ObjOf('previous_ticket');
  if P <> nil then
    Result := P.StrOf('id');
end;

function TBFTicketDetailVM.ContinuationText: string;
var
  P: TBFJson;
begin
  Result := '';
  if Ticket = nil then Exit;
  P := Ticket.ObjOf('previous_ticket');
  if P <> nil then
    Result := BFFill(BFT(FLocale, 'detail_continuation_of'), 'n', P.StrOf('ticket_number'));
end;

procedure AddBubble(var B: TBFBubbles; const Author: string; const Html: TBFRaw;
  IsStaff: Boolean; const Timestamp: string; Attachments: TBFJson);
var
  N: Integer;
begin
  N := Length(B);
  SetLength(B, N + 1);
  B[N].Author := Author;
  B[N].Html := Html;
  B[N].IsStaff := IsStaff;
  B[N].Timestamp := Timestamp;
  B[N].Attachments := Attachments;
end;

function TBFTicketDetailVM.Bubbles: TBFBubbles;
var
  T, Atts, Ints, It: TBFJson;
  I: Integer;
  Author: string;
begin
  Result := nil;
  T := Ticket;
  if T = nil then
    Exit;
  Atts := FData.ArrOf('attachments');
  // A descrição inicial é sempre a primeira bolha "Você".
  if (T.StrOf('description') <> '') or ((Atts <> nil) and (Atts.Count > 0)) then
    AddBubble(Result, BFT(FLocale, 'you'), T.Utf8Of('description'), False,
      T.StrOf('created_at'), Atts);
  Ints := FData.ArrOf('interactions');
  if Ints <> nil then
    for I := 0 to Ints.Count - 1 do
    begin
      It := Ints.Item(I);
      if It.BoolOf('author_is_staff') then
        Author := It.StrOf('author_name', BFT(FLocale, 'support_team'))
      else
        Author := BFT(FLocale, 'you');
      if Author = '' then
        Author := BFT(FLocale, 'support_team');
      AddBubble(Result, Author, It.Utf8Of('content'), It.BoolOf('author_is_staff'),
        It.StrOf('created_at'), It.ArrOf('attachments'));
    end;
end;

function TBFTicketDetailVM.ShowNoMessages: Boolean;
var
  Ints, Atts: TBFJson;
begin
  Result := False;
  if Ticket = nil then Exit;
  Ints := FData.ArrOf('interactions');
  Atts := FData.ArrOf('attachments');
  Result := ((Ints = nil) or (Ints.Count = 0)) and (Ticket.StrOf('description') = '') and
    ((Atts = nil) or (Atts.Count = 0)) and not HasChat;
end;

function TBFTicketDetailVM.HasChat: Boolean;
begin
  Result := (FConversations <> nil) and (FConversations.Count > 0);
end;

function IsLive(C: TBFJson): Boolean;
begin
  Result := (C.StrOf('status') <> 'closed') and (C.StrOf('status') <> 'abandoned');
end;

function TBFTicketDetailVM.HasLiveConversation: Boolean;
var
  I: Integer;
begin
  Result := False;
  if FConversations <> nil then
    for I := 0 to FConversations.Count - 1 do
      if IsLive(FConversations.Item(I)) then
      begin
        Result := True;
        Exit;
      end;
end;

function TBFTicketDetailVM.ConversationCount: Integer;
begin
  if FConversations = nil then Result := 0 else Result := FConversations.Count;
end;

function TBFTicketDetailVM.Conversation(I: Integer): TBFJson;
begin
  Result := FConversations.Item(I);
end;

function TBFTicketDetailVM.ConversationTitle(I: Integer): string;
var
  C, A: TBFJson;
begin
  C := Conversation(I);
  Result := BFFormatDateTime(C.StrOf('created_at'));
  A := C.ObjOf('assigned_to');
  if (A <> nil) and (A.StrOf('name') <> '') then
    Result := Result + ' ' + BFFromUtf8(#$C2#$B7) + ' ' +
      BFFill(BFT(FLocale, 'detail_chat_with'), 'name', A.StrOf('name'));
end;

function TBFTicketDetailVM.ConversationSubtitle(I: Integer): string;
var
  C, Msgs: TBFJson;
  J, N: Integer;
begin
  C := Conversation(I);
  N := 0;
  Msgs := C.ArrOf('messages');
  if Msgs <> nil then
    for J := 0 to Msgs.Count - 1 do
      if Msgs.Item(J).StrOf('author_kind') <> 'system' then
        Inc(N);
  if N = 1 then
    Result := BFT(FLocale, 'detail_chat_count_one')
  else
    Result := BFFill(BFT(FLocale, 'detail_chat_count'), 'n', IntToStr(N));
  if IsLive(C) then
    Result := Result + ' ' + BFFromUtf8(#$C2#$B7) + ' ' + BFT(FLocale, 'detail_chat_ongoing');
end;

function TBFTicketDetailVM.TranscriptBubbles(I: Integer): TBFBubbles;
var
  Msgs, M: TBFJson;
  Order: array of Integer;
  J, K, Tmp: Integer;
  Kind, Author: string;
begin
  Result := nil;
  Msgs := Conversation(I).ArrOf('messages');
  if Msgs = nil then
    Exit;
  SetLength(Order, Msgs.Count);
  for J := 0 to Msgs.Count - 1 do
    Order[J] := J;
  // Ordenação estável por created_at (inserção).
  for J := 1 to High(Order) do
  begin
    Tmp := Order[J];
    K := J - 1;
    while (K >= 0) and (BFIsoToUnixMsDef(Msgs.Item(Order[K]).StrOf('created_at')) >
      BFIsoToUnixMsDef(Msgs.Item(Tmp).StrOf('created_at'))) do
    begin
      Order[K + 1] := Order[K];
      Dec(K);
    end;
    Order[K + 1] := Tmp;
  end;
  for J := 0 to High(Order) do
  begin
    M := Msgs.Item(Order[J]);
    Kind := M.StrOf('author_kind');
    if Kind = 'customer' then
      Author := BFT(FLocale, 'you')
    else if Kind = 'system' then
      Author := ''
    else
    begin
      Author := M.StrOf('author_name');
      if Author = '' then
        if Kind = 'bot' then Author := BFT(FLocale, 'chat_bot')
        else Author := BFT(FLocale, 'support_team');
    end;
    AddBubble(Result, Author, M.Utf8Of('content'), Kind <> 'customer', M.StrOf('created_at'),
      M.ArrOf('attachments'));
  end;
end;

function TBFTicketDetailVM.IsExpanded(I: Integer): Boolean;
begin
  Result := FExpanded.IndexOf(Conversation(I).StrOf('id')) >= 0;
end;

procedure TBFTicketDetailVM.ToggleExpanded(I: Integer);
var
  K: Integer;
begin
  K := FExpanded.IndexOf(Conversation(I).StrOf('id'));
  if K >= 0 then
    FExpanded.Delete(K)
  else
    FExpanded.Add(Conversation(I).StrOf('id'));
end;

function TBFTicketDetailVM.ShowInteractionsTitle: Boolean;
var
  Ints: TBFJson;
begin
  Ints := nil;
  if FData <> nil then
    Ints := FData.ArrOf('interactions');
  Result := HasChat and (Ints <> nil) and (Ints.Count > 0);
end;

function TBFTicketDetailVM.LastEventAt: string;
var
  Best: Int64;
  I, J: Integer;
  Ints, Msgs: TBFJson;

  procedure Consider(const S: string);
  var
    Ms: Int64;
  begin
    if (S <> '') and BFIsoToUnixMs(S, Ms) and (Ms > Best) then
    begin
      Best := Ms;
      Result := S;
    end;
  end;

begin
  Result := '';
  Best := -1;
  if Ticket = nil then
    Exit;
  Consider(Ticket.StrOf('updated_at'));
  Ints := FData.ArrOf('interactions');
  if Ints <> nil then
    for I := 0 to Ints.Count - 1 do
      Consider(Ints.Item(I).StrOf('created_at'));
  if FConversations <> nil then
    for I := 0 to FConversations.Count - 1 do
    begin
      Msgs := FConversations.Item(I).ArrOf('messages');
      if Msgs <> nil then
        for J := 0 to Msgs.Count - 1 do
          Consider(Msgs.Item(J).StrOf('created_at'));
    end;
end;

procedure TBFTicketDetailVM.MarkRead;
var
  Last: string;
begin
  Last := LastEventAt;
  if Last <> '' then
    FReadState.MarkRead(FTicketId, Last);
end;

function TBFTicketDetailVM.CanSend(const DraftHtml: string; PendingCount: Integer): Boolean;
begin
  Result := not Sending and not IsClosed and ((not BFIsHtmlEmpty(DraftHtml)) or (PendingCount > 0));
end;

end.
