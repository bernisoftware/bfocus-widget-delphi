unit BFocusModels;

{ Modelos sem UI do launcher: "•"/contador do botão (idêntico ao widget.js), pílula de
  versão, push (registro e handlePush) e as mensagens do Host Protocol v1. }

{$I BFocusDefines.inc}

interface

uses
  SysUtils, Classes, BFocusText, BFocusJson, BFocusHttp, BFocusConfig;

type
  { Badge do botão (scenarios.badge):
    ApplyState(latest) — só com o widget FECHADO. latest vazio: nada. Sem last_seen: grava
                         e não acende. latest > last_seen (como instante): "•".
    ApplyUnread(n)     — texto = n (>99 = "99+"), 0 = "".
    ApplySeen(ts)      — last_seen = ts.
    Open / Close       — aberto ignora ApplyState. }
  TBFBadgeModel = class
  public
    LastSeen: string;
    Text: string;
    IsOpen: Boolean;
    { True quando LastSeen mudou (quem chama grava de forma persistente). }
    function ApplyState(const LatestEventAt: string): Boolean;
    procedure ApplyUnread(Count: Integer);
    function ApplySeen(const LatestEventAt: string): Boolean;
    procedure Open;
    procedure Close;
  end;

  { Pílula de versão a partir de release_notes do launcher-state (scenarios.pill). }
  TBFPill = class
  public
    Text: string;
    Dot: Boolean;
    Color: string;         // cor do produto (a pílula usa primary_color; esta é reserva)
    BannerIds: TStringList;
    constructor Create;
    destructor Destroy; override;
    { True quando algo visível mudou. }
    function Apply(ReleaseNotes: TBFJson): Boolean;
    function BannerKey: string; // ids juntos, para comparar filas
  end;

{ '•' e '—' na codificação nativa (Delphi 7 = página ANSI). }
function BFBadgeDot: string;
function BFEmDash: string;
function BFBadgeCountLabel(Count: Integer): string;
function BFPillLabel(const BadgeVersion: string): string;

{ Notificação do desktop (BRIEF §4.5), no idioma do widget. }
function BFNotificationTitle(const Locale: string): string;
function BFNotificationBody(const Locale: string): string;

{ ── push (BRIEF §4.4) ── }
function BFPushRegisterRequest(Config: TBFocusConfig; const Token, Platform: string): TBFHttpRequest;
function BFPushUnregisterRequest(Config: TBFocusConfig; const Token: string): TBFHttpRequest;
{ True se o push é do bFocus; Navigate recebe o payload do bfocus:navigate (dono: quem chama). }
function BFHandlePushJson(Data: TBFJson; out Navigate: TBFJson): Boolean;
{ Mesma regra com os dados como pares Nome=Valor (formato comum nos apps desktop). }
function BFHandlePushStrings(Data: TStrings; out Navigate: TBFJson): Boolean;

{ ── Host Protocol v1 (§3) ── }
{ Tipos que o embed envia e o pacote trata. Desconhecido = ignorar. }
function BFIsKnownEmbedType(const MsgType: string): Boolean;
{ Mensagem do embed (string JSON) → objeto (type, payload); nil se inválida, fora do
  prefixo bfocus: ou de tipo desconhecido. }
function BFParseHostMessage(const Raw: TBFRaw; out MsgType: string): TBFJson;
{ Mensagem para o embed. Payload (pode ser nil) passa a ser da função. }
function BFHostCommand(const MsgType: string; Payload: TBFJson): TBFRaw;
function BFNavigatePayload(View: TBFOpenView; const TicketId, ConversationId: string): TBFJson;
{ JavaScript que entrega a mensagem ao embed (host → embed). }
function BFReceiveScript(const MessageJson: TBFRaw): string;

const
  BF_FLUSH_SCRIPT = 'window.bFocusEmbed && window.bFocusEmbed.flush()';

implementation

{ ── símbolos ───────────────────────────────────────────────────────────── }

function BFBadgeDot: string;
begin
  {$IFDEF BF_UNICODE}
  Result := #$2022;
  {$ELSE}
  Result := BFFromUtf8(#$E2#$80#$A2);
  {$ENDIF}
end;

function BFEmDash: string;
begin
  {$IFDEF BF_UNICODE}
  Result := #$2014;
  {$ELSE}
  Result := BFFromUtf8(#$E2#$80#$94);
  {$ENDIF}
end;

function BFBadgeCountLabel(Count: Integer): string;
begin
  if Count <= 0 then
    Result := ''
  else if Count > 99 then
    Result := '99+'
  else
    Result := IntToStr(Count);
end;

function BFNotificationTitle(const Locale: string): string;
begin
  if Locale = 'en' then Result := 'Support'
  else if Locale = 'es' then Result := 'Soporte'
  else Result := 'Suporte';
end;

function BFNotificationBody(const Locale: string): string;
begin
  if Locale = 'en' then Result := 'There are updates on your tickets.'
  else if Locale = 'es' then Result := 'Hay novedades en tus tickets.'
  else Result := BFFromUtf8('H'#$C3#$A1' novidades nos seus chamados.');
end;

{ ── badge ──────────────────────────────────────────────────────────────── }

function TBFBadgeModel.ApplyState(const LatestEventAt: string): Boolean;
var
  Latest, Seen: Int64;
begin
  Result := False;
  if IsOpen or (LatestEventAt = '') then
    Exit;
  if LastSeen = '' then
  begin
    // Primeira visita: só grava a base, sem acender.
    LastSeen := LatestEventAt;
    Result := True;
    Exit;
  end;
  if not BFIsoToUnixMs(LatestEventAt, Latest) then
    Exit;
  if not BFIsoToUnixMs(LastSeen, Seen) then
  begin
    // Base ilegível: recomeça a partir de agora, sem acender.
    LastSeen := LatestEventAt;
    Result := True;
    Exit;
  end;
  if Latest > Seen then
    Text := BFBadgeDot;
end;

procedure TBFBadgeModel.ApplyUnread(Count: Integer);
begin
  Text := BFBadgeCountLabel(Count);
end;

function TBFBadgeModel.ApplySeen(const LatestEventAt: string): Boolean;
begin
  Result := (LatestEventAt <> '') and (LatestEventAt <> LastSeen);
  if Result then
    LastSeen := LatestEventAt;
end;

procedure TBFBadgeModel.Open;
begin
  IsOpen := True;
end;

procedure TBFBadgeModel.Close;
begin
  IsOpen := False;
end;

{ ── pílula ─────────────────────────────────────────────────────────────── }

function BFPillLabel(const BadgeVersion: string): string;
var
  V: string;
begin
  V := Trim(BadgeVersion);
  if (V <> '') and ((V[1] = 'v') or (V[1] = 'V')) then
    Delete(V, 1, 1);
  if V = '' then
    Result := BFEmDash
  else
    Result := 'v' + V;
end;

constructor TBFPill.Create;
begin
  inherited Create;
  BannerIds := TStringList.Create;
  Text := BFEmDash;
end;

destructor TBFPill.Destroy;
begin
  BannerIds.Free;
  inherited Destroy;
end;

function TBFPill.BannerKey: string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to BannerIds.Count - 1 do
  begin
    if I > 0 then
      Result := Result + ',';
    Result := Result + BannerIds[I];
  end;
end;

function TBFPill.Apply(ReleaseNotes: TBFJson): Boolean;
var
  NewText, OldKey, NewColor: string;
  NewDot: Boolean;
  Ids, Product: TBFJson;
  I: Integer;
begin
  OldKey := BannerKey;
  if ReleaseNotes = nil then
  begin
    NewText := BFEmDash;
    NewDot := False;
    NewColor := '';
    BannerIds.Clear;
  end
  else
  begin
    NewText := BFPillLabel(ReleaseNotes.StrOf('badge_version'));
    NewDot := ReleaseNotes.BoolOf('has_unseen');
    Product := ReleaseNotes.ObjOf('product');
    if Product <> nil then
      NewColor := Product.StrOf('color')
    else
      NewColor := '';
    BannerIds.Clear;
    Ids := ReleaseNotes.ArrOf('banner_ids');
    if Ids <> nil then
      for I := 0 to Ids.Count - 1 do
        BannerIds.Add(Ids.Item(I).AsString);
  end;
  Result := (NewText <> Text) or (NewDot <> Dot) or (OldKey <> BannerKey) or (NewColor <> Color);
  Text := NewText;
  Dot := NewDot;
  Color := NewColor;
end;

{ ── push ───────────────────────────────────────────────────────────────── }

function BFPushRegisterRequest(Config: TBFocusConfig; const Token, Platform: string): TBFHttpRequest;
var
  Body: TBFJson;
begin
  Result := TBFHttpRequest.Create('POST', BFApiBase(Config) + '/api/v1/widget/push/devices');
  BFApplyWidgetHeaders(Config, Result, True, True);
  Body := TBFJson.NewObject;
  try
    Body.PutStr('token', Token);
    Body.PutStr('platform', Platform);
    Body.PutStr('app_id', BFLowerAscii(Trim(Config.AppId)));
    Result.SetBodyRaw(Body.ToJson);
  finally
    Body.Free;
  end;
end;

function BFPushUnregisterRequest(Config: TBFocusConfig; const Token: string): TBFHttpRequest;
var
  Body: TBFJson;
begin
  Result := TBFHttpRequest.Create('POST',
    BFApiBase(Config) + '/api/v1/widget/push/devices/unregister');
  BFApplyWidgetHeaders(Config, Result, True, True);
  Body := TBFJson.NewObject;
  try
    Body.PutStr('token', Token);
    Result.SetBodyRaw(Body.ToJson);
  finally
    Body.Free;
  end;
end;

function HandlePush(const IsBFocus, MsgType, TicketId, ConversationId: string;
  out Navigate: TBFJson): Boolean;
begin
  Navigate := nil;
  Result := IsBFocus = '1';
  if not Result then
    Exit;
  if ((MsgType = 'ticket.reply') or (MsgType = 'ticket.status')) and (TicketId <> '') then
    Navigate := BFNavigatePayload(ovTicket, TicketId, '')
  else if (MsgType = 'chat.message') and (ConversationId <> '') then
    Navigate := BFNavigatePayload(ovChat, '', ConversationId)
  else
    Navigate := BFNavigatePayload(ovList, '', '');
end;

function BFHandlePushJson(Data: TBFJson; out Navigate: TBFJson): Boolean;
begin
  Navigate := nil;
  Result := False;
  if (Data = nil) or not Data.IsObject then
    Exit;
  Result := HandlePush(Data.StrOf('bfocus'), Data.StrOf('type'), Data.StrOf('ticket_id'),
    Data.StrOf('conversation_id'), Navigate);
end;

function BFHandlePushStrings(Data: TStrings; out Navigate: TBFJson): Boolean;
begin
  Navigate := nil;
  Result := False;
  if Data = nil then
    Exit;
  Result := HandlePush(Data.Values['bfocus'], Data.Values['type'], Data.Values['ticket_id'],
    Data.Values['conversation_id'], Navigate);
end;

{ ── Host Protocol ──────────────────────────────────────────────────────── }

const
  { 'bfocus:identity-expired' é aditiva: a assinatura v2 venceu (7 dias) e o embed
    pede outra ao OnUserHashRequest. Host antigo que ignora segue funcionando. }
  KNOWN_TYPES: array[0..11] of string = (
    'bfocus:ready', 'bfocus:close', 'bfocus:unread', 'bfocus:seen', 'bfocus:branding',
    'bfocus:error', 'bfocus:identity-expired', 'bfocus:openExternal', 'bfocus:download',
    'bfocus:rn:branding', 'bfocus:rn:done', 'bfocus:rn:closeHistory');

function BFIsKnownEmbedType(const MsgType: string): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(KNOWN_TYPES) do
    if KNOWN_TYPES[I] = MsgType then
    begin
      Result := True;
      Exit;
    end;
  Result := False;
end;

function BFParseHostMessage(const Raw: TBFRaw; out MsgType: string): TBFJson;
var
  T: TBFJson;
begin
  MsgType := '';
  Result := TBFJson.TryParse(Raw);
  if Result = nil then
    Exit;
  T := nil;
  if Result.IsObject then
    T := Result.Get('type');
  if (T = nil) or (T.Kind <> jkString) then
  begin
    FreeAndNil(Result);
    Exit;
  end;
  MsgType := T.AsString;
  if not BFIsKnownEmbedType(MsgType) then
  begin
    MsgType := '';
    FreeAndNil(Result);
  end;
end;

function BFHostCommand(const MsgType: string; Payload: TBFJson): TBFRaw;
var
  Msg: TBFJson;
begin
  Msg := TBFJson.NewObject;
  try
    Msg.PutStr('type', MsgType);
    if Payload <> nil then
      Msg.Put('payload', Payload);
    Result := Msg.ToJson;
  finally
    Msg.Free;
  end;
end;

function BFNavigatePayload(View: TBFOpenView; const TicketId, ConversationId: string): TBFJson;
begin
  Result := TBFJson.NewObject;
  case View of
    ovTicket:
      begin
        Result.PutStr('view', 'ticket');
        Result.PutStr('ticketId', TicketId);
      end;
    ovChat:
      begin
        Result.PutStr('view', 'chat');
        if ConversationId <> '' then
          Result.PutStr('conversationId', ConversationId);
      end;
    ovNew: Result.PutStr('view', 'new');
  else
    Result.PutStr('view', 'list');
  end;
end;

function BFReceiveScript(const MessageJson: TBFRaw): string;
begin
  Result := 'window.bFocusEmbed && window.bFocusEmbed.receive(' + BFFromUtf8(MessageJson) + ')';
end;

end.
