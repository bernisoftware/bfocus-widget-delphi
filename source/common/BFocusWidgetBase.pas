unit BFocusWidgetBase;

{ Base não visual dos componentes TBFocusWidget (híbrido, Delphi 10.4+) e
  TBFocusNativeWidget (UI nativa, Delphi 7+ e Lazarus). Cuida do que é igual nos dois
  (BRIEF §3–4): configuração, consulta periódica do launcher-state (enquanto o app estiver
  aberto, com o widget fechado), badge/pílula persistentes, banner, renovação do userHash,
  notificação do sistema e os callbacks do integrador. As subclasses só mostram telas. }

{$I BFocusDefines.inc}

interface

uses
  SysUtils, Classes, ExtCtrls, Forms, BFocusText, BFocusJson, BFocusHttp, BFocusConfig,
  BFocusModels, BFocusStorage, BFocusApi, BFocusLauncher, BFocusAsync, BFocusNotifier;

type
  TBFBadgeEvent = procedure(Sender: TObject; const ALabel: string) of object;
  TBFReleaseNotesEvent = procedure(Sender: TObject; const ALabel: string; ADot: Boolean;
    BannerIds: TStrings) of object;
  TBFErrorEvent = procedure(Sender: TObject; const Code, Detail: string) of object;
  { userHashProvider: devolva o hash novo calculado no SEU servidor (síncrono). }
  TBFUserHashEvent = procedure(Sender: TObject; var UserHash: string) of object;

  { Botão/pílula que acompanham o estado do widget. }
  IBFocusWidgetListener = interface
    ['{5E0C8A13-7B6D-4C29-9F41-A2D3B7E6C590}']
    procedure BFocusStateChanged(Sender: TObject);
  end;

  TBFocusWidgetBase = class(TComponent)
  private
    FConfig: TBFocusConfig;
    FHttp: IBFocusHttp;
    FStorage: IBFocusStorage;
    FLauncher: TBFLauncherCore;
    FApi: TBFocusApi;
    FTimer: TTimer;
    FNotifier: TBFNotifier;
    FListeners: TList;
    FInitialized: Boolean;
    FFetching: Boolean;
    FHashRetried: Boolean;
    FWidgetOpen: Boolean;
    FPendingOpen: Boolean;
    FPendingView: TBFOpenView;
    FPendingId: string;
    FLocale: string;
    FOnBadgeChanged: TBFBadgeEvent;
    FOnReleaseNotesChanged: TBFReleaseNotesEvent;
    FOnError: TBFErrorEvent;
    FOnOpen: TNotifyEvent;
    FOnClose: TNotifyEvent;
    FOnUserHashRequest: TBFUserHashEvent;
    FPushToken: string;
    procedure SetConfig(Value: TBFocusConfig);
    procedure TimerTick(Sender: TObject);
    function FetchWork(Job: TBFJob): TBFJson;
    procedure FetchDone(Job: TBFJob);
    procedure NotifierClick(Sender: TObject);
    function PushWork(Job: TBFJob): TBFJson;
    procedure PushDone(Job: TBFJob);
    procedure RestartTimer;
  protected
    { Telas (subclasses). }
    procedure DoShowWidget(View: TBFOpenView; const Id: string); virtual; abstract;
    procedure DoHideWidget; virtual; abstract;
    procedure DoOpenBanner(Ids: TStrings); virtual; abstract;
    procedure DoOpenHistory; virtual; abstract;
    { Identidade mudou ou logout: descartar telas/WebView (limpando dados da origem). }
    procedure DoResetUI(ClearData: Boolean); virtual; abstract;
    { A Api foi recriada (userHash novo): telas nativas trocam a delas. }
    procedure DoApiChanged; virtual;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure ApplyEvents(Ev: TBFLauncherEvents);
    procedure NotifyListeners;
    procedure RecreateApi;
  public
    { Chamados pelas telas nativas e pela ponte (uso interno do pacote). }
    procedure WidgetShown;
    procedure WidgetHidden;
    procedure HostUnread(Count: Integer);
    procedure HostSeen(const LatestEventAt: string);
    procedure HostBranding(const Color: string);
    procedure HostError(const Code, Detail: string);
    { Identidade recusada dentro das telas: pede hash novo uma vez; True = recarregar. }
    function HostIdentityRefresh: Boolean;
    procedure HostBannerDone;
    procedure HostBannerOpened;
    procedure SetBrowserMode(Value: Boolean);
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Valida, resolve o idioma, carrega o estado local e faz a primeira consulta. }
    procedure Init;
    procedure Open(View: TBFOpenView = ovList; const Id: string = '');
    procedure OpenTicket(const TicketId: string);
    procedure OpenNewTicket;
    procedure OpenChat;
    procedure Close;
    procedure Toggle;
    procedure OpenReleaseNotesHistory;
    procedure Refresh;
    procedure Logout;
    { Só mobile no contrato; aqui por completude (o desktop não recebe push). }
    procedure RegisterPushToken(const Token: string; const Platform: string = 'android');
    { True se o push é do bFocus; abre o widget no item certo. }
    function HandlePush(Data: TStrings): Boolean;
    procedure AddListener(Listener: TComponent);
    procedure RemoveListener(Listener: TComponent);

    function BadgeText: string;
    function PillText: string;
    function PillDot: Boolean;
    function PrimaryColor: string;
    function BannerIds: TStrings;
    property IsOpen: Boolean read FWidgetOpen;
    property Initialized: Boolean read FInitialized;
    property Locale: string read FLocale;
    property Launcher: TBFLauncherCore read FLauncher;
    property Api: TBFocusApi read FApi;
    property Storage: IBFocusStorage read FStorage write FStorage;
    property Http: IBFocusHttp read FHttp write FHttp;
  published
    property Config: TBFocusConfig read FConfig write SetConfig;
    property OnBadgeChanged: TBFBadgeEvent read FOnBadgeChanged write FOnBadgeChanged;
    property OnReleaseNotesChanged: TBFReleaseNotesEvent read FOnReleaseNotesChanged
      write FOnReleaseNotesChanged;
    property OnError: TBFErrorEvent read FOnError write FOnError;
    property OnOpen: TNotifyEvent read FOnOpen write FOnOpen;
    property OnClose: TNotifyEvent read FOnClose write FOnClose;
    property OnUserHashRequest: TBFUserHashEvent read FOnUserHashRequest write FOnUserHashRequest;
  end;

  EBFocusConfig = class(Exception);

implementation

uses
  BFocusHttpDefault;

constructor TBFocusWidgetBase.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FConfig := TBFocusConfig.Create;
  FListeners := TList.Create;
  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.OnTimer := TimerTick;
end;

destructor TBFocusWidgetBase.Destroy;
begin
  FTimer.Enabled := False;
  BFJobs.CancelOwner(Self);
  FListeners.Free;
  FApi.Free;
  FLauncher.Free;
  FConfig.Free;
  inherited Destroy;
end;

procedure TBFocusWidgetBase.SetConfig(Value: TBFocusConfig);
begin
  FConfig.Assign(Value);
end;

procedure TBFocusWidgetBase.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (FListeners <> nil) then
    FListeners.Remove(AComponent);
end;

procedure TBFocusWidgetBase.AddListener(Listener: TComponent);
begin
  if (Listener <> nil) and (FListeners.IndexOf(Listener) < 0) then
  begin
    FListeners.Add(Listener);
    Listener.FreeNotification(Self);
  end;
end;

procedure TBFocusWidgetBase.RemoveListener(Listener: TComponent);
begin
  FListeners.Remove(Listener);
end;

procedure TBFocusWidgetBase.NotifyListeners;
var
  I: Integer;
  L: IBFocusWidgetListener;
begin
  for I := FListeners.Count - 1 downto 0 do
    if Supports(TComponent(FListeners[I]), IBFocusWidgetListener, L) then
      L.BFocusStateChanged(Self);
end;

function TBFocusWidgetBase.BadgeText: string;
begin
  if FLauncher = nil then Result := '' else Result := FLauncher.Badge.Text;
end;

function TBFocusWidgetBase.PillText: string;
begin
  if FLauncher = nil then Result := BFEmDash else Result := FLauncher.Pill.Text;
end;

function TBFocusWidgetBase.PillDot: Boolean;
begin
  Result := (FLauncher <> nil) and FLauncher.Pill.Dot;
end;

function TBFocusWidgetBase.PrimaryColor: string;
begin
  if (FLauncher = nil) or (FLauncher.PrimaryColor = '') then
    Result := '#6366F1'
  else
    Result := FLauncher.PrimaryColor;
end;

function TBFocusWidgetBase.BannerIds: TStrings;
begin
  if FLauncher = nil then Result := nil else Result := FLauncher.Pill.BannerIds;
end;

procedure TBFocusWidgetBase.RecreateApi;
begin
  FreeAndNil(FApi);
  FApi := TBFocusApi.Create(FConfig, FHttp);
  DoApiChanged;
end;

procedure TBFocusWidgetBase.DoApiChanged;
begin
end;

procedure TBFocusWidgetBase.Init;
var
  Problem: string;
begin
  Problem := FConfig.Validate;
  if Problem <> '' then
    raise EBFocusConfig.Create('bFocus: ' + Problem);
  if FConfig.Locale = '' then
    FConfig.Locale := BFDeviceLocale
  else
    FConfig.Locale := BFNormalizeLocale(FConfig.Locale);
  FLocale := FConfig.Locale;
  if FHttp = nil then
    FHttp := BFDefaultHttp;
  if FStorage = nil then
    FStorage := BFDefaultStorage;
  FreeAndNil(FLauncher);
  FLauncher := TBFLauncherCore.Create(FConfig, FStorage);
  FLauncher.LoadPersisted;
  RecreateApi;
  if FConfig.Notifications and (FNotifier = nil) then
  begin
    FNotifier := TBFNotifier.Create(Self);
    FNotifier.OnClick := NotifierClick;
  end;
  FInitialized := True;
  FHashRetried := False;
  // Primeira chamada logo após o init; nada mais em paralelo com ela (cria o usuário).
  Refresh;
end;

procedure TBFocusWidgetBase.RestartTimer;
var
  Seconds: Integer;
begin
  FTimer.Enabled := False;
  Seconds := FConfig.PollIntervalSeconds;
  if Seconds < 5 then
    Seconds := 5;
  FTimer.Interval := Seconds * 1000;
  // Desktop: consulta enquanto o app estiver aberto, mesmo sem foco; só com o widget fechado.
  FTimer.Enabled := FInitialized and not FWidgetOpen;
end;

procedure TBFocusWidgetBase.TimerTick(Sender: TObject);
begin
  if not FWidgetOpen then
    Refresh;
end;

procedure TBFocusWidgetBase.Refresh;
begin
  if not FInitialized or FFetching then
    Exit;
  FFetching := True;
  BFJobs.Run(FApi, FetchWork, FetchDone, Self, []);
  RestartTimer;
end;

function TBFocusWidgetBase.FetchWork(Job: TBFJob): TBFJson;
var
  F: TBFLauncherFetch;
begin
  // Roda na thread: só a Api do job. O resultado vira um objeto simples para o Done.
  F := TBFLauncherCore.Fetch(Job.Api);
  try
    Result := TBFJson.NewObject;
    Result.PutBool('ok', F.Ok);
    Result.PutInt('status', F.Status);
    Result.PutStr('code', F.ErrorCode);
    Result.PutInt('net', Ord(F.NetError));
    if F.Data <> nil then
      Result.Put('data', F.Data.Clone);
  finally
    F.Free;
  end;
end;

procedure TBFocusWidgetBase.FetchDone(Job: TBFJob);
var
  R: TBFJson;
  F: TBFLauncherFetch;
  NewHash: string;
begin
  FFetching := False;
  R := Job.TakeData;
  if R = nil then
    Exit;
  F := TBFLauncherFetch.Create;
  try
    F.Ok := R.BoolOf('ok');
    F.Status := Integer(R.IntOf('status'));
    F.ErrorCode := R.StrOf('code');
    F.NetError := TBFNetError(R.IntOf('net'));
    F.Data := R.ExtractKey('data');
    // 401 de identidade com provider: pede um hash novo UMA vez e repete antes de avisar.
    if TBFLauncherCore.NeedsHashRetry(F) and Assigned(FOnUserHashRequest) and not FHashRetried then
    begin
      FHashRetried := True;
      NewHash := FConfig.UserHash;
      FOnUserHashRequest(Self, NewHash);
      if (NewHash <> '') and (NewHash <> FConfig.UserHash) then
      begin
        FConfig.UserHash := NewHash;
        RecreateApi;
        DoResetUI(False);
        Refresh;
        Exit;
      end;
    end;
    if F.Ok then
      FHashRetried := False;
    ApplyEvents(FLauncher.Apply(F));
  finally
    F.Free;
    R.Free;
  end;
  if FPendingOpen and FLauncher.FirstCallDone then
  begin
    FPendingOpen := False;
    Open(FPendingView, FPendingId);
  end;
  if (FPushToken <> '') and FLauncher.FirstCallDone then
    RegisterPushToken(FPushToken);
end;

procedure TBFocusWidgetBase.ApplyEvents(Ev: TBFLauncherEvents);
begin
  if Ev = [] then
    Exit;
  if (leBadge in Ev) and Assigned(FOnBadgeChanged) then
    FOnBadgeChanged(Self, FLauncher.Badge.Text);
  if (lePill in Ev) and Assigned(FOnReleaseNotesChanged) then
    FOnReleaseNotesChanged(Self, FLauncher.Pill.Text, FLauncher.Pill.Dot, FLauncher.Pill.BannerIds);
  if (leError in Ev) and Assigned(FOnError) then
    FOnError(Self, FLauncher.LastErrorCode, '');
  if (leNotify in Ev) and (FNotifier <> nil) then
    FNotifier.Show(BFNotificationTitle(FLocale), BFNotificationBody(FLocale));
  if leBanner in Ev then
  begin
    FLauncher.BannerOpened;
    DoOpenBanner(FLauncher.Pill.BannerIds);
  end;
  NotifyListeners;
end;

procedure TBFocusWidgetBase.NotifierClick(Sender: TObject);
begin
  Open;
end;

procedure TBFocusWidgetBase.Open(View: TBFOpenView; const Id: string);
begin
  if not FInitialized then
    raise EBFocusConfig.Create('bFocus: chame Init antes de Open');
  if not FLauncher.FirstCallDone then
  begin
    // Nenhuma chamada em paralelo com a primeira: abre quando ela terminar.
    FPendingOpen := True;
    FPendingView := View;
    FPendingId := Id;
    Exit;
  end;
  DoShowWidget(View, Id);
end;

procedure TBFocusWidgetBase.OpenTicket(const TicketId: string);
begin
  Open(ovTicket, TicketId);
end;

procedure TBFocusWidgetBase.OpenNewTicket;
begin
  Open(ovNew, '');
end;

procedure TBFocusWidgetBase.OpenChat;
begin
  Open(ovChat, '');
end;

procedure TBFocusWidgetBase.Close;
begin
  if FWidgetOpen then
    DoHideWidget;
end;

procedure TBFocusWidgetBase.Toggle;
begin
  if FWidgetOpen then Close else Open;
end;

procedure TBFocusWidgetBase.OpenReleaseNotesHistory;
begin
  if FInitialized then
    DoOpenHistory;
end;

procedure TBFocusWidgetBase.WidgetShown;
begin
  if FWidgetOpen then
    Exit;
  FWidgetOpen := True;
  FLauncher.WidgetOpened;
  FTimer.Enabled := False; // aberto não consulta: o badge segue o embed
  if FNotifier <> nil then
    FNotifier.Hide;
  if Assigned(FOnOpen) then
    FOnOpen(Self);
  NotifyListeners;
end;

procedure TBFocusWidgetBase.WidgetHidden;
begin
  if not FWidgetOpen then
    Exit;
  FWidgetOpen := False;
  FLauncher.WidgetClosed;
  if Assigned(FOnClose) then
    FOnClose(Self);
  NotifyListeners;
  // Fechar consulta na hora e volta ao intervalo.
  Refresh;
end;

procedure TBFocusWidgetBase.HostUnread(Count: Integer);
begin
  ApplyEvents(FLauncher.HandleUnread(Count));
end;

procedure TBFocusWidgetBase.HostSeen(const LatestEventAt: string);
begin
  FLauncher.HandleSeen(LatestEventAt);
end;

procedure TBFocusWidgetBase.HostBranding(const Color: string);
begin
  if FLauncher.HandleBranding(Color) <> [] then
    NotifyListeners;
end;

procedure TBFocusWidgetBase.HostError(const Code, Detail: string);
begin
  if Assigned(FOnError) then
    FOnError(Self, Code, Detail);
end;

function TBFocusWidgetBase.HostIdentityRefresh: Boolean;
var
  NewHash: string;
begin
  Result := False;
  if not Assigned(FOnUserHashRequest) or FHashRetried then
    Exit;
  FHashRetried := True;
  NewHash := FConfig.UserHash;
  FOnUserHashRequest(Self, NewHash);
  if (NewHash <> '') and (NewHash <> FConfig.UserHash) then
  begin
    FConfig.UserHash := NewHash;
    RecreateApi;
    Result := True;
  end;
end;

procedure TBFocusWidgetBase.HostBannerOpened;
begin
  FLauncher.BannerOpened;
end;

procedure TBFocusWidgetBase.HostBannerDone;
begin
  FLauncher.BannerClosed;
  // Em bfocus:rn:done, fecha e consulta o launcher-state de novo.
  Refresh;
end;

procedure TBFocusWidgetBase.SetBrowserMode(Value: Boolean);
begin
  if FLauncher <> nil then
    FLauncher.BrowserMode := Value;
end;

procedure TBFocusWidgetBase.Logout;
begin
  FTimer.Enabled := False;
  BFJobs.CancelOwner(Self);
  FFetching := False;
  if FPushToken <> '' then
  begin
    BFJobs.Run(FApi, PushWork, nil, nil, ['unregister', FPushToken]);
    FPushToken := '';
  end;
  if FWidgetOpen then
    DoHideWidget;
  DoResetUI(True);
  if FLauncher <> nil then
    FLauncher.ClearPersisted;
  FInitialized := False;
  NotifyListeners;
end;

function TBFocusWidgetBase.PushWork(Job: TBFJob): TBFJson;
begin
  Result := nil;
  if Job.Arg(0) = 'register' then
    Job.Api.PushRegister(Job.Arg(1), Job.Arg(2))
  else
    Job.Api.PushUnregister(Job.Arg(1));
end;

procedure TBFocusWidgetBase.PushDone(Job: TBFJob);
begin
  // Falha de push não é fatal: tenta de novo quando a identidade mudar.
end;

procedure TBFocusWidgetBase.RegisterPushToken(const Token, Platform: string);
begin
  FPushToken := Token;
  // O registro espera a primeira chamada terminar (ela cria o usuário).
  if not FInitialized or not FLauncher.FirstCallDone then
    Exit;
  BFJobs.Run(FApi, PushWork, PushDone, Self, ['register', Token, Platform]);
end;

function TBFocusWidgetBase.HandlePush(Data: TStrings): Boolean;
var
  Nav: TBFJson;
  V: string;
begin
  Result := BFHandlePushStrings(Data, Nav);
  try
    if not Result or (Nav = nil) then
      Exit;
    V := Nav.StrOf('view');
    if V = 'ticket' then Open(ovTicket, Nav.StrOf('ticketId'))
    else if V = 'chat' then Open(ovChat, Nav.StrOf('conversationId'))
    else Open(ovList, '');
  finally
    Nav.Free;
  end;
end;

end.
