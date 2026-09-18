unit BFocusVMTests;

{ Testes dos view-models das telas nativas com dados fixos no formato da API
  (api/app/routers/widget.py e widget_chat.py). Cobrem os cenários 2–13 do behavior spec
  §11 no que é lógica (a parte visual é roteiro manual). }

{$I BFocusDefines.inc}

interface

procedure RunVMTests;

implementation

uses
  SysUtils, Classes, BFocusTestKit, BFocusText, BFocusJson, BFocusStorage, BFocusApi,
  BFocusHttp, BFocusConfig, BFocusVMTickets, BFocusVMChat, BFocusVMReleaseNotes, BFocusI18n,
  BFocusFormat;

function J(const S: string): TBFJson;
begin
  Result := TBFJson.Parse(BFToUtf8(S));
end;

{ ── chamados ───────────────────────────────────────────────────────────── }

procedure TestReadStateAndList;
var
  Store: IBFocusStorage;
  RS: TBFReadState;
  L: TBFTicketListVM;
begin
  Store := TBFMemoryStorage.Create;
  RS := TBFReadState.Create(Store, 'k:u:c');
  L := TBFTicketListVM.Create(RS, 'pt_BR');
  try
    Check(not RS.IsUnread('a', '2026-09-01T10:00:00.500Z', '2026-09-01T10:00:00Z'),
      'nunca aberto, dentro de 1 s da criação: lido');
    Check(RS.IsUnread('a', '2026-09-01T10:00:02Z', '2026-09-01T10:00:00Z'),
      'nunca aberto, evento depois da criação: não lido');
    RS.MarkRead('a', '2026-09-01T10:00:02Z');
    Check(not RS.IsUnread('a', '2026-09-01T10:00:02Z', '2026-09-01T10:00:00Z'), 'aberto → lido');
    Check(RS.IsUnread('a', '2026-09-01T07:00:03-03:00', '2026-09-01T10:00:00Z'),
      'resposta nova (outro fuso) → não lido');
    Check(not RS.IsUnread('b', '', '2026-09-01T10:00:00Z'), 'sem last_event_at: lido');
    L.ApplyList(J('[{"id":"a","ticket_number":"T-1","title":"x","status":"in_progress",' +
      '"created_at":"2026-09-01T10:00:00Z","updated_at":"2026-09-01T10:00:05Z","last_event_at":"2026-09-01T10:00:05Z"},' +
      '{"id":"b","ticket_number":"T-2","title":"y","status":"resolved","created_at":"2026-09-01T10:00:00Z",' +
      '"updated_at":"2026-09-01T10:00:00Z","last_event_at":"2026-09-01T10:00:00Z"}]'));
    CheckEqInt(L.Count, 2, 'lista');
    CheckEqInt(L.UnreadCount, 1, 'contagem de não lidos (bfocus:unread)');
    CheckEq(L.StatusText(0), 'Em andamento', 'status traduzido');
    CheckEq(L.StatusColor(0), '#f59e0b', 'cor do status pelos tokens');
    CheckEq(L.StatusColor(1), '#10b981', 'cor resolvido');
    Check(not L.IsEmpty, 'não vazia');
    L.ApplyList(J('[]'));
    Check(L.IsEmpty, 'estado vazio');
  finally
    L.Free;
    RS.Free;
  end;
end;

procedure TestNewTicket;
var
  Cfg, Att: TBFJson;
  V: TBFNewTicketVM;
  S: string;
begin
  Cfg := J('{"tenant":{"name":"ACME","primary_color":"#123456"},"defaults":{"department_id":null,"type":"bug"},' +
    '"departments":[{"id":"d1","name":"TI"},{"id":"d2","name":"Fin"}],"types":["support","bug","request","incident"],' +
    '"priorities":["low","medium","high","critical"],"chat":{"enabled":true}}');
  V := TBFNewTicketVM.Create(Cfg, 'en');
  try
    CheckEq(V.TypeName, 'bug', 'tipo padrão da config');
    CheckEq(V.Priority, 'medium', 'prioridade padrão');
    CheckEqInt(V.TypeCount, 4, 'chips de tipo');
    CheckEq(V.TypeLabel('support'), 'Question', 'rótulo do tipo');
    CheckEq(V.PriorityColor('critical'), '#ef4444', 'cor da prioridade');
    Check(V.ShowDepartments, 'departamento com mais de um');
    Check(not V.CanSubmit, 'sem título não envia');
    S := StringOfChar('x', 600);
    V.Title := S;
    CheckEqInt(Length(V.Title), 500, 'título até 500');
    Check(V.CanSubmit, 'com título envia');
    V.DescriptionHtml := '<p></p>';
    CheckEq(V.DescriptionForSend, '', 'descrição vazia não vai');
    V.ApplyUpload(J('{"url":"https://cdn/x.png","filename":"x.png","size":10,"mime":"image/png"}'));
    V.ApplyUpload(J('{"url":"https://cdn/y.pdf","filename":"y.pdf","size":20,"mime":"application/pdf"}'));
    CheckEqInt(V.UploadCount, 2, '2 anexos (cenário 3)');
    Att := V.AttachmentsForSend;
    try
      CheckEq(string(Att.ToJson), '[{"url":"https://cdn/x.png","filename":"x.png","size":10,"content_type":"image/png"},' +
        '{"url":"https://cdn/y.pdf","filename":"y.pdf","size":20,"content_type":"application/pdf"}]',
        'anexos no formato do POST');
    finally
      Att.Free;
    end;
    V.RemoveUpload(0);
    CheckEqInt(V.UploadCount, 1, 'remover anexo');
    V.ApplyPrefill('<p>oi</p>', nil, BFT('en', 'chat_offline_fallback'));
    Check(Pos('unavailable', V.Notice) > 0, 'aviso do chat offline (cenário 10)');
  finally
    V.Free;
    Cfg.Free;
  end;
end;

procedure TestDetail;
var
  Store: IBFocusStorage;
  RS: TBFReadState;
  D: TBFTicketDetailVM;
  B: TBFBubbles;
begin
  Store := TBFMemoryStorage.Create;
  RS := TBFReadState.Create(Store, 's');
  D := TBFTicketDetailVM.Create(RS, 'pt_BR', 't1');
  try
    D.ApplyTicket(J('{"ticket":{"id":"t1","ticket_number":"T-9","title":"Erro","status":"resolved",' +
      '"description":"<p>desc</p>","created_at":"2026-09-01T10:00:00Z","updated_at":"2026-09-01T11:00:00Z",' +
      '"auto_close_at":"2026-09-08T11:00:00Z","previous_ticket":{"id":"t0","ticket_number":"T-8","title":"a"}},' +
      '"interactions":[{"id":"i1","content":"<p>resp</p>","author_name":"Bia","author_is_staff":true,' +
      '"created_at":"2026-09-01T10:30:00Z","attachments":[]}],' +
      '"attachments":[{"id":"a1","filename":"f.pdf","url":"u","size":1,"content_type":"application/pdf"}]}'));
    D.ApplyConversations(J('[{"id":"c1","status":"active","created_at":"2026-09-01T10:00:00Z","closed_at":null,' +
      '"assigned_to":{"id":"x","name":"Bia"},"messages":[' +
      '{"id":"m2","author_kind":"agent","author_name":"Bia","content":"<p>b</p>","created_at":"2026-09-01T12:00:00Z","attachments":[]},' +
      '{"id":"m1","author_kind":"customer","author_name":null,"content":"<p>a</p>","created_at":"2026-09-01T10:01:00Z","attachments":[]},' +
      '{"id":"m0","author_kind":"system","author_name":null,"content":"<p>s</p>","created_at":"2026-09-01T10:00:00Z","attachments":[]}]}]'));
    B := D.Bubbles;
    CheckEqInt(Length(B), 2, 'descrição + interação');
    CheckEq(B[0].Author, 'Você', 'descrição é "Você"');
    CheckEqInt(B[0].Attachments.Count, 1, 'anexo do chamado na primeira bolha');
    Check(B[1].IsStaff and (B[1].Author = 'Bia'), 'resposta da equipe');
    Check(D.IsResolved and not D.IsClosed, 'resolvido aceita resposta (cenário 4)');
    Check(Pos('reaberto (até', D.ReopenHint) > 0, 'dica de reabertura com data');
    CheckEq(D.ContinuationText, 'Continuação de T-8', 'continuação');
    Check(D.HasChat and D.HasLiveConversation, 'conversa do chat viva');
    CheckEq(D.ConversationSubtitle(0), '2 mensagens ' + BFFromUtf8(#$C2#$B7) + ' em andamento', 'contagem sem system');
    B := D.TranscriptBubbles(0);
    CheckEq(string(B[0].Html) + string(B[2].Html), '<p>s</p><p>b</p>', 'transcrição em ordem cronológica');
    CheckEq(B[1].Author, 'Você', 'cliente = Você');
    Check(D.ShowInteractionsTitle, 'título do andamento com chat');
    CheckEq(D.LastEventAt, '2026-09-01T12:00:00Z', 'evento mais recente inclui o chat');
    D.MarkRead;
    Check(not RS.IsUnread('t1', '2026-09-01T12:00:00Z', '2026-09-01T10:00:00Z'), 'abrir marca como lido');
    Check(D.CanSend('<p>x</p>', 0) and D.CanSend('', 1) and not D.CanSend('<p> </p>', 0), 'pode enviar');
    Check(D.NeedsReloadAfterSendError(409), '409 TICKET_CLOSED recarrega');
    D.ApplyTicket(J('{"ticket":{"id":"t1","ticket_number":"T-9","title":"Erro","status":"closed",' +
      '"description":null,"created_at":"2026-09-01T10:00:00Z","updated_at":"2026-09-01T11:00:00Z"},"interactions":[],"attachments":[]}'));
    Check(D.IsClosed and (D.ClosedNotice <> '') and not D.CanSend('<p>x</p>', 0),
      'fechado: sem caixa, com aviso (cenário 5)');
    D.ApplyConversations(nil);
    Check(D.ShowNoMessages, 'sem mensagens');
  finally
    D.Free;
    RS.Free;
  end;
end;

{ ── chat ───────────────────────────────────────────────────────────────── }

function Conv(const Status, Extra: string): TBFJson;
begin
  Result := J('{"id":"c1","ticket_id":"t1","ticket_number":"T-5","status":"' + Status + '"' + Extra + '}');
end;

function Msg(const Id, Kind, Staff, Name, At: string): string;
begin
  Result := '{"id":"' + Id + '","conversation_id":"c1","content":"<p>' + Id + '</p>","author_kind":"' + Kind +
    '","author_name":' + Name + ',"author_is_staff":' + Staff + ',"created_at":"' + At + '","attachments":[]}';
end;

procedure TestChatSession;
var
  S: TBFChatSession;
  Item: TBFOutboxItem;
  Ev: TBFJson;
  Delay: Integer;
  Reconn: Boolean;
  E: Exception;
begin
  S := TBFChatSession.Create;
  try
    CheckBool(S.HomeMode(True) = hmLoading, True, 'home carregando');
    S.ApplyAvailability(J('{"enabled":true,"status":"busy","queue_size":3}'));
    CheckBool(S.HomeMode(True) = hmBusy, True, 'home ocupado');
    CheckBool(S.HomeMode(False) = hmHidden, True, 'chat desligado');
    S.ApplyActive(nil);
    Check(S.ActiveChecked and (S.Conversation = nil), 'sem conversa ativa');
    S.OpenConversation(J('{"conversation":' + Conv('queued', ',"queue_position":2').ToJsonString +
      ',"messages":[' + Msg('m2', 'human', 'false', 'null', '2026-09-01T10:01:00Z') + ',' +
      Msg('m1', 'system', 'false', 'null', '2026-09-01T10:00:00Z') + ']}'));
    CheckEq(S.ConversationId, 'c1', 'conversa aberta');
    CheckBool(S.HomeMode(True) = hmActive, True, 'home com conversa');
    CheckEq(S.Message(0).StrOf('id'), 'm1', 'mensagens ordenadas por created_at');
    CheckEq(BFChatStatusLabel('pt_BR', S.Conversation), 'Na fila ' + BFFromUtf8(#$E2#$80#$94) + ' posição 2',
      'status na fila com posição');
    CheckEq(BFChatStatusColor('queued'), '#f59e0b', 'cor do status');
    Check(S.NeedsQueueRefresh, 'fila recarrega a cada 30 s');
    // Envio otimista e confirmação pelo id.
    Item := S.AddOutbox('<p>oi</p>', nil);
    CheckEqInt(S.OutboxCount, 1, 'mensagem na fila de envio');
    S.FailOutbox(Item.TempId);
    Check(S.OutboxItem(0).State = obFailed, 'falha marca "tentar de novo" (cenário 8)');
    Check(S.RetryOutbox(Item.TempId).State = obSending, 'tentar de novo');
    S.ConfirmOutbox(Item.TempId, J(Msg('m3', 'human', 'false', '"Ana"', '2026-09-01T10:02:00Z')));
    CheckEqInt(S.OutboxCount, 0, 'confirmada sai da fila');
    CheckEqInt(S.MessageCount, 3, 'confirmada entra na conversa');
    Item := S.AddOutbox('<p>x</p>', nil);
    S.DiscardOutbox(Item.TempId);
    CheckEqInt(S.OutboxCount, 0, 'descartar');
    // Poll: ticket → eventos (dedupe) → reconexão recarrega.
    S.StreamStart;
    Check(S.StreamStatus = ssConnecting, 'conectando');
    Delay := S.StreamApplyTicket(J('{"mode":"sse","ticket":"tk","expires_in":60,"poll_interval_ms":5000,"last_event_id":10}'));
    CheckEqInt(Delay, 0, 'primeiro poll imediato (modo poll sempre)');
    CheckEqInt(S.LastEventId, 10, 'last_event_id do ticket');
    Item := S.AddOutbox('<p>minha</p>', nil);
    Ev := J('{"events":[' +
      '{"id":11,"type":"message.created","created_at":"x","payload":{"message":' + Msg('m4', 'human', 'true', '"Bia"', '2026-09-01T10:03:00Z') + '}},' +
      '{"id":12,"type":"message.created","created_at":"x","payload":{"message":' + Msg('m5', 'human', 'false', '"Ana"', '2026-09-01T10:03:30Z') + '}},' +
      '{"id":11,"type":"message.created","created_at":"x","payload":{"message":' + Msg('m4', 'human', 'true', '"Bia"', '2026-09-01T10:03:00Z') + '}},' +
      '{"id":13,"type":"conversation.updated","created_at":"x","payload":{"conversation":' +
      Conv('active', ',"assigned_to":{"id":"a","name":"Bia","avatar_url":null}').ToJsonString + '}}' +
      '],"last_event_id":13}');
    Delay := S.StreamApplyPoll(Ev, False, Reconn);
    CheckEqInt(Delay, 5000, 'próximo poll em 5 s');
    Check(Reconn, 'primeira resposta = (re)conexão → recarregar conversa');
    CheckEqInt(S.MessageCount, 5, 'evento repetido descartado (cenário 8)');
    CheckEqInt(S.Unread, 1, 'mensagem da equipe fora da tela conta como não lida');
    CheckEqInt(S.OutboxCount, 0, 'minha mensagem pelo stream ocupa a otimista');
    CheckEq(BFChatStatusLabel('en', S.Conversation), 'Being served by Bia', 'status com atendente');
    CheckEqInt(S.LastEventId, 13, 'último id');
    Delay := S.StreamApplyPoll(J('{"events":[],"last_event_id":13}'), True, Reconn);
    Check(not Reconn, 'polls seguintes não recarregam');
    S.MarkSeen;
    CheckEqInt(S.Unread, 0, 'visto zera');
    E := EBFocusNetworkError.CreateNet(neNetwork, 'x');
    try
      CheckEqInt(S.StreamPollFailed(E), 10000, 'queda de rede: espera exponencial');
      Check(S.StreamStatus = ssReconnecting, 'reconectando');
      CheckEqInt(S.StreamPollFailed(E), 20000, 'segunda falha');
      CheckEqInt(S.StreamPollFailed(E), 30000, 'teto de 30 s');
    finally
      E.Free;
    end;
    E := EBFocusApiError.CreateCode(404, 'CONVERSATION_NOT_FOUND', 'x');
    try
      CheckEqInt(S.StreamPollFailed(E), -1, '4xx é fatal');
      Check(S.StreamStatus = ssFailed, 'falhou');
    finally
      E.Free;
    end;
    E := EBFocusApiError.CreateCode(429, 'RATE_LIMITED', 'x');
    try
      Check(not BFIsFatalStreamError(E), '429 não é fatal');
    finally
      E.Free;
    end;
    // Snapshot velho não sobrescreve conversa mais nova.
    S.ApplySnapshot('c1', J('{"conversation":' + Conv('queued', '').ToJsonString + ',"messages":[]}'),
      S.ConvChangedAt - 1000);
    CheckEq(S.ConversationStatus, 'active', 'snapshot velho não volta a conversa');
    // Encerrada com CSAT; continuar abre outra.
    S.ApplyConversation(Conv('closed', ',"close_reason":"resolved","ticket_status":"resolved"'));
    Check(S.IsTerminal, 'encerrada');
    Check(BFClosingOutcome(S.Conversation) = coCsat, 'desfecho csat (cenário 9)');
    S.StreamStart;
    Check(not S.StreamRunning, 'encerrada não liga o stream');
    S.Reset;
    Check(S.Conversation = nil, 'continuar/voltar zera a conversa');
    // Identidade.
    E := EBFocusApiError.CreateCode(401, 'WIDGET_USER_HASH_INVALID', 'x');
    try
      S.NoteError(E);
      Check(S.IdentityError, '401 no chat → error_identity');
    finally
      E.Free;
    end;
  finally
    S.Free;
  end;
end;

procedure TestChatHelpers;
var
  A, B, C, Av: TBFJson;
begin
  A := J(Msg('a', 'human', 'true', '"Bia"', '2026-09-01T10:00:00Z'));
  B := J(Msg('b', 'human', 'true', '"Bia"', '2026-09-01T10:01:59Z'));
  C := J(Msg('c', 'human', 'true', '"Bia"', '2026-09-01T10:04:00Z'));
  try
    Check(BFChatGroupedWithNext(A, B), 'mesmo autor em < 2 min agrupa');
    Check(not BFChatGroupedWithNext(B, C), 'mais de 2 min separa');
    Check(not BFChatGroupedWithNext(C, nil), 'última não agrupa');
  finally
    A.Free; B.Free; C.Free;
  end;
  A := Conv('closed', ',"close_reason":"follow_up","ticket_status":"in_progress"');
  B := Conv('closed', ',"close_reason":"closed_by_customer","ticket_status":"cancelled"');
  C := Conv('closed', ',"close_reason":"resolved","first_response_at":"2026-09-01T10:00:00Z"');
  try
    Check(BFClosingOutcome(A) = coFollowUp, 'follow_up');
    Check(BFClosingOutcome(B) = coPlain, 'plain');
    Check(BFClosingOutcome(C) = coCsat, 'servidor antigo: csat com primeira resposta');
  finally
    A.Free; B.Free; C.Free;
  end;
  A := Conv('bot', ',"agent":{"name":"Lia","avatar_url":null}');
  Av := J('{"enabled":true,"status":"online","queue_size":0,"ai_agent":{"name":"Lia","avatar_url":null}}');
  try
    CheckEq(BFChatStatusLabel('pt_BR', A), 'Com Lia, assistente virtual', 'status bot');
    Check(BFIsBotAvailability(Av), 'produto autônomo');
    Check(Pos('Lia', BFChatIntro('pt_BR', Av)) > 0, 'intro com o nome do assistente');
  finally
    A.Free; Av.Free;
  end;
end;

procedure TestCsat;
var
  V: TBFCsatVM;
  E: Exception;
begin
  V := TBFCsatVM.Create;
  try
    Check(not V.BeginSubmit, 'sem nota não envia');
    V.Rating := 4;
    V.Comment := StringOfChar('a', 2500);
    CheckEqInt(Length(V.Comment), 2000, 'comentário até 2000');
    Check(V.BeginSubmit, 'envia');
    Check(not V.BeginSubmit, 'duplo clique não envia duas vezes');
    E := EBFocusNetworkError.CreateNet(neTimeout, '');
    try
      V.ApplyError(E, 'en');
    finally
      E.Free;
    end;
    Check((V.State = csError) and (Pos('too long', V.ErrorText) > 0), 'erro de tempo explicado');
    CheckEq(V.ButtonText('en'), 'Try again', 'botão vira tentar de novo');
    Check(V.BeginSubmit, 'reenvia');
    E := EBFocusApiError.CreateCode(409, 'TICKET_NOT_RESOLVED', '');
    try
      V.ApplyError(E, 'en');
    finally
      E.Free;
    end;
    Check(V.State = csNotResolved, 'ainda não resolvido');
  finally
    V.Free;
  end;
end;

{ ── release notes ──────────────────────────────────────────────────────── }

procedure TestReleaseNotes;
var
  B: TBFBannerVM;
  Ids: TStringList;
  Sp: TBFSplashVM;
  H: TBFHistoryVM;
begin
  B := TBFBannerVM.Create;
  Ids := TStringList.Create;
  try
    Ids.CommaText := 'n2,n5,n9';
    B.SetIds(Ids);
    // n9 não está mais pendente e é ignorada; a ordem é a dos ids.
    B.ApplyPending(J('[{"id":"n5","version":"4.2","title":"b","require_acknowledgement":false,"product":{"name":"ERP","color":"#22C55E"}},' +
      '{"id":"n2","version":"4.0","title":"a","require_acknowledgement":true,"product":{"name":"ERP","color":null}}]'));
    CheckEqInt(B.Count, 2, 'fila do banner (cenário 11)');
    CheckEq(B.Current.StrOf('id'), 'n2', 'ordem dos ids');
    Check(B.RequireAck, 'exige ciência');
    CheckEq(B.EyebrowText('pt_BR'), 'Ciência exigida', 'sobretítulo de ciência');
    CheckEq(B.CounterText, '1 / 2', 'contador');
    B.ResetGate(900, 400);
    Check(not B.ConfirmEnabled and B.ShowScrollHint, 'botão travado até rolar (cenário 12)');
    B.UpdateScroll(400, 400, 900);
    Check(not B.ConfirmEnabled, 'ainda longe do fim');
    B.UpdateScroll(492, 400, 900);
    Check(B.ConfirmEnabled, 'a 8 px do fim libera');
    Check(B.BeginConfirm and B.Submitting, 'registrando');
    CheckEq(B.ButtonText('pt_BR'), 'Registrando…', 'ackSubmitting no banner');
    Check(not B.ConfirmEnabled and not B.BeginConfirm, 'sem clique duplo');
    B.ConfirmFailed;
    Check(B.Failed and not B.Submitting and B.ConfirmEnabled, 'falha: ackError e pode tentar de novo');
    CheckEq(B.Current.StrOf('id'), 'n2', 'falha: a release fica na tela');
    CheckEq(BFRN('en', 'ackError'), 'Couldn''t save your confirmation. Check your connection and try again.',
      'texto ackError');
    Check(B.BeginConfirm and not B.Failed, 'tentar de novo limpa o erro');
    CheckEq(B.Color('#6366F1'), '#6366F1', 'sem cor do produto usa a primária');
    Check(not B.Advance, 'avança para a próxima');
    Check(not B.RequireAck, 'sem ciência');
    B.ResetGate(403, 400);
    Check(B.ConfirmEnabled, 'conteúdo que não rola libera na hora');
    CheckEq(B.ButtonText('en'), 'Got it', 'botão Entendi');
    CheckEq(B.Color('#000'), '#22C55E', 'cor do produto');
    Check(B.Advance and B.IsDone, 'depois da última: rn:done');
  finally
    Ids.Free;
    B.Free;
  end;
  Sp := TBFSplashVM.Create;
  try
    Sp.ApplyList(J('[{"id":"r1","version":"1","title":"t","description":"<p>d</p>","published_at":null,"product":{"color":null}}]'));
    Check(Sp.Visible(True) and not Sp.Visible(False), 'splash respeita showReleaseNotes');
    CheckEq(Sp.CountText('en'), '1 update waiting for you. Mark it as read to continue.', 'contagem');
    Sp.Dismiss;
    Check(not Sp.Visible(True), 'pular por agora');
    Sp.WidgetReopened;
    Check(Sp.Visible(True), 'volta ao reabrir');
  finally
    Sp.Free;
  end;
  H := TBFHistoryVM.Create;
  try
    Check(not H.IsEmpty, 'carregando não é vazio');
    H.ApplyChangelog(J('{"products":[{"current_version":"4.2.0"}],"notes":[' +
      '{"id":"a","version":"4.2.0","is_current":true,"require_acknowledgement":true,"published_at":"2026-09-14T12:00:00Z","product":{"color":null}},' +
      '{"id":"b","version":"4.1.0","is_current":false,"require_acknowledgement":false,"published_at":null,"product":{"color":"#111111"}}]}'));
    CheckEq(H.CurrentVersion, '4.2.0', 'versão atual (cenário 13)');
    Check(H.Note(0).BoolOf('is_current') and H.Note(0).BoolOf('require_acknowledgement'), 'destaque e ⚠');
    CheckEq(H.DateText(0, 'en'), 'Sep 14, 2026', 'data no idioma (en)');
    Check(Pos(' de set. de 2026', H.DateText(0, 'pt_BR')) > 0, 'data no idioma (pt)');
    CheckEq(H.DateText(1, 'en'), '', 'sem data');
  finally
    H.Free;
  end;
end;

const
  // Fila do GET /widget/release-notes (published_at crescente): as que exigem ciência + a
  // mais recente que não exige.
  SPLASH_QUEUE =
    '[{"id":"a1","version":"4.0","title":"a","description":"<p>a</p>","require_acknowledgement":true,' +
    '"product":{"name":"ERP","color":"#22C55E"}},' +
    '{"id":"a2","version":"4.1","title":"b","description":"<p>b</p>","require_acknowledgement":true,' +
    '"product":{"name":"ERP","color":null}},' +
    '{"id":"n3","version":"4.2","title":"c","description":"<p>c</p>","require_acknowledgement":false,' +
    '"product":{"name":"ERP","color":null}}]';

procedure TestSplashAck;
var
  Sp: TBFSplashVM;
begin
  Sp := TBFSplashVM.Create;
  try
    Sp.ApplyList(J(SPLASH_QUEUE));
    Check(Sp.Locked, 'exige ciência: trava a lista');
    CheckEqInt(Sp.AckCount, 2, 'duas na trava');
    CheckEq(Sp.AckNote.StrOf('id'), 'a1', 'mais antiga primeiro');
    CheckEq(Sp.AckCounterText, '1 / 2', 'contador');
    CheckEq(Sp.AckColor('#6366F1'), '#22C55E', 'cor do produto');
    CheckEqInt(Sp.Count, 1, 'cartões só das que não exigem');
    Check(Sp.Visible(True) and not Sp.Visible(False), 'respeita showReleaseNotes');
    Sp.Dismiss;
    Check(Sp.Visible(True) and Sp.Locked, 'sem pular com ciência pendente');
    // Trava de rolagem (mesmas regras do banner).
    Sp.ResetGate(900, 400);
    Check(not Sp.AckEnabled and Sp.ShowScrollHint, 'botão só depois de rolar');
    Check(not Sp.BeginAck and not Sp.Submitting, 'clique com a trava fechada não envia');
    Sp.UpdateScroll(491, 400, 900);
    Check(not Sp.AckEnabled, 'a 9 px do fim ainda trava');
    Sp.UpdateScroll(492, 400, 900);
    Check(Sp.AckEnabled and not Sp.ShowScrollHint, 'a 8 px do fim libera');
    // Reconsulta de 60 s com a mesma release: a rolagem feita continua valendo.
    Sp.ApplyList(J(SPLASH_QUEUE));
    Check(Sp.AckEnabled, 'reconsulta não trava de novo a mesma release');
    // Registrando / erro.
    Check(Sp.BeginAck and Sp.Submitting, 'registra');
    Check(not Sp.AckEnabled and not Sp.BeginAck, 'sem clique duplo');
    CheckEq(Sp.AckButtonText('pt_BR'), 'Registrando…', 'ackSubmitting');
    CheckEq(Sp.AckButtonText('es'), 'Registrando…', 'ackSubmitting (es)');
    Sp.AckError;
    Check(Sp.AckFailed and not Sp.Submitting, 'falha: ackError');
    CheckEq(Sp.AckNote.StrOf('id'), 'a1', 'falha: a release fica');
    CheckEq(Sp.AckButtonText('en'), 'I have read and acknowledge the new features and changes',
      'volta ao ackButton');
    CheckEq(BFRN('pt_BR', 'ackError'), 'Não foi possível registrar. Verifique a conexão e tente de novo.',
      'texto ackError');
    Check(Sp.BeginAck and not Sp.AckFailed, 'tentar de novo limpa o erro');
    Sp.AckDone('a1');
    CheckEq(Sp.AckNote.StrOf('id'), 'a2', 'próxima da fila');
    CheckEq(Sp.AckCounterText, '', 'última: sem contador');
    Check(not Sp.AckEnabled and not Sp.AckFailed and not Sp.Submitting, 'trava reinicia na próxima');
    Sp.ResetGate(403, 400);
    Check(Sp.AckEnabled, 'conteúdo que não rola libera na hora');
    Check(Sp.BeginAck, 'registra a segunda');
    Sp.AckDone('a2');
    Check(not Sp.Locked, 'ciência toda registrada: destrava');
    Check(not Sp.Visible(True), 'o pular dado antes vale para os cartões');
    Sp.WidgetReopened;
    Check(Sp.Visible(True) and (Sp.Count = 1), 'cartões voltam ao reabrir');
    // "Pular" só esconde o que não exige; ciência publicada depois trava de novo.
    Sp.Dismiss;
    Check(not Sp.Visible(True), 'pular por agora (sem ciência)');
    Sp.ApplyList(J('[{"id":"a9","version":"4.3","title":"d","require_acknowledgement":true,"product":null},' +
      '{"id":"n3","version":"4.2","title":"c","require_acknowledgement":false,"product":null}]'));
    Check(Sp.Visible(True) and Sp.Locked, 'ciência publicada depois do pular trava de novo');
    CheckEq(Sp.AckNote.StrOf('id'), 'a9', 'a nova na trava');
    CheckEq(Sp.AckColor('#6366F1'), '#6366F1', 'sem produto: primária');
    Check(not Sp.AckEnabled, 'release nova começa travada');
    Sp.ApplyList(J('[]'));
    Check(not Sp.Visible(True) and not Sp.Locked, 'fila vazia: nada');
  finally
    Sp.Free;
  end;
end;

type
  { Transporte falso: guarda a URL e responde 200 com lista vazia (sem rede). }
  TRecordingHttp = class(TInterfacedObject, IBFocusHttp)
  public
    LastUrl: string;
    procedure Execute(Request: TBFHttpRequest; Response: TBFHttpResponse);
  end;

procedure TRecordingHttp.Execute(Request: TBFHttpRequest; Response: TBFHttpResponse);
var
  B: TBFRaw;
begin
  LastUrl := Request.Url;
  B := '{"data":[]}';
  Response.Status := 200;
  Response.Body.WriteBuffer(B[1], Length(B));
end;

procedure TestSplashRequest;
var
  Rec: TRecordingHttp;
  Http: IBFocusHttp;
  Cfg: TBFocusConfig;
  Api: TBFocusApi;
begin
  Rec := TRecordingHttp.Create;
  Http := Rec;
  Cfg := TBFocusConfig.Create;
  try
    Cfg.PublishableKey := 'bf_pk_test_123';
    Cfg.AppId := 'com.empresa.erp';
    Cfg.User.ExternalId := 'USR-1';
    Cfg.Customer.ExternalId := 'ACME-1';
    Cfg.Product := 'erp';
    Cfg.Audience := 'external';
    Api := TBFocusApi.Create(Cfg, Http);
    try
      Api.ListReleaseNotes.Free;
      Check(Pos('/api/v1/widget/release-notes?product=erp&audience=external', Rec.LastUrl) > 0,
        'splash pede com o product e o audience do widget: ' + Rec.LastUrl);
    finally
      Api.Free;
    end;
  finally
    Cfg.Free;
  end;
end;

procedure RunVMTests;
begin
  RunTest('vm: leitura local e lista', TestReadStateAndList);
  RunTest('vm: novo chamado', TestNewTicket);
  RunTest('vm: detalhe', TestDetail);
  RunTest('vm: chat (sessão, fila, poll)', TestChatSession);
  RunTest('vm: chat (agrupamento, desfecho, assistente)', TestChatHelpers);
  RunTest('vm: CSAT', TestCsat);
  RunTest('vm: release notes (banner, splash, histórico)', TestReleaseNotes);
  RunTest('vm: splash com ciência (trava, fila, pular)', TestSplashAck);
  RunTest('vm: splash pede product e audience', TestSplashRequest);
end;

end.
