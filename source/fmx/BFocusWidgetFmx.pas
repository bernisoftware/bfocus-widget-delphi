unit BFocusWidgetFmx;

{ Variante FMX (Delphi 10.4+, Windows e macOS): TBFocusFmxWidget mostra o embed da CDN num
  TWebBrowser e cuida do launcher-state, badge, pílula, banner e notificação.

  Ponte JS → host no FMX: o TWebBrowser do FMX NÃO tem um evento de mensagem vinda da
  página (não há equivalente ao WebMessageReceived/WKScriptMessageHandler exposto) e o
  EvaluateJavaScript não devolve valor. Canal documentado usado aqui:
    1. depois de carregar, o host injeta window.bFocusHost (com postMessage; o canal
       "genérico" do Host Protocol v1, §2) e chama bFocusEmbed.flush();
    2. o shim põe a mensagem da vez no fragmento da URL, com um número de sequência:
       location.replace(base + '#bfq=<seq>:<json codificado>') — navegação no mesmo
       documento, sem recarregar a página (o embed já leu seus parâmetros ao iniciar);
    3. o host consulta TWebBrowser.URL a cada 200 ms; ao ver uma sequência nova, confere a
       origem, decodifica, trata a mensagem e confirma com window.__bfAck(seq), liberando
       a próxima da fila.
  Host → embed continua sendo EvaluateJavaScript("window.bFocusEmbed && ...receive(...)").
  Travar a navegação: o FMX não permite cancelar; ao detectar outra origem, o host para,
  abre o link no navegador e recarrega o embed. }

{$I BFocusDefines.inc}

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.Notification,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.WebBrowser, FMX.StdCtrls,
  FMX.Dialogs, BFocusText, BFocusJson, BFocusHttp, BFocusConfig, BFocusModels,
  BFocusStorage, BFocusApi, BFocusLauncher, BFocusAsync, BFocusI18n;

type
  TBFFmxWebKind = (fwTickets, fwBanner, fwHistory);
  TBFFmxMessageEvent = procedure(Sender: TObject; const MsgType: string; Msg: TBFJson) of object;

  TBFocusFmxWebForm = class(TForm)
  private
    FBrowser: TWebBrowser;
    FOverlay: TLabel;
    FRetry: TButton;
    FPoll: TTimer;
    FKind: TBFFmxWebKind;
    FUrl, FOrigin, FLocale: string;
    FLastSeq: Integer;
    FReady, FLocked, FAllowClose: Boolean;
    FOnMessage: TBFFmxMessageEvent;
    FOnUserClose: TNotifyEvent;
    procedure DidFinishLoad(ASender: TObject);
    procedure DidStartLoad(ASender: TObject);
    procedure DidFailLoad(ASender: TObject);
    procedure PollTick(Sender: TObject);
    procedure RetryClick(Sender: TObject);
    procedure CloseQueryHandler(Sender: TObject; var CanClose: Boolean);
    procedure InjectBridge;
  public
    constructor CreateFor(AOwner: TComponent; AKind: TBFFmxWebKind; const ALocale, AOrigin: string);
    procedure Load(const Url: string);
    procedure PostToEmbed(const MessageJson: TBFRaw);
    procedure ClearOriginData;
    procedure ForceClose;
    property Ready: Boolean read FReady;
    property OnEmbedMessage: TBFFmxMessageEvent read FOnMessage write FOnMessage;
    property OnUserClose: TNotifyEvent read FOnUserClose write FOnUserClose;
  end;

  TBFFmxBadgeEvent = procedure(Sender: TObject; const ALabel: string) of object;
  TBFFmxReleaseNotesEvent = procedure(Sender: TObject; const ALabel: string; ADot: Boolean;
    BannerIds: TStrings) of object;
  TBFFmxErrorEvent = procedure(Sender: TObject; const Code, Detail: string) of object;
  TBFFmxUserHashEvent = procedure(Sender: TObject; var UserHash: string) of object;

  TBFocusFmxWidget = class(TComponent)
  private
    FConfig: TBFocusConfig;
    FHttp: IBFocusHttp;
    FStorage: IBFocusStorage;
    FLauncher: TBFLauncherCore;
    FApi: TBFocusApi;
    FTimer: TTimer;
    FTickets, FBanner, FHistory: TBFocusFmxWebForm;
    FNotifications: TNotificationCenter;
    FInitialized, FFetching, FHashRetried, FOpen, FNeedOpenMsg: Boolean;
    FLocale: string;
    FOnBadgeChanged: TBFFmxBadgeEvent;
    FOnReleaseNotesChanged: TBFFmxReleaseNotesEvent;
    FOnError: TBFFmxErrorEvent;
    FOnOpen, FOnClose, FOnStateChanged: TNotifyEvent;
    FOnUserHashRequest: TBFFmxUserHashEvent;
    procedure SetConfig(Value: TBFocusConfig);
    function Origin: string;
    function NewForm(Kind: TBFFmxWebKind): TBFocusFmxWebForm;
    procedure TimerTick(Sender: TObject);
    function FetchWork(Job: TBFJob): TBFJson;
    procedure FetchDone(Job: TBFJob);
    procedure Apply(Ev: TBFLauncherEvents);
    procedure EmbedMessage(Sender: TObject; const MsgType: string; Msg: TBFJson);
    procedure TicketsUserClose(Sender: TObject);
    procedure NotificationReceived(Sender: TObject; ANotification: TNotification);
    function DownloadWork(Job: TBFJob): TBFJson;
    procedure DownloadDone(Job: TBFJob);
    procedure Hidden;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Init;
    procedure Open(View: TBFOpenView = ovList; const Id: string = '');
    procedure Close;
    procedure OpenReleaseNotesHistory;
    procedure Refresh;
    procedure Logout;
    function HandlePush(Data: TStrings): Boolean;
    function BadgeText: string;
    function PillText: string;
    function PillDot: Boolean;
    function PrimaryColor: string;
    property IsOpen: Boolean read FOpen;
    property Storage: IBFocusStorage read FStorage write FStorage;
    property Http: IBFocusHttp read FHttp write FHttp;
  published
    property Config: TBFocusConfig read FConfig write SetConfig;
    property OnBadgeChanged: TBFFmxBadgeEvent read FOnBadgeChanged write FOnBadgeChanged;
    property OnReleaseNotesChanged: TBFFmxReleaseNotesEvent read FOnReleaseNotesChanged
      write FOnReleaseNotesChanged;
    property OnError: TBFFmxErrorEvent read FOnError write FOnError;
    property OnOpen: TNotifyEvent read FOnOpen write FOnOpen;
    property OnClose: TNotifyEvent read FOnClose write FOnClose;
    { Botão/pílula próprios do integrador: repinte aqui. }
    property OnStateChanged: TNotifyEvent read FOnStateChanged write FOnStateChanged;
    property OnUserHashRequest: TBFFmxUserHashEvent read FOnUserHashRequest write FOnUserHashRequest;
  end;

  { Botão flutuante de 56 px com badge (desenhado no Canvas do FMX). }
  TBFocusFmxLauncherButton = class(TControl)
  private
    FWidget: TBFocusFmxWidget;
  protected
    procedure Paint; override;
    procedure Click; override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property Widget: TBFocusFmxWidget read FWidget write FWidget;
    property Align;
    property Position;
    property Width;
    property Height;
    property Visible;
  end;

  { Pílula "v4.2.0" com ponto; tocar abre o histórico. }
  TBFocusFmxReleaseBadge = class(TControl)
  private
    FWidget: TBFocusFmxWidget;
  protected
    procedure Paint; override;
    procedure Click; override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property Widget: TBFocusFmxWidget read FWidget write FWidget;
    property Align;
    property Position;
    property Width;
    property Height;
    property Visible;
  end;

implementation

uses
{$IFDEF MSWINDOWS}
  Winapi.ShellAPI, Winapi.Windows,
{$ENDIF}
{$IFDEF MACOS}
  Macapi.Helpers, Macapi.AppKit, Macapi.Foundation,
{$ENDIF}
  BFocusHttpDefault;

procedure OpenExternal(const Url: string);
var
  S: string;
begin
  S := BFUrlScheme(Url);
  if not ((S = 'https') or (S = 'http') or BFStartsText(Url, 'mailto:') or BFStartsText(Url, 'tel:')) then
    Exit;
{$IFDEF MSWINDOWS}
  ShellExecute(0, 'open', PChar(Url), nil, nil, SW_SHOWNORMAL);
{$ENDIF}
{$IFDEF MACOS}
  TNSWorkspace.Wrap(TNSWorkspace.OCClass.sharedWorkspace).openURL(
    TNSURL.Wrap(TNSURL.OCClass.URLWithString(StrToNSStr(Url))));
{$ENDIF}
end;

function HexColor(const Hex: string; Default: TAlphaColor): TAlphaColor;
var
  R, G, B: Byte;
begin
  if BFParseHexColor(Hex, R, G, B) then
    Result := $FF000000 or (Cardinal(R) shl 16) or (Cardinal(G) shl 8) or B
  else
    Result := Default;
end;

const
  BRIDGE_JS =
    '(function(){if(window.__bfq)return;var q=[],seq=0,cur=0,' +
    'base=location.href.split("#")[0];window.__bfq=q;' +
    'function show(){if(cur||!q.length)return;seq++;cur=seq;' +
    'location.replace(base+"#bfq="+seq+":"+encodeURIComponent(q[0]));}' +
    'window.__bfAck=function(n){if(n!==cur)return;q.shift();cur=0;show();};' +
    'window.bFocusHost={postMessage:function(s){q.push(String(s));show();}};' +
    'if(window.bFocusEmbed)window.bFocusEmbed.flush();})()';

{ ── TBFocusFmxWebForm ──────────────────────────────────────────────────── }

constructor TBFocusFmxWebForm.CreateFor(AOwner: TComponent; AKind: TBFFmxWebKind;
  const ALocale, AOrigin: string);
begin
  inherited CreateNew(AOwner);
  FKind := AKind;
  FLocale := ALocale;
  FOrigin := AOrigin;
  OnCloseQuery := CloseQueryHandler;
  Width := 400;
  Height := 620;
  if AKind = fwBanner then
  begin
    BorderStyle := TFmxFormBorderStyle.None;
    FormStyle := TFormStyle.StayOnTop;
    WindowState := TWindowState.wsMaximized;
    FLocked := True;
  end
  else if AKind = fwHistory then
    Caption := BFRN(ALocale, 'historyTitle')
  else
    Caption := BFT(ALocale, 'header_title');
  FBrowser := TWebBrowser.Create(Self);
  FBrowser.Parent := Self;
  FBrowser.Align := TAlignLayout.Client;
{$IFDEF MSWINDOWS}
  FBrowser.WindowsEngine := TWindowsEngine.EdgeIfAvailable;
{$ENDIF}
  FBrowser.OnDidFinishLoad := DidFinishLoad;
  FBrowser.OnDidStartLoad := DidStartLoad;
  FBrowser.OnDidFailLoadWithError := DidFailLoad;
  FOverlay := TLabel.Create(Self);
  FOverlay.Parent := Self;
  FOverlay.Align := TAlignLayout.Contents;
  FOverlay.TextSettings.HorzAlign := TTextAlign.Center;
  FOverlay.Text := BFT(ALocale, 'loading');
  FRetry := TButton.Create(Self);
  FRetry.Parent := Self;
  FRetry.Align := TAlignLayout.Bottom;
  FRetry.Text := BFT(ALocale, 'btn_retry');
  FRetry.OnClick := RetryClick;
  FRetry.Visible := False;
  FPoll := TTimer.Create(Self);
  FPoll.Interval := 200;
  FPoll.Enabled := False;
  FPoll.OnTimer := PollTick;
end;

procedure TBFocusFmxWebForm.Load(const Url: string);
begin
  FUrl := Url;
  FReady := False;
  FLastSeq := 0;
  FOverlay.Text := BFT(FLocale, 'loading');
  FOverlay.Visible := True;
  FRetry.Visible := False;
  FBrowser.URL := Url;
  FBrowser.Navigate;
end;

procedure TBFocusFmxWebForm.RetryClick(Sender: TObject);
begin
  Load(FUrl);
end;

procedure TBFocusFmxWebForm.InjectBridge;
begin
  FBrowser.EvaluateJavaScript(BRIDGE_JS);
end;

procedure TBFocusFmxWebForm.DidFinishLoad(ASender: TObject);
begin
  InjectBridge;
  FPoll.Enabled := True;
end;

procedure TBFocusFmxWebForm.DidStartLoad(ASender: TObject);
var
  U: string;
begin
  U := FBrowser.URL;
  // Outra origem: não dá para cancelar no FMX — abre fora e volta ao embed.
  if (U <> '') and not BFStartsText(U, 'about:') and (BFOriginOf(U) <> FOrigin) then
  begin
    FBrowser.Stop;
    OpenExternal(U);
    Load(FUrl);
  end;
end;

procedure TBFocusFmxWebForm.DidFailLoad(ASender: TObject);
begin
  FOverlay.Text := BFT(FLocale, 'error_load');
  FOverlay.Visible := True;
  FRetry.Visible := True;
end;

procedure TBFocusFmxWebForm.PollTick(Sender: TObject);
var
  U, Frag, Raw, MsgType: string;
  P, C, Seq: Integer;
  Msg: TBFJson;
begin
  U := FBrowser.URL;
  P := Pos('#bfq=', U);
  if (P = 0) or (BFOriginOf(U) <> FOrigin) then
    Exit;
  Frag := Copy(U, P + 5, MaxInt);
  C := Pos(':', Frag);
  if C = 0 then
    Exit;
  Seq := StrToIntDef(Copy(Frag, 1, C - 1), 0);
  if Seq <= FLastSeq then
    Exit;
  FLastSeq := Seq;
  Raw := BFUrlDecode(Copy(Frag, C + 1, MaxInt));
  FBrowser.EvaluateJavaScript('window.__bfAck && window.__bfAck(' + IntToStr(Seq) + ')');
  Msg := BFParseHostMessage(BFToUtf8(Raw), MsgType);
  if Msg = nil then
    Exit;
  try
    if MsgType = 'bfocus:ready' then
    begin
      FReady := True;
      FOverlay.Visible := False;
    end;
    if Assigned(FOnMessage) then
      FOnMessage(Self, MsgType, Msg);
  finally
    Msg.Free;
  end;
end;

procedure TBFocusFmxWebForm.PostToEmbed(const MessageJson: TBFRaw);
begin
  FBrowser.EvaluateJavaScript(BFReceiveScript(MessageJson));
end;

procedure TBFocusFmxWebForm.ClearOriginData;
begin
  FBrowser.EvaluateJavaScript('try{localStorage.clear();sessionStorage.clear()}catch(e){}');
end;

procedure TBFocusFmxWebForm.ForceClose;
begin
  FAllowClose := True;
  FPoll.Enabled := False;
  Hide;
end;

procedure TBFocusFmxWebForm.CloseQueryHandler(Sender: TObject; var CanClose: Boolean);
begin
  if FAllowClose then
    Exit;
  // Fechar esconde (a WebView fica); o banner nunca fecha por gesto.
  CanClose := False;
  if FLocked then
    Exit;
  Hide;
  if Assigned(FOnUserClose) then
    FOnUserClose(Self);
end;

{ ── TBFocusFmxWidget ───────────────────────────────────────────────────── }

constructor TBFocusFmxWidget.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FConfig := TBFocusConfig.Create;
  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.OnTimer := TimerTick;
end;

destructor TBFocusFmxWidget.Destroy;
begin
  BFJobs.CancelOwner(Self);
  FApi.Free;
  FLauncher.Free;
  FConfig.Free;
  inherited Destroy;
end;

procedure TBFocusFmxWidget.SetConfig(Value: TBFocusConfig);
begin
  FConfig.Assign(Value);
end;

function TBFocusFmxWidget.Origin: string;
begin
  Result := BFOriginOf(BFEmbedBase(FConfig));
end;

procedure TBFocusFmxWidget.Init;
var
  Problem: string;
begin
  Problem := FConfig.Validate;
  if Problem <> '' then
    raise Exception.Create('bFocus: ' + Problem);
  if FConfig.Locale = '' then
    FConfig.Locale := BFDeviceLocale
  else
    FConfig.Locale := BFNormalizeLocale(FConfig.Locale);
  FLocale := FConfig.Locale;
  if FHttp = nil then FHttp := BFDefaultHttp;
  if FStorage = nil then FStorage := BFDefaultStorage;
  FreeAndNil(FLauncher);
  FLauncher := TBFLauncherCore.Create(FConfig, FStorage);
  FLauncher.LoadPersisted;
  FreeAndNil(FApi);
  FApi := TBFocusApi.Create(FConfig, FHttp);
  if FConfig.Notifications and (FNotifications = nil) then
  begin
    FNotifications := TNotificationCenter.Create(Self);
    FNotifications.OnReceiveLocalNotification := NotificationReceived;
  end;
  FInitialized := True;
  Refresh;
end;

procedure TBFocusFmxWidget.Refresh;
begin
  if not FInitialized or FFetching then
    Exit;
  FFetching := True;
  BFJobs.Run(FApi, FetchWork, FetchDone, Self, []);
  // Desktop: consulta enquanto o app estiver aberto, com o widget fechado.
  FTimer.Enabled := False;
  FTimer.Interval := FConfig.PollIntervalSeconds * 1000;
  FTimer.Enabled := not FOpen;
end;

procedure TBFocusFmxWidget.TimerTick(Sender: TObject);
begin
  if not FOpen then
    Refresh;
end;

function TBFocusFmxWidget.FetchWork(Job: TBFJob): TBFJson;
var
  F: TBFLauncherFetch;
begin
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

procedure TBFocusFmxWidget.FetchDone(Job: TBFJob);
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
    if TBFLauncherCore.NeedsHashRetry(F) and Assigned(FOnUserHashRequest) and not FHashRetried then
    begin
      FHashRetried := True;
      NewHash := FConfig.UserHash;
      FOnUserHashRequest(Self, NewHash);
      if (NewHash <> '') and (NewHash <> FConfig.UserHash) then
      begin
        FConfig.UserHash := NewHash;
        FreeAndNil(FApi);
        FApi := TBFocusApi.Create(FConfig, FHttp);
        FreeAndNil(FTickets);
        Refresh;
        Exit;
      end;
    end;
    if F.Ok then
      FHashRetried := False;
    Apply(FLauncher.Apply(F));
  finally
    F.Free;
    R.Free;
  end;
end;

procedure TBFocusFmxWidget.Apply(Ev: TBFLauncherEvents);
var
  N: TNotification;
begin
  if (leBadge in Ev) and Assigned(FOnBadgeChanged) then
    FOnBadgeChanged(Self, FLauncher.Badge.Text);
  if (lePill in Ev) and Assigned(FOnReleaseNotesChanged) then
    FOnReleaseNotesChanged(Self, FLauncher.Pill.Text, FLauncher.Pill.Dot, FLauncher.Pill.BannerIds);
  if (leError in Ev) and Assigned(FOnError) then
    FOnError(Self, FLauncher.LastErrorCode, '');
  if (leNotify in Ev) and (FNotifications <> nil) then
  begin
    N := FNotifications.CreateNotification;
    try
      N.Name := 'bfocus';
      N.Title := BFNotificationTitle(FLocale);
      N.AlertBody := BFNotificationBody(FLocale);
      FNotifications.PresentNotification(N);
    finally
      N.Free;
    end;
  end;
  if leBanner in Ev then
  begin
    FLauncher.BannerOpened;
    FreeAndNil(FBanner);
    FBanner := NewForm(fwBanner);
    FBanner.Load(BFEmbedUrlIds(FConfig, epReleaseNotes, hmNative, '', 'banner',
      FLauncher.Pill.BannerIds));
    FBanner.Show;
  end;
  if Assigned(FOnStateChanged) then
    FOnStateChanged(Self);
end;

procedure TBFocusFmxWidget.NotificationReceived(Sender: TObject; ANotification: TNotification);
begin
  if ANotification.Name = 'bfocus' then
    Open;
end;

function TBFocusFmxWidget.NewForm(Kind: TBFFmxWebKind): TBFocusFmxWebForm;
begin
  Result := TBFocusFmxWebForm.CreateFor(Self, Kind, FLocale, Origin);
  Result.OnEmbedMessage := EmbedMessage;
end;

procedure TBFocusFmxWidget.Open(View: TBFOpenView; const Id: string);
begin
  if not FInitialized then
    Exit;
  if FTickets = nil then
  begin
    FTickets := NewForm(fwTickets);
    FTickets.OnUserClose := TicketsUserClose;
    FTickets.Load(BFEmbedUrl(FConfig, epEmbed, hmNative, BFOpenParam(View, Id), '', []));
    FNeedOpenMsg := True;
  end
  else
  begin
    if View <> ovList then
      FTickets.PostToEmbed(BFHostCommand('bfocus:navigate', BFNavigatePayload(View, Id, Id)));
    FTickets.PostToEmbed(BFHostCommand('bfocus:open', nil));
  end;
  FTickets.Show;
  if not FOpen then
  begin
    FOpen := True;
    FLauncher.WidgetOpened;
    FTimer.Enabled := False;
    if Assigned(FOnOpen) then
      FOnOpen(Self);
  end;
end;

procedure TBFocusFmxWidget.Hidden;
begin
  if not FOpen then
    Exit;
  FOpen := False;
  FLauncher.WidgetClosed;
  if Assigned(FOnClose) then
    FOnClose(Self);
  Refresh;
end;

procedure TBFocusFmxWidget.Close;
begin
  if FTickets <> nil then
  begin
    FTickets.PostToEmbed(BFHostCommand('bfocus:close', nil));
    FTickets.Hide;
  end;
  Hidden;
end;

procedure TBFocusFmxWidget.TicketsUserClose(Sender: TObject);
begin
  FTickets.PostToEmbed(BFHostCommand('bfocus:close', nil));
  Hidden;
end;

procedure TBFocusFmxWidget.OpenReleaseNotesHistory;
begin
  if not FInitialized then
    Exit;
  if FHistory = nil then
  begin
    FHistory := NewForm(fwHistory);
    FHistory.Load(BFEmbedUrl(FConfig, epReleaseNotes, hmNative, '', 'history', []));
  end;
  FHistory.Show;
end;

procedure TBFocusFmxWidget.EmbedMessage(Sender: TObject; const MsgType: string; Msg: TBFJson);
var
  P: TBFJson;
  Dlg: TSaveDialog;
begin
  P := Msg.ObjOf('payload');
  if MsgType = 'bfocus:ready' then
  begin
    if (Sender = FTickets) and FNeedOpenMsg then
    begin
      FNeedOpenMsg := False;
      FTickets.PostToEmbed(BFHostCommand('bfocus:open', nil));
    end;
  end
  else if MsgType = 'bfocus:close' then
    Close
  else if (MsgType = 'bfocus:unread') and (P <> nil) then
  begin
    if FOpen then
      Apply(FLauncher.HandleUnread(Integer(P.IntOf('count'))));
  end
  else if (MsgType = 'bfocus:seen') and (P <> nil) then
    FLauncher.HandleSeen(P.StrOf('latest_event_at'))
  else if ((MsgType = 'bfocus:branding') or (MsgType = 'bfocus:rn:branding')) and (P <> nil) then
    Apply(FLauncher.HandleBranding(P.StrOf('primary_color')))
  else if (MsgType = 'bfocus:error') and (P <> nil) then
  begin
    if Assigned(FOnError) then
      FOnError(Self, P.StrOf('code'), P.StrOf('detail'));
    if ((P.StrOf('code') = 'WIDGET_USER_HASH_INVALID') or
        (P.StrOf('code') = 'WIDGET_USER_HASH_EXPIRED')) and HostIdentityRefresh and (FTickets <> nil) then
      FTickets.Load(BFEmbedUrl(FConfig, epEmbed, hmNative, '', '', []));
  end
  else if MsgType = 'bfocus:identity-expired' then
  begin
    // Assinatura v2 vencida: hash novo do OnUserHashRequest e recarga, sem OnError.
    if HostIdentityRefresh and (FTickets <> nil) then
      FTickets.Load(BFEmbedUrl(FConfig, epEmbed, hmNative, '', '', []));
  end
  else if (MsgType = 'bfocus:openExternal') and (P <> nil) then
    OpenExternal(P.StrOf('url'))
  else if (MsgType = 'bfocus:download') and (P <> nil) then
  begin
    Dlg := TSaveDialog.Create(nil);
    try
      Dlg.FileName := ExtractFileName(P.StrOf('filename'));
      if Dlg.Execute then
        BFJobs.Run(FApi, DownloadWork, DownloadDone, Self, [P.StrOf('url'), Dlg.FileName]);
    finally
      Dlg.Free;
    end;
  end
  else if MsgType = 'bfocus:rn:done' then
  begin
    if FBanner <> nil then
      FBanner.ForceClose;
    FLauncher.BannerClosed;
    Refresh;
  end
  else if MsgType = 'bfocus:rn:closeHistory' then
  begin
    if FHistory <> nil then
      FHistory.Hide;
  end;
end;

function TBFocusFmxWidget.DownloadWork(Job: TBFJob): TBFJson;
begin
  Job.Api.DownloadTo(Job.Arg(0), Job.Stream);
  Result := nil;
end;

procedure TBFocusFmxWidget.DownloadDone(Job: TBFJob);
begin
  if not Job.Failed then
    Job.Stream.SaveToFile(Job.Arg(1));
end;

procedure TBFocusFmxWidget.Logout;
begin
  FTimer.Enabled := False;
  BFJobs.CancelOwner(Self);
  FFetching := False;
  if FTickets <> nil then
    FTickets.ClearOriginData;
  FreeAndNil(FTickets);
  FreeAndNil(FBanner);
  FreeAndNil(FHistory);
  if FLauncher <> nil then
    FLauncher.ClearPersisted;
  FOpen := False;
  FInitialized := False;
end;

function TBFocusFmxWidget.HandlePush(Data: TStrings): Boolean;
var
  Nav: TBFJson;
begin
  Result := BFHandlePushStrings(Data, Nav);
  try
    if Result and (Nav <> nil) then
    begin
      if Nav.StrOf('view') = 'ticket' then Open(ovTicket, Nav.StrOf('ticketId'))
      else if Nav.StrOf('view') = 'chat' then Open(ovChat, Nav.StrOf('conversationId'))
      else Open;
    end;
  finally
    Nav.Free;
  end;
end;

function TBFocusFmxWidget.BadgeText: string;
begin
  if FLauncher = nil then Result := '' else Result := FLauncher.Badge.Text;
end;

function TBFocusFmxWidget.PillText: string;
begin
  if FLauncher = nil then Result := BFEmDash else Result := FLauncher.Pill.Text;
end;

function TBFocusFmxWidget.PillDot: Boolean;
begin
  Result := (FLauncher <> nil) and FLauncher.Pill.Dot;
end;

function TBFocusFmxWidget.PrimaryColor: string;
begin
  if (FLauncher = nil) or (FLauncher.PrimaryColor = '') then
    Result := '#6366F1'
  else
    Result := FLauncher.PrimaryColor;
end;

{ ── botão e pílula ─────────────────────────────────────────────────────── }

constructor TBFocusFmxLauncherButton.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Width := 56;
  Height := 56;
  HitTest := True;
  Cursor := crHandPoint;
end;

procedure TBFocusFmxLauncherButton.Paint;
var
  R: TRectF;
  Primary: TAlphaColor;
  Badge: string;
begin
  if FWidget <> nil then
    Primary := HexColor(FWidget.PrimaryColor, $FF6366F1)
  else
    Primary := $FF6366F1;
  R := RectF(0, 0, Width, Height);
  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := Primary;
  Canvas.FillEllipse(R, 1);
  Canvas.Stroke.Kind := TBrushKind.Solid;
  Canvas.Stroke.Color := TAlphaColors.White;
  Canvas.Stroke.Thickness := 2;
  Canvas.DrawEllipse(RectF(Width / 2 - 12, Height / 2 - 10, Width / 2 + 12, Height / 2 + 8), 1);
  if FWidget <> nil then
    Badge := FWidget.BadgeText
  else
    Badge := '';
  if Badge <> '' then
  begin
    Canvas.Fill.Color := $FFEF4444;
    Canvas.FillEllipse(RectF(Width - 20, 0, Width, 20), 1);
    Canvas.Fill.Color := TAlphaColors.White;
    Canvas.Font.Size := 10;
    Canvas.FillText(RectF(Width - 20, 0, Width, 20), Badge, False, 1, [], TTextAlign.Center,
      TTextAlign.Center);
  end;
end;

procedure TBFocusFmxLauncherButton.Click;
begin
  inherited Click;
  if FWidget <> nil then
    if FWidget.IsOpen then FWidget.Close else FWidget.Open;
end;

constructor TBFocusFmxReleaseBadge.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Width := 84;
  Height := 24;
  HitTest := True;
  Cursor := crHandPoint;
end;

procedure TBFocusFmxReleaseBadge.Paint;
var
  Primary: TAlphaColor;
  Txt: string;
begin
  if FWidget <> nil then
  begin
    Primary := HexColor(FWidget.PrimaryColor, $FF6366F1);
    Txt := FWidget.PillText;
  end
  else
  begin
    Primary := $FF6366F1;
    Txt := '...';
  end;
  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := (Primary and $00FFFFFF) or $22000000;
  Canvas.FillRect(RectF(0, 0, Width, Height), Height / 2, Height / 2, AllCorners, 1);
  Canvas.Fill.Color := Primary;
  Canvas.Font.Size := 11;
  Canvas.FillText(RectF(8, 0, Width - 12, Height), Txt, False, 1, [], TTextAlign.Center,
    TTextAlign.Center);
  if (FWidget <> nil) and FWidget.PillDot then
  begin
    Canvas.Fill.Color := $FFEF4444;
    Canvas.FillEllipse(RectF(Width - 11, 3, Width - 3, 11), 1);
  end;
end;

procedure TBFocusFmxReleaseBadge.Click;
begin
  inherited Click;
  if FWidget <> nil then
    FWidget.OpenReleaseNotesHistory;
end;

end.
