unit BFocusLauncher;

{ Lógica do launcher sem UI nem timer (BRIEF §4.1–4.2), igual para o híbrido e para a UI
  nativa:
  - Fetch: a chamada do launcher-state (roda numa thread; nunca levanta exceção);
  - Apply: aplica o resultado no badge, na pílula e decide banner/notificação/erro;
  - regras de visibilidade: aberto ignora o estado; unread/seen só com o widget aberto.
  Quem usa (TBFocusWidgetBase) cuida do relógio, das threads e da renovação do userHash. }

{$I BFocusDefines.inc}

interface

uses
  SysUtils, Classes, BFocusText, BFocusJson, BFocusHttp, BFocusConfig, BFocusModels,
  BFocusStorage, BFocusApi;

type
  TBFLauncherEvent = (leBadge, lePill, lePrimary, leError, leBanner, leNotify,
    leChat, leFirstCall);
  TBFLauncherEvents = set of TBFLauncherEvent;

  { Resultado de uma consulta (seguro para passar entre threads). }
  TBFLauncherFetch = class
  public
    Ok: Boolean;
    Data: TBFJson;           // "data" do launcher-state (dono: este objeto)
    Status: Integer;         // status HTTP de erro (0 = rede)
    ErrorCode: string;       // código de máquina (WIDGET_USER_HASH_INVALID…)
    NetError: TBFNetError;
    destructor Destroy; override;
    function IsIdentityError: Boolean;
  end;

  TBFLauncherCore = class
  private
    FConfig: TBFocusConfig;
    FStorage: IBFocusStorage;
    FBadge: TBFBadgeModel;
    FPill: TBFPill;
    FPrimaryColor: string;
    FChatEnabled: Boolean;
    FActiveConversationId: string;
    FOpenCount: Integer;
    FTotalCount: Integer;
    FFirstCallDone: Boolean;
    FBannerOpenKey: string;
    FLastErrorCode: string;
    FNotifiedCode: string;
    FBrowserMode: Boolean;
    procedure PersistLastSeen;
  public
    constructor Create(Config: TBFocusConfig; Storage: IBFocusStorage);
    destructor Destroy; override;
    { Consulta o launcher-state. Seguro em thread (a Api é imutável). }
    class function Fetch(Api: TBFocusApi): TBFLauncherFetch;
    { Aplica o resultado (thread principal). Erro de identidade (401) ou outro 4xx vira
      leError com LastErrorCode, uma vez por código até o próximo sucesso (BRIEF §4.1).
      Com userHashProvider, quem chama pede um hash novo e repete ANTES de chamar Apply
      (ver NeedsHashRetry): só a repetição recusada chega aqui como erro. }
    function Apply(F: TBFLauncherFetch): TBFLauncherEvents;
    { True quando vale pedir um userHash novo e repetir a chamada. }
    class function NeedsHashRetry(F: TBFLauncherFetch): Boolean;
    { Widget visível / escondido: o badge passa a seguir o embed. }
    procedure WidgetOpened;
    procedure WidgetClosed;
    function HandleUnread(Count: Integer): TBFLauncherEvents;
    function HandleSeen(const LatestEventAt: string): TBFLauncherEvents;
    function HandleBranding(const Color: string): TBFLauncherEvents;
    { Banner: não reabre o mesmo conjunto de ids enquanto ele estiver aberto. }
    function ShouldOpenBanner: Boolean;
    procedure BannerOpened;
    procedure BannerClosed;
    function BannerIsOpen: Boolean;
    procedure LoadPersisted;
    procedure ClearPersisted;
    { Troca de identidade: volta ao estado de "primeira chamada". }
    procedure ResetSession;

    property Config: TBFocusConfig read FConfig;
    property Badge: TBFBadgeModel read FBadge;
    property Pill: TBFPill read FPill;
    property PrimaryColor: string read FPrimaryColor;
    property ChatEnabled: Boolean read FChatEnabled;
    property ActiveConversationId: string read FActiveConversationId;
    property OpenCount: Integer read FOpenCount;
    property TotalCount: Integer read FTotalCount;
    property FirstCallDone: Boolean read FFirstCallDone;
    property LastErrorCode: string read FLastErrorCode;
    { Modo navegador (sem WebView): o banner de ciência não abre sozinho (BRIEF §4.5). }
    property BrowserMode: Boolean read FBrowserMode write FBrowserMode;
  end;

implementation

{ ── TBFLauncherFetch ───────────────────────────────────────────────────── }

destructor TBFLauncherFetch.Destroy;
begin
  Data.Free;
  inherited Destroy;
end;

function TBFLauncherFetch.IsIdentityError: Boolean;
begin
  { WIDGET_USER_HASH_EXPIRED: assinatura v2 fora dos 7 dias — pedir outra resolve. }
  Result := (Status = 401) and ((ErrorCode = 'WIDGET_USER_HASH_INVALID') or
    (ErrorCode = 'WIDGET_USER_HASH_EXPIRED') or
    (ErrorCode = 'WIDGET_VERIFIED_SESSION_REQUIRED'));
end;

{ ── TBFLauncherCore ────────────────────────────────────────────────────── }

constructor TBFLauncherCore.Create(Config: TBFocusConfig; Storage: IBFocusStorage);
begin
  inherited Create;
  FConfig := Config;
  FStorage := Storage;
  FBadge := TBFBadgeModel.Create;
  FPill := TBFPill.Create;
end;

destructor TBFLauncherCore.Destroy;
begin
  FBadge.Free;
  FPill.Free;
  inherited Destroy;
end;

procedure TBFLauncherCore.LoadPersisted;
begin
  if FStorage <> nil then
    FBadge.LastSeen := FStorage.ReadValue(BFLastSeenStorageKey(FConfig));
end;

procedure TBFLauncherCore.PersistLastSeen;
begin
  if (FStorage <> nil) and (FBadge.LastSeen <> '') then
    FStorage.WriteValue(BFLastSeenStorageKey(FConfig), FBadge.LastSeen);
end;

procedure TBFLauncherCore.ClearPersisted;
begin
  if FStorage <> nil then
  begin
    FStorage.DeleteValue(BFLastSeenStorageKey(FConfig));
    FStorage.DeletePrefix('bf:read:' + BFScopeKey(FConfig) + ':');
  end;
  FBadge.LastSeen := '';
  FBadge.Text := '';
end;

procedure TBFLauncherCore.ResetSession;
begin
  FFirstCallDone := False;
  FBannerOpenKey := '';
  FNotifiedCode := '';
  FBadge.Text := '';
  FBadge.IsOpen := False;
  LoadPersisted;
end;

class function TBFLauncherCore.Fetch(Api: TBFocusApi): TBFLauncherFetch;
begin
  Result := TBFLauncherFetch.Create;
  try
    Result.Data := Api.LauncherState;
    Result.Ok := (Result.Data <> nil) and Result.Data.IsObject;
  except
    on E: EBFocusApiError do
    begin
      Result.Status := E.Status;
      Result.ErrorCode := E.Code;
    end;
    on E: EBFocusNetworkError do
      Result.NetError := E.Kind;
    on E: Exception do
      Result.NetError := neNetwork;
  end;
end;

function TBFLauncherCore.Apply(F: TBFLauncherFetch): TBFLauncherEvents;
var
  PrevText, Color, Latest: string;
  Tickets, Chat, RN: TBFJson;
begin
  Result := [];
  if not FFirstCallDone then
  begin
    FFirstCallDone := True;
    Include(Result, leFirstCall);
  end;
  if (F = nil) or not F.Ok then
  begin
    // Rede ou 5xx: silêncio, tenta no próximo ciclo. 4xx: avisa o integrador uma vez.
    if (F <> nil) and (F.Status >= 400) and (F.Status < 500) then
    begin
      if F.ErrorCode <> '' then
        FLastErrorCode := F.ErrorCode
      else
        FLastErrorCode := 'HTTP_' + IntToStr(F.Status);
      if FLastErrorCode <> FNotifiedCode then
      begin
        FNotifiedCode := FLastErrorCode;
        Include(Result, leError);
      end;
    end;
    Exit;
  end;
  FNotifiedCode := '';
  FLastErrorCode := '';

  Color := F.Data.StrOf('primary_color');
  if (Color <> '') and (Color <> FPrimaryColor) then
  begin
    FPrimaryColor := Color;
    Include(Result, lePrimary);
  end;

  Tickets := F.Data.ObjOf('tickets');
  PrevText := FBadge.Text;
  if Tickets <> nil then
  begin
    FOpenCount := Integer(Tickets.IntOf('open_count'));
    FTotalCount := Integer(Tickets.IntOf('total_count'));
    Latest := Tickets.StrOf('latest_event_at');
    if FBadge.ApplyState(Latest) then
      PersistLastSeen;
  end;
  if FBadge.Text <> PrevText then
  begin
    Include(Result, leBadge);
    // Desktop: a transição para "•" vira notificação do sistema (BRIEF §4.5).
    if FConfig.Notifications and (FBadge.Text = BFBadgeDot) then
      Include(Result, leNotify);
  end;

  Chat := F.Data.ObjOf('chat');
  if Chat <> nil then
  begin
    if (Chat.BoolOf('enabled') <> FChatEnabled) or
      (Chat.StrOf('active_conversation_id') <> FActiveConversationId) then
      Include(Result, leChat);
    FChatEnabled := Chat.BoolOf('enabled');
    FActiveConversationId := Chat.StrOf('active_conversation_id');
  end;

  RN := F.Data.ObjOf('release_notes');
  if FPill.Apply(RN) then
    Include(Result, lePill);
  if ShouldOpenBanner then
    Include(Result, leBanner);
end;

procedure TBFLauncherCore.WidgetOpened;
begin
  FBadge.Open;
end;

procedure TBFLauncherCore.WidgetClosed;
begin
  FBadge.Close;
end;

function TBFLauncherCore.HandleUnread(Count: Integer): TBFLauncherEvents;
var
  Prev: string;
begin
  Result := [];
  Prev := FBadge.Text;
  FBadge.ApplyUnread(Count);
  if FBadge.Text <> Prev then
    Include(Result, leBadge);
end;

function TBFLauncherCore.HandleSeen(const LatestEventAt: string): TBFLauncherEvents;
begin
  Result := [];
  if FBadge.ApplySeen(LatestEventAt) then
    PersistLastSeen;
end;

function TBFLauncherCore.HandleBranding(const Color: string): TBFLauncherEvents;
begin
  Result := [];
  if (Color <> '') and (Color <> FPrimaryColor) then
  begin
    FPrimaryColor := Color;
    Include(Result, lePrimary);
  end;
end;

class function TBFLauncherCore.NeedsHashRetry(F: TBFLauncherFetch): Boolean;
begin
  Result := (F <> nil) and F.IsIdentityError;
end;

function TBFLauncherCore.ShouldOpenBanner: Boolean;
begin
  Result := FConfig.AutoShowReleaseBanner and not FBrowserMode and (FPill.BannerIds.Count > 0) and
    (FBannerOpenKey <> FPill.BannerKey) and (FBannerOpenKey = '');
end;

procedure TBFLauncherCore.BannerOpened;
begin
  FBannerOpenKey := FPill.BannerKey;
end;

procedure TBFLauncherCore.BannerClosed;
begin
  FBannerOpenKey := '';
end;

function TBFLauncherCore.BannerIsOpen: Boolean;
begin
  Result := FBannerOpenKey <> '';
end;

end.
