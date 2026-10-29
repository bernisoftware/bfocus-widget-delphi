unit BFocusVMChat;

{ Chat ao vivo sem UI (behavior spec §5; useChatSession.ts + chatStream.ts):
  conversa, mensagens confirmadas + fila de envio otimista, não lidas, disponibilidade,
  desfecho (CSAT/acompanhamento), agrupamento de 2 min e o tempo real em MODO POLL
  (diferença aceita §10: Delphi 7/Lazarus não têm SSE). Quem usa dirige os tempos:
  cada Stream* devolve em quantos ms agir de novo (-1 = parou de vez). }

{$I BFocusDefines.inc}

interface

uses
  SysUtils, Classes, BFocusText, BFocusJson, BFocusHttp, BFocusApi, BFocusI18n, BFocusTokens,
  BFocusFormat;

const
  BF_CHAT_GROUP_MS = 120000;   // agrupamento de mensagens do mesmo autor
  BF_CHAT_MAX_BACKOFF_MS = 30000;
  BF_CHAT_SEEN_LIMIT = 1000;
  BF_CHAT_QUEUE_REFRESH_MS = 30000;
  BF_CHAT_AVAILABILITY_MS = 30000;
  BF_CSAT_COMMENT_MAX = 2000;

type
  TBFStreamStatus = (ssIdle, ssConnecting, ssPolling, ssReconnecting, ssFailed);
  TBFHomeMode = (hmHidden, hmLoading, hmActive, hmOnline, hmBusy, hmOffline);
  TBFClosingOutcome = (coCsat, coFollowUp, coPlain);
  TBFOutboxState = (obSending, obFailed);
  TBFStartResult = (srOk, srOffline, srError);

  TBFOutboxItem = class
  public
    TempId: string;
    ContentHtml: string;
    Attachments: TBFJson;   // array (dono)
    CreatedAt: string;
    State: TBFOutboxState;
    destructor Destroy; override;
  end;

  TBFChatSession = class
  private
    FConversation: TBFJson;
    FMessages: TBFJson;
    FOutbox: TList;
    FAvailability: TBFJson;
    FAvailabilityFailed: Boolean;
    FActiveChecked: Boolean;
    FLoaded: Boolean;
    FIdentityError: Boolean;
    FUnread: Integer;
    FConvChangedAt: Int64;
    FStatus: TBFStreamStatus;
    FRunning: Boolean;
    FGeneration: Integer;
    FLastEventId: Int64;
    FSeen: array of Int64;
    FSeenCount: Integer;
    FSeenNext: Integer;
    FFailures: Integer;
    FAttempt: Integer;
    FPollMs: Integer;
    FFirstPoll: Boolean;
    FTempSeq: Integer;
    procedure ClearConversation;
    procedure MergeMessages(Incoming: TBFJson);
    function SeenHas(Id: Int64): Boolean;
    procedure SeenAdd(Id: Int64);
    function FindOutbox(const TempId: string): Integer;
  public
    constructor Create;
    destructor Destroy; override;

    function Conversation: TBFJson;
    function ConversationId: string;
    function ConversationStatus: string;
    function IsTerminal: Boolean;
    function HasOpenConversation: Boolean;
    function Messages: TBFJson;
    function MessageCount: Integer;
    function Message(I: Integer): TBFJson;
    function OutboxCount: Integer;
    function OutboxItem(I: Integer): TBFOutboxItem;
    function Availability: TBFJson;

    { Respostas (a sessão vira dona dos nós recebidos). }
    procedure ApplyActive(Conv: TBFJson);
    procedure ApplyActiveFailed(E: Exception);
    procedure OpenConversation(Res: TBFJson);        // {conversation, messages}
    procedure Reset;
    procedure ApplySnapshot(const Id: string; Res: TBFJson; RequestedAt: Int64);
    procedure ApplyConversation(Conv: TBFJson);
    procedure ApplyAvailability(A: TBFJson);
    procedure ApplyAvailabilityFailed(E: Exception);
    { 401 de identidade em qualquer chamada do chat → a tela vira error_identity. }
    procedure NoteError(E: Exception);
    { Evento do tempo real (não é dono). True quando algo visível mudou. }
    function ApplyEvent(Ev: TBFJson; Viewing: Boolean): Boolean;

    { Fila de envio otimista. }
    function AddOutbox(const Html: string; Attachments: TBFJson): TBFOutboxItem;
    procedure ConfirmOutbox(const TempId: string; Msg: TBFJson);
    procedure FailOutbox(const TempId: string);
    function RetryOutbox(const TempId: string): TBFOutboxItem;
    procedure DiscardOutbox(const TempId: string);
    procedure MarkSeen;

    function HomeMode(Enabled: Boolean): TBFHomeMode;
    { Fila: rede de segurança para a posição (recarregar a cada 30 s). }
    function NeedsQueueRefresh: Boolean;

    { Tempo real (poll). }
    procedure StreamStart;
    procedure StreamStop;
    function StreamApplyTicket(T: TBFJson): Integer;
    function StreamTicketFailed(E: Exception): Integer;
    function StreamApplyPoll(Res: TBFJson; Viewing: Boolean; out Reconnected: Boolean): Integer;
    function StreamPollFailed(E: Exception): Integer;

    property ActiveChecked: Boolean read FActiveChecked;
    property Loaded: Boolean read FLoaded;
    property IdentityError: Boolean read FIdentityError;
    property Unread: Integer read FUnread;
    property StreamStatus: TBFStreamStatus read FStatus;
    property StreamRunning: Boolean read FRunning;
    { Muda a cada start/stop: respostas de uma geração antiga são descartadas. }
    property StreamGeneration: Integer read FGeneration;
    property LastEventId: Int64 read FLastEventId;
    property ConvChangedAt: Int64 read FConvChangedAt;
  end;

  TBFCsatState = (csIdle, csSending, csDone, csError, csNotResolved);

  TBFCsatVM = class
  private
    FComment: string;
    procedure SetComment(const Value: string);
  public
    Rating: Integer;
    State: TBFCsatState;
    ErrorText: string;
    { False quando não há nota ou já está enviando (trava de duplo clique). }
    function BeginSubmit: Boolean;
    procedure ApplySuccess;
    procedure ApplyError(E: Exception; const Locale: string);
    function ButtonText(const Locale: string): string;
    property Comment: string read FComment write SetComment;
  end;

function BFIsFatalStreamError(E: Exception): Boolean;
function BFClosingOutcome(Conv: TBFJson): TBFClosingOutcome;
function BFChatStatusLabel(const Locale: string; Conv: TBFJson): string;
function BFChatStatusColor(const Status: string): string;
function BFChatAuthorKey(M: TBFJson): string;
{ Mensagem seguida de outra do mesmo autor em até 2 min: rodapé/avatar só na última. }
function BFChatGroupedWithNext(M, Next: TBFJson): Boolean;
function BFChatIsMine(M: TBFJson): Boolean;
function BFChatAuthorName(const Locale: string; M, Conv: TBFJson): string;
function BFBotAgent(Conv: TBFJson): TBFJson;
function BFAvailabilityAgent(A: TBFJson): TBFJson;
function BFIsBotAvailability(A: TBFJson): Boolean;
function BFChatIntro(const Locale: string; A: TBFJson): string;

implementation

{ ── utilidades ─────────────────────────────────────────────────────────── }

function BFIsFatalStreamError(E: Exception): Boolean;
var
  S: Integer;
begin
  // 4xx (exceto tempo/limite) = conversa inexistente, sem permissão ou recurso desligado.
  S := BFErrorStatus(E);
  Result := (S >= 400) and (S < 500) and (S <> 408) and (S <> 425) and (S <> 429);
end;

function BFClosingOutcomeOf(Conv: TBFJson): TBFClosingOutcome;
var
  Reason, TS, St: string;
  Continues: Boolean;
begin
  Reason := Conv.StrOf('close_reason');
  TS := Conv.StrOf('ticket_status');
  St := Conv.StrOf('status');
  Continues := (Reason = 'follow_up') or (Reason = 'transferred');
  if TS <> '' then
  begin
    if (St = 'closed') and ((TS = 'resolved') or (TS = 'closed')) then
      Result := coCsat
    else if Continues or (TS = 'open') or (TS = 'in_triage') or (TS = 'in_progress') or
      (TS = 'waiting_requester') then
      Result := coFollowUp
    else
      Result := coPlain;
    Exit;
  end;
  // Servidor antigo sem ticket_status: regra anterior.
  if Continues then
    Result := coFollowUp
  else if (St = 'closed') and (Conv.StrOf('first_response_at') <> '') then
    Result := coCsat
  else
    Result := coPlain;
end;

function BFClosingOutcome(Conv: TBFJson): TBFClosingOutcome;
begin
  Result := BFClosingOutcomeOf(Conv);
  // Sem pesquisa (a empresa ou quem encerrou não manda): fica só o aviso de encerrada.
  if (Result = coCsat) and Conv.Has('survey') and not Conv.BoolOf('survey', True) then
    Result := coPlain;
end;

function BFBotAgent(Conv: TBFJson): TBFJson;
begin
  Result := nil;
  if Conv = nil then Exit;
  Result := Conv.ObjOf('agent');
  if (Result = nil) or (Result.StrOf('name') = '') then
    Result := Conv.ObjOf('ai_agent');
  if (Result <> nil) and (Result.StrOf('name') = '') then
    Result := nil;
end;

function BFAvailabilityAgent(A: TBFJson): TBFJson;
begin
  Result := nil;
  if A = nil then Exit;
  Result := A.ObjOf('ai_agent');
  if (Result = nil) or (Result.StrOf('name') = '') then
    Result := A.ObjOf('agent');
  if (Result <> nil) and (Result.StrOf('name') = '') then
    Result := nil;
end;

function BFIsBotAvailability(A: TBFJson): Boolean;
begin
  Result := (A <> nil) and ((A.StrOf('mode') = 'bot') or (A.StrOf('mode') = 'autonomous') or
    A.BoolOf('autonomous') or (BFAvailabilityAgent(A) <> nil));
end;

function BFChatIntro(const Locale: string; A: TBFJson): string;
var
  Agent: TBFJson;
begin
  if not BFIsBotAvailability(A) then
    Result := BFT(Locale, 'chat_new_intro')
  else
  begin
    Agent := BFAvailabilityAgent(A);
    if Agent <> nil then
      Result := BFFill(BFT(Locale, 'chat_new_intro_bot_named'), 'name', Agent.StrOf('name'))
    else
      Result := BFT(Locale, 'chat_new_intro_bot');
  end;
end;

function BFChatStatusLabel(const Locale: string; Conv: TBFJson): string;
var
  St: string;
  Pos_: Int64;
  Bot, Agent: TBFJson;
begin
  St := Conv.StrOf('status');
  if St = 'queued' then
  begin
    Pos_ := Conv.IntOf('queue_position');
    if Pos_ > 0 then
      Result := BFFill(BFT(Locale, 'chat_status_queued_pos'), 'n', IntToStr(Pos_))
    else
      Result := BFT(Locale, 'chat_status_queued');
  end
  else if St = 'bot' then
  begin
    Bot := BFBotAgent(Conv);
    if Bot <> nil then
      Result := BFFill(BFT(Locale, 'chat_status_bot_with'), 'name', Bot.StrOf('name'))
    else
      Result := BFT(Locale, 'chat_status_bot');
  end
  else if St = 'active' then
  begin
    Agent := Conv.ObjOf('assigned_to');
    if (Agent <> nil) and (Agent.StrOf('name') <> '') then
      Result := BFFill(BFT(Locale, 'chat_status_active_with'), 'name', Agent.StrOf('name'))
    else
      Result := BFT(Locale, 'chat_status_active');
  end
  else if St = 'waiting_customer' then
    Result := BFT(Locale, 'chat_status_waiting_customer')
  else
    Result := BFT(Locale, 'chat_status_closed');
end;

function BFChatStatusColor(const Status: string): string;
begin
  Result := BFTokenColor('chatStatus', Status, '#64748b');
end;

function BFChatIsMine(M: TBFJson): Boolean;
begin
  Result := not M.BoolOf('author_is_staff') and (M.StrOf('author_kind') = 'human');
end;

function BFChatAuthorKey(M: TBFJson): string;
begin
  if M.BoolOf('author_is_staff') or (M.StrOf('author_kind') <> 'human') then
    Result := 'team:' + M.StrOf('author_kind') + ':' + M.StrOf('author_name')
  else
    Result := 'me';
end;

function BFChatGroupedWithNext(M, Next: TBFJson): Boolean;
begin
  Result := (Next <> nil) and (Next.StrOf('author_kind') <> 'system') and
    (BFChatAuthorKey(Next) = BFChatAuthorKey(M)) and
    (BFIsoToUnixMsDef(Next.StrOf('created_at')) - BFIsoToUnixMsDef(M.StrOf('created_at')) <
    BF_CHAT_GROUP_MS);
end;

function BFChatAuthorName(const Locale: string; M, Conv: TBFJson): string;
var
  Bot: TBFJson;
begin
  if BFChatIsMine(M) then
    Result := BFT(Locale, 'you')
  else
  begin
    Result := M.StrOf('author_name');
    if Result = '' then
      if M.StrOf('author_kind') = 'bot' then
      begin
        Bot := BFBotAgent(Conv);
        if Bot <> nil then Result := Bot.StrOf('name') else Result := BFT(Locale, 'chat_bot');
      end
      else
        Result := BFT(Locale, 'support_team');
  end;
end;

{ ── TBFOutboxItem ──────────────────────────────────────────────────────── }

destructor TBFOutboxItem.Destroy;
begin
  Attachments.Free;
  inherited Destroy;
end;

{ ── TBFChatSession ─────────────────────────────────────────────────────── }

constructor TBFChatSession.Create;
begin
  inherited Create;
  FMessages := TBFJson.NewArray;
  FOutbox := TList.Create;
  FLastEventId := -1;
  SetLength(FSeen, BF_CHAT_SEEN_LIMIT);
end;

destructor TBFChatSession.Destroy;
begin
  ClearConversation;
  FMessages.Free;
  FOutbox.Free;
  FAvailability.Free;
  inherited Destroy;
end;

procedure TBFChatSession.ClearConversation;
var
  I: Integer;
begin
  FreeAndNil(FConversation);
  FMessages.Clear;
  for I := 0 to FOutbox.Count - 1 do
    TBFOutboxItem(FOutbox[I]).Free;
  FOutbox.Clear;
  FLoaded := False;
  FUnread := 0;
  FConvChangedAt := 0;
  // Conversa nova = histórico de eventos novo.
  FLastEventId := -1;
  FSeenCount := 0;
  FSeenNext := 0;
end;

function TBFChatSession.Conversation: TBFJson;
begin
  Result := FConversation;
end;

function TBFChatSession.ConversationId: string;
begin
  if FConversation = nil then Result := '' else Result := FConversation.StrOf('id');
end;

function TBFChatSession.ConversationStatus: string;
begin
  if FConversation = nil then Result := '' else Result := FConversation.StrOf('status');
end;

function TBFChatSession.IsTerminal: Boolean;
begin
  Result := (ConversationStatus = 'closed') or (ConversationStatus = 'abandoned');
end;

function TBFChatSession.HasOpenConversation: Boolean;
begin
  Result := (FConversation <> nil) and not IsTerminal;
end;

function TBFChatSession.Messages: TBFJson;
begin
  Result := FMessages;
end;

function TBFChatSession.MessageCount: Integer;
begin
  Result := FMessages.Count;
end;

function TBFChatSession.Message(I: Integer): TBFJson;
begin
  Result := FMessages.Item(I);
end;

function TBFChatSession.OutboxCount: Integer;
begin
  Result := FOutbox.Count;
end;

function TBFChatSession.OutboxItem(I: Integer): TBFOutboxItem;
begin
  Result := TBFOutboxItem(FOutbox[I]);
end;

function TBFChatSession.Availability: TBFJson;
begin
  Result := FAvailability;
end;

{ União por id, ordenada por created_at (estável). Mensagens nunca são apagadas. }
procedure TBFChatSession.MergeMessages(Incoming: TBFJson);
var
  I, J, K: Integer;
  M: TBFJson;
  Items: TList;
  Tmp: Pointer;
begin
  if Incoming = nil then
    Exit;
  for I := 0 to Incoming.Count - 1 do
  begin
    M := Incoming.Item(I);
    if M.StrOf('id') = '' then
      Continue;
    K := -1;
    for J := 0 to FMessages.Count - 1 do
      if FMessages.Item(J).StrOf('id') = M.StrOf('id') then
      begin
        K := J;
        Break;
      end;
    if K >= 0 then
    begin
      // Troca mantendo a posição (a ordenação abaixo acerta o resto).
      Items := TList.Create;
      try
        while FMessages.Count > 0 do
          Items.Add(FMessages.Extract(0));
        TBFJson(Items[K]).Free;
        Items[K] := M.Clone;
        for J := 0 to Items.Count - 1 do
          FMessages.Add(TBFJson(Items[J]));
      finally
        Items.Free;
      end;
    end
    else
      FMessages.Add(M.Clone);
  end;
  Items := TList.Create;
  try
    while FMessages.Count > 0 do
      Items.Add(FMessages.Extract(0));
    for I := 1 to Items.Count - 1 do
    begin
      Tmp := Items[I];
      J := I - 1;
      while (J >= 0) and (BFIsoToUnixMsDef(TBFJson(Items[J]).StrOf('created_at')) >
        BFIsoToUnixMsDef(TBFJson(Tmp).StrOf('created_at'))) do
      begin
        Items[J + 1] := Items[J];
        Dec(J);
      end;
      Items[J + 1] := Tmp;
    end;
    for I := 0 to Items.Count - 1 do
      FMessages.Add(TBFJson(Items[I]));
  finally
    Items.Free;
  end;
end;

procedure TBFChatSession.ApplyActive(Conv: TBFJson);
begin
  FActiveChecked := True;
  if (Conv = nil) or not Conv.IsObject or (FConversation <> nil) then
  begin
    Conv.Free;
    Exit;
  end;
  ClearConversation;
  FConversation := Conv;
  FConvChangedAt := BFNowUnixMs;
end;

procedure TBFChatSession.ApplyActiveFailed(E: Exception);
begin
  NoteError(E);
  FActiveChecked := True;
end;

procedure TBFChatSession.OpenConversation(Res: TBFJson);
begin
  try
    if (Res = nil) or (Res.ObjOf('conversation') = nil) then
      Exit;
    ClearConversation;
    FActiveChecked := True;
    FConversation := Res.ExtractKey('conversation');
    MergeMessages(Res.ArrOf('messages'));
    FLoaded := Res.Has('messages');
    FConvChangedAt := BFNowUnixMs;
  finally
    Res.Free;
  end;
end;

procedure TBFChatSession.Reset;
begin
  StreamStop;
  ClearConversation;
  FActiveChecked := True;
end;

procedure TBFChatSession.ApplySnapshot(const Id: string; Res: TBFJson; RequestedAt: Int64);
var
  Conv: TBFJson;
begin
  try
    if (Res = nil) or (ConversationId <> Id) then
      Exit;
    // Evento/POST mais novo que o pedido do snapshot vence (o snapshot pode estar velho).
    if FConvChangedAt <= RequestedAt then
    begin
      Conv := Res.ExtractKey('conversation');
      if (Conv <> nil) and Conv.IsObject then
      begin
        FConversation.Free;
        FConversation := Conv;
      end
      else
        Conv.Free;
    end;
    MergeMessages(Res.ArrOf('messages'));
    FLoaded := True;
  finally
    Res.Free;
  end;
end;

procedure TBFChatSession.ApplyConversation(Conv: TBFJson);
begin
  if (Conv = nil) or not Conv.IsObject or
    ((FConversation <> nil) and (Conv.StrOf('id') <> ConversationId)) then
  begin
    Conv.Free;
    Exit;
  end;
  FConversation.Free;
  FConversation := Conv;
  FConvChangedAt := BFNowUnixMs;
end;

procedure TBFChatSession.ApplyAvailability(A: TBFJson);
begin
  FAvailability.Free;
  FAvailability := A;
  FAvailabilityFailed := False;
end;

procedure TBFChatSession.ApplyAvailabilityFailed(E: Exception);
begin
  NoteError(E);
  if FAvailability = nil then
    FAvailabilityFailed := True;
end;

procedure TBFChatSession.NoteError(E: Exception);
begin
  if BFIsIdentityError(E) then
    FIdentityError := True;
end;

function TBFChatSession.FindOutbox(const TempId: string): Integer;
var
  I: Integer;
begin
  for I := 0 to FOutbox.Count - 1 do
    if TBFOutboxItem(FOutbox[I]).TempId = TempId then
    begin
      Result := I;
      Exit;
    end;
  Result := -1;
end;

function TBFChatSession.ApplyEvent(Ev: TBFJson; Viewing: Boolean): Boolean;
var
  T: string;
  Conv, Msg: TBFJson;
  Known, FromTeam: Boolean;
  I: Integer;
  Single: TBFJson;
begin
  Result := False;
  if (Ev = nil) or not Ev.IsObject then
    Exit;
  T := Ev.StrOf('type');
  if T = 'conversation.updated' then
  begin
    Conv := Ev.Path('payload.conversation');
    if (Conv = nil) or not Conv.IsObject or (FConversation = nil) or
      (Conv.StrOf('id') <> ConversationId) then
      Exit;
    FConversation.Free;
    FConversation := Conv.Clone;
    FConvChangedAt := BFNowUnixMs;
    Result := True;
  end
  else if T = 'message.created' then
  begin
    Msg := Ev.Path('payload.message');
    if (Msg = nil) or not Msg.IsObject or (Msg.StrOf('id') = '') then
      Exit;
    Known := False;
    for I := 0 to FMessages.Count - 1 do
      if FMessages.Item(I).StrOf('id') = Msg.StrOf('id') then
      begin
        Known := True;
        Break;
      end;
    if not Known and BFChatIsMine(Msg) then
      // Minha mensagem chegou pelo stream antes da resposta do POST: ocupa o lugar da
      // otimista mais antiga em envio (o POST depois só confirma o id).
      for I := 0 to FOutbox.Count - 1 do
        if TBFOutboxItem(FOutbox[I]).State = obSending then
        begin
          TBFOutboxItem(FOutbox[I]).Free;
          FOutbox.Delete(I);
          Break;
        end;
    FromTeam := Msg.BoolOf('author_is_staff') or (Msg.StrOf('author_kind') = 'bot');
    Single := TBFJson.NewArray;
    try
      Single.Add(Msg.Clone);
      MergeMessages(Single);
    finally
      Single.Free;
    end;
    if not Known and FromTeam and not Viewing then
      Inc(FUnread);
    Result := True;
  end;
end;

function TBFChatSession.AddOutbox(const Html: string; Attachments: TBFJson): TBFOutboxItem;
begin
  Inc(FTempSeq);
  Result := TBFOutboxItem.Create;
  Result.TempId := 'tmp-' + IntToStr(BFNowUnixMs) + '-' + IntToStr(FTempSeq);
  Result.ContentHtml := Html;
  if Attachments <> nil then
    Result.Attachments := Attachments
  else
    Result.Attachments := TBFJson.NewArray;
  Result.CreatedAt := BFUnixMsToIso(BFNowUnixMs);
  Result.State := obSending;
  FOutbox.Add(Result);
end;

procedure TBFChatSession.ConfirmOutbox(const TempId: string; Msg: TBFJson);
var
  I: Integer;
  Single: TBFJson;
begin
  I := FindOutbox(TempId);
  if I >= 0 then
  begin
    TBFOutboxItem(FOutbox[I]).Free;
    FOutbox.Delete(I);
  end;
  if (Msg <> nil) and Msg.IsObject then
  begin
    Single := TBFJson.NewArray;
    try
      Single.Add(Msg);
      Msg := nil;
      MergeMessages(Single);
    finally
      Single.Free;
    end;
  end;
  Msg.Free;
end;

procedure TBFChatSession.FailOutbox(const TempId: string);
var
  I: Integer;
begin
  I := FindOutbox(TempId);
  if I >= 0 then
    TBFOutboxItem(FOutbox[I]).State := obFailed;
end;

function TBFChatSession.RetryOutbox(const TempId: string): TBFOutboxItem;
var
  I: Integer;
begin
  Result := nil;
  I := FindOutbox(TempId);
  if I < 0 then
    Exit;
  Result := TBFOutboxItem(FOutbox[I]);
  Result.State := obSending;
end;

procedure TBFChatSession.DiscardOutbox(const TempId: string);
var
  I: Integer;
begin
  I := FindOutbox(TempId);
  if I >= 0 then
  begin
    TBFOutboxItem(FOutbox[I]).Free;
    FOutbox.Delete(I);
  end;
end;

procedure TBFChatSession.MarkSeen;
begin
  FUnread := 0;
end;

function TBFChatSession.HomeMode(Enabled: Boolean): TBFHomeMode;
var
  St: string;
begin
  if not Enabled then
    Result := hmHidden
  else if HasOpenConversation then
    Result := hmActive
  else if FAvailability <> nil then
  begin
    St := FAvailability.StrOf('status');
    if not FAvailability.BoolOf('enabled') then Result := hmHidden
    else if St = 'online' then Result := hmOnline
    else if St = 'busy' then Result := hmBusy
    else Result := hmOffline;
  end
  else if FAvailabilityFailed then
    Result := hmHidden
  else
    Result := hmLoading;
end;

function TBFChatSession.NeedsQueueRefresh: Boolean;
begin
  Result := ConversationStatus = 'queued';
end;

{ ── tempo real (poll) ──────────────────────────────────────────────────── }

function TBFChatSession.SeenHas(Id: Int64): Boolean;
var
  I: Integer;
begin
  for I := 0 to FSeenCount - 1 do
    if FSeen[I] = Id then
    begin
      Result := True;
      Exit;
    end;
  Result := False;
end;

procedure TBFChatSession.SeenAdd(Id: Int64);
begin
  // Anel dos últimos 1000 ids: o mais antigo sai quando enche.
  FSeen[FSeenNext] := Id;
  FSeenNext := (FSeenNext + 1) mod BF_CHAT_SEEN_LIMIT;
  if FSeenCount < BF_CHAT_SEEN_LIMIT then
    Inc(FSeenCount);
end;

procedure TBFChatSession.StreamStart;
begin
  if FRunning or (FConversation = nil) or IsTerminal then
    Exit;
  FRunning := True;
  Inc(FGeneration);
  FAttempt := 0;
  FFailures := 0;
  FStatus := ssConnecting;
end;

procedure TBFChatSession.StreamStop;
begin
  if FRunning then
    Inc(FGeneration);
  FRunning := False;
  FStatus := ssIdle;
end;

function TBFChatSession.StreamApplyTicket(T: TBFJson): Integer;
begin
  Result := 0;
  try
    if not FRunning then
    begin
      Result := -1;
      Exit;
    end;
    if (T <> nil) and T.IsObject then
    begin
      if (FLastEventId < 0) and T.Has('last_event_id') and not T.IsNullOrAbsent('last_event_id') then
        FLastEventId := T.IntOf('last_event_id');
      FPollMs := Integer(T.IntOf('poll_interval_ms', 5000));
    end;
    if FPollMs < 1000 then
      FPollMs := 5000;
    FFirstPoll := True;
    FStatus := ssPolling;
  finally
    T.Free;
  end;
end;

function TBFChatSession.StreamTicketFailed(E: Exception): Integer;
var
  Ceiling: Integer;
begin
  if BFIsFatalStreamError(E) then
  begin
    FRunning := False;
    Inc(FGeneration);
    FStatus := ssFailed;
    NoteError(E);
    Result := -1;
    Exit;
  end;
  FStatus := ssReconnecting;
  // Espera exponencial com variação aleatória, até 30 s.
  Ceiling := 1000;
  if FAttempt < 5 then
    Ceiling := 1000 shl FAttempt
  else
    Ceiling := BF_CHAT_MAX_BACKOFF_MS;
  if Ceiling > BF_CHAT_MAX_BACKOFF_MS then
    Ceiling := BF_CHAT_MAX_BACKOFF_MS;
  Inc(FAttempt);
  Result := Ceiling div 2 + Random(Ceiling div 2 + 1);
end;

function TBFChatSession.StreamApplyPoll(Res: TBFJson; Viewing: Boolean;
  out Reconnected: Boolean): Integer;
var
  Events, Ev: TBFJson;
  I: Integer;
  Id: Int64;
begin
  Reconnected := False;
  try
    if not FRunning then
    begin
      Result := -1;
      Exit;
    end;
    if (Res <> nil) and Res.IsObject then
    begin
      Events := Res.ArrOf('events');
      if Events <> nil then
        for I := 0 to Events.Count - 1 do
        begin
          Ev := Events.Item(I);
          if Ev.Has('id') and not Ev.IsNullOrAbsent('id') then
          begin
            Id := Ev.IntOf('id');
            // Replay e ao vivo podem se sobrepor: descarta repetidos pelo id.
            if SeenHas(Id) then
              Continue;
            SeenAdd(Id);
            if Id > FLastEventId then
              FLastEventId := Id;
          end;
          ApplyEvent(Ev, Viewing);
        end;
      if Res.Has('last_event_id') and not Res.IsNullOrAbsent('last_event_id') and
        (Res.IntOf('last_event_id') > FLastEventId) then
        FLastEventId := Res.IntOf('last_event_id');
    end;
    FFailures := 0;
    FAttempt := 0;
    FStatus := ssPolling;
    // A cada (re)conexão, recarregar a conversa inteira cobre qualquer lacuna.
    Reconnected := FFirstPoll;
    FFirstPoll := False;
    Result := FPollMs;
  finally
    Res.Free;
  end;
end;

function TBFChatSession.StreamPollFailed(E: Exception): Integer;
var
  F: Integer;
begin
  if BFIsFatalStreamError(E) then
  begin
    FRunning := False;
    Inc(FGeneration);
    FStatus := ssFailed;
    NoteError(E);
    Result := -1;
    Exit;
  end;
  Inc(FFailures);
  FStatus := ssReconnecting;
  F := FFailures;
  if F > 3 then
    F := 3;
  Result := FPollMs shl F;
  if Result > BF_CHAT_MAX_BACKOFF_MS then
    Result := BF_CHAT_MAX_BACKOFF_MS;
end;

{ ── CSAT ───────────────────────────────────────────────────────────────── }

procedure TBFCsatVM.SetComment(const Value: string);
begin
  FComment := Copy(Value, 1, BF_CSAT_COMMENT_MAX);
end;

function TBFCsatVM.BeginSubmit: Boolean;
begin
  Result := (Rating >= 1) and (Rating <= 5) and (State <> csSending) and (State <> csDone);
  if Result then
  begin
    State := csSending;
    ErrorText := '';
  end;
end;

procedure TBFCsatVM.ApplySuccess;
begin
  State := csDone;
end;

procedure TBFCsatVM.ApplyError(E: Exception; const Locale: string);
begin
  if (BFErrorStatus(E) = 409) and (BFErrorCode(E) = 'TICKET_NOT_RESOLVED') then
  begin
    State := csNotResolved;
    Exit;
  end;
  if E is EBFocusNetworkError then
  begin
    if EBFocusNetworkError(E).Kind = neTimeout then
      ErrorText := BFT(Locale, 'csat_error_timeout')
    else
      ErrorText := BFT(Locale, 'csat_error_network');
  end
  else
    ErrorText := BFT(Locale, 'csat_error_generic');
  State := csError;
end;

function TBFCsatVM.ButtonText(const Locale: string): string;
begin
  case State of
    csSending: Result := BFT(Locale, 'csat_sending');
    csError: Result := BFT(Locale, 'csat_retry');
  else
    Result := BFT(Locale, 'csat_submit');
  end;
end;

end.
