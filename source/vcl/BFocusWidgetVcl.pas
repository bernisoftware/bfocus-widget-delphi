unit BFocusWidgetVcl;

{ TBFocusWidget — componente não visual do Delphi 10.4+ (VCL): o widget web da CDN numa
  janela com WebView2 (BFocusWebViewVcl). Sem WebView2 utilizável:
  - NoWebViewFallback = nwNativeUI (padrão): telas nativas da Fase 6 (BFocusNativeUI),
    seguindo a ordem de preferência do plano (revisão 1);
  - nwBrowser: modo navegador (host=browser), como a §4.5 do BRIEF.
  API do BRIEF §3: Init, Open, Close, OpenReleaseNotesHistory, Refresh, Logout,
  RegisterPushToken, HandlePush; eventos OnBadgeChanged, OnReleaseNotesChanged, OnError,
  OnOpen, OnClose, OnUserHashRequest. }

{$I BFocusDefines.inc}

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, Vcl.Forms, Vcl.Controls, Vcl.Dialogs,
  BFocusText, BFocusJson, BFocusConfig, BFocusModels, BFocusApi, BFocusAsync,
  BFocusWidgetBase, BFocusWebViewVcl, BFocusNativeUI;

type
  TBFNoWebViewFallback = (nwNativeUI, nwBrowser);

  TBFocusWidget = class(TBFocusWidgetBase)
  private
    FTickets: TBFocusWebViewForm;
    FBanner: TBFocusWebViewForm;
    FHistory: TBFocusWebViewForm;
    FNative: TBFocusNativeUI;
    FFallback: TBFNoWebViewFallback;
    FUnavailable: Boolean;
    FChecked: Boolean;
    FPanelWidth: Integer;
    FPanelHeight: Integer;
    FNeedOpenMessage: Boolean;
    function EmbedOrigin: string;
    function UseNative: Boolean;
    function UseBrowser: Boolean;
    function CheckWebView: Boolean;
    function NewForm(Kind: TBFWebKind): TBFocusWebViewForm;
    procedure EmbedMessage(Sender: TObject; const MsgType: string; Msg: TBFJson);
    procedure EmbedReady(Sender: TObject);
    procedure WebViewUnavailable(Sender: TObject);
    procedure TicketsUserClose(Sender: TObject);
    procedure HistoryUserClose(Sender: TObject);
    procedure PositionPanel(F: TForm);
    procedure StartDownload(const Url, FileName: string);
    function DownloadWork(Job: TBFJob): TBFJson;
    procedure DownloadDone(Job: TBFJob);
    function NativeUI: TBFocusNativeUI;
    procedure FreeForms;
  protected
    procedure DoShowWidget(View: TBFOpenView; const Id: string); override;
    procedure DoHideWidget; override;
    procedure DoOpenBanner(Ids: TStrings); override;
    procedure DoOpenHistory; override;
    procedure DoResetUI(ClearData: Boolean); override;
    procedure DoApiChanged; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  published
    property NoWebViewFallback: TBFNoWebViewFallback read FFallback write FFallback default nwNativeUI;
    property PanelWidth: Integer read FPanelWidth write FPanelWidth default 400;
    property PanelHeight: Integer read FPanelHeight write FPanelHeight default 620;
  end;

implementation

constructor TBFocusWidget.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FFallback := nwNativeUI;
  FPanelWidth := 400;
  FPanelHeight := 620;
end;

destructor TBFocusWidget.Destroy;
begin
  BFJobs.CancelOwner(Self);
  FreeForms;
  inherited Destroy;
end;

procedure TBFocusWidget.FreeForms;
begin
  FreeAndNil(FTickets);
  FreeAndNil(FBanner);
  FreeAndNil(FHistory);
end;

function TBFocusWidget.EmbedOrigin: string;
begin
  Result := BFOriginOf(BFEmbedBase(Config));
end;

function TBFocusWidget.CheckWebView: Boolean;
begin
  if not FChecked then
  begin
    FChecked := True;
    FUnavailable := not BFWebView2Available;
    SetBrowserMode(FUnavailable and (FFallback = nwBrowser));
  end;
  Result := not FUnavailable;
end;

function TBFocusWidget.UseNative: Boolean;
begin
  Result := not CheckWebView and (FFallback = nwNativeUI);
end;

function TBFocusWidget.UseBrowser: Boolean;
begin
  Result := not CheckWebView and (FFallback = nwBrowser);
end;

function TBFocusWidget.NativeUI: TBFocusNativeUI;
begin
  if FNative = nil then
    FNative := TBFocusNativeUI.CreateFor(Self, Self);
  Result := FNative;
end;

function TBFocusWidget.NewForm(Kind: TBFWebKind): TBFocusWebViewForm;
begin
  Result := TBFocusWebViewForm.CreateFor(Self, Kind, Locale, EmbedOrigin);
  Result.OnEmbedMessage := EmbedMessage;
  Result.OnUnavailable := WebViewUnavailable;
  Result.OnReady := EmbedReady;
end;

procedure TBFocusWidget.PositionPanel(F: TForm);
var
  WA: TRect;
begin
  // Painel de 400 x 620 no canto inferior direito da área de trabalho (como o web).
  WA := Screen.WorkAreaRect;
  F.Width := FPanelWidth;
  F.Height := FPanelHeight;
  if F.Height > WA.Bottom - WA.Top - 24 then
    F.Height := WA.Bottom - WA.Top - 24;
  F.Left := WA.Right - F.Width - 24;
  F.Top := WA.Bottom - F.Height - 24;
end;

procedure TBFocusWidget.DoShowWidget(View: TBFOpenView; const Id: string);
begin
  if UseNative then
  begin
    NativeUI.ShowWidget(View, Id);
    Exit;
  end;
  if UseBrowser then
  begin
    // Modo navegador: página inteira; badge e pílula seguem pelo REST.
    BFOpenInBrowser(BFEmbedUrl(Config, epEmbed, hmBrowser, BFOpenParam(View, Id), '', []));
    Exit;
  end;
  if FTickets = nil then
  begin
    FTickets := NewForm(wkTickets);
    FTickets.OnUserClose := TicketsUserClose;
    PositionPanel(FTickets);
    // Deep link no primeiro carregamento: open= na URL.
    FTickets.Load(BFEmbedUrl(Config, epEmbed, hmNative, BFOpenParam(View, Id), '', []));
  end
  else if View <> ovList then
    FTickets.PostToEmbed(BFHostCommand('bfocus:navigate', BFNavigatePayload(View, Id, Id)));
  FTickets.Show;
  WidgetShown;
  if FTickets.Ready then
    FTickets.PostToEmbed(BFHostCommand('bfocus:open', nil))
  else
    FNeedOpenMessage := True;
end;

procedure TBFocusWidget.EmbedReady(Sender: TObject);
begin
  if (Sender = FTickets) and FNeedOpenMessage and FTickets.Visible then
  begin
    FNeedOpenMessage := False;
    FTickets.PostToEmbed(BFHostCommand('bfocus:open', nil));
  end;
end;

procedure TBFocusWidget.DoHideWidget;
begin
  if FNative <> nil then
    FNative.HideWidget;
  if (FTickets <> nil) and FTickets.Visible then
  begin
    // Obrigatório ao esconder sem destruir: desliga o stream do chat.
    FTickets.PostToEmbed(BFHostCommand('bfocus:close', nil));
    FTickets.Hide;
  end;
  WidgetHidden;
end;

procedure TBFocusWidget.TicketsUserClose(Sender: TObject);
begin
  FTickets.PostToEmbed(BFHostCommand('bfocus:close', nil));
  WidgetHidden;
end;

procedure TBFocusWidget.HistoryUserClose(Sender: TObject);
begin
  // Nada a fazer: o histórico não mexe no estado.
end;

procedure TBFocusWidget.DoOpenBanner(Ids: TStrings);
begin
  if UseNative then
  begin
    NativeUI.OpenBanner(Ids);
    Exit;
  end;
  if UseBrowser then
    Exit; // modo navegador: o banner não abre sozinho (BRIEF §4.5)
  FreeAndNil(FBanner);
  FBanner := NewForm(wkBanner);
  FBanner.Load(BFEmbedUrlIds(Config, epReleaseNotes, hmNative, '', 'banner', Ids));
  FBanner.Show;
end;

procedure TBFocusWidget.DoOpenHistory;
begin
  if UseNative then
  begin
    NativeUI.OpenHistory;
    Exit;
  end;
  if UseBrowser then
  begin
    // Com fila pendente, "abrir as novidades" mostra o banner; senão, o histórico.
    if BannerIds.Count > 0 then
      BFOpenInBrowser(BFEmbedUrlIds(Config, epReleaseNotes, hmBrowser, '', 'banner', BannerIds))
    else
      BFOpenInBrowser(BFEmbedUrl(Config, epReleaseNotes, hmBrowser, '', 'history', []));
    Exit;
  end;
  if FHistory = nil then
  begin
    FHistory := NewForm(wkHistory);
    FHistory.OnUserClose := HistoryUserClose;
    PositionPanel(FHistory);
    FHistory.Load(BFEmbedUrl(Config, epReleaseNotes, hmNative, '', 'history', []));
  end;
  FHistory.Show;
end;

procedure TBFocusWidget.WebViewUnavailable(Sender: TObject);
var
  WasTickets: Boolean;
begin
  WasTickets := Sender = FTickets;
  FUnavailable := True;
  FChecked := True;
  SetBrowserMode(FFallback = nwBrowser);
  // Libera as janelas depois do evento (estamos dentro do callback do WebView2).
  TThread.ForceQueue(nil,
    procedure
    begin
      FreeForms;
      WidgetHidden;
      if WasTickets then
        Open;
    end);
end;

procedure TBFocusWidget.EmbedMessage(Sender: TObject; const MsgType: string; Msg: TBFJson);
var
  P: TBFJson;
  Code: string;
begin
  P := Msg.ObjOf('payload');
  if MsgType = 'bfocus:close' then
    DoHideWidget
  else if MsgType = 'bfocus:unread' then
  begin
    if IsOpen and (P <> nil) then
      HostUnread(Integer(P.IntOf('count')));
  end
  else if MsgType = 'bfocus:seen' then
  begin
    if P <> nil then
      HostSeen(P.StrOf('latest_event_at'));
  end
  else if (MsgType = 'bfocus:branding') or (MsgType = 'bfocus:rn:branding') then
  begin
    if P <> nil then
      HostBranding(P.StrOf('primary_color'));
  end
  else if MsgType = 'bfocus:error' then
  begin
    if P <> nil then
      Code := P.StrOf('code')
    else
      Code := '';
    // Hash recusado: pede um novo e recarrega; só avisa se não houver como renovar.
    if (Code = 'WIDGET_USER_HASH_INVALID') and HostIdentityRefresh then
    begin
      if FTickets <> nil then
        FTickets.Load(BFEmbedUrl(Config, epEmbed, hmNative, '', '', []));
    end
    else if P <> nil then
      HostError(Code, P.StrOf('detail'));
  end
  else if MsgType = 'bfocus:openExternal' then
  begin
    if P <> nil then
      BFOpenInBrowser(P.StrOf('url'));
  end
  else if MsgType = 'bfocus:download' then
  begin
    if P <> nil then
      StartDownload(P.StrOf('url'), P.StrOf('filename'));
  end
  else if MsgType = 'bfocus:rn:done' then
  begin
    if FBanner <> nil then
    begin
      FBanner.ForceClose;
      TThread.ForceQueue(nil, procedure begin FreeAndNil(FBanner) end);
    end;
    HostBannerDone;
  end
  else if MsgType = 'bfocus:rn:closeHistory' then
  begin
    if FHistory <> nil then
      FHistory.Hide;
  end;
end;

procedure TBFocusWidget.StartDownload(const Url, FileName: string);
var
  Dlg: TSaveDialog;
  Job: TBFJob;
begin
  Dlg := TSaveDialog.Create(nil);
  try
    Dlg.FileName := ExtractFileName(StringReplace(FileName, '/', '\', [rfReplaceAll]));
    Dlg.Options := Dlg.Options + [ofOverwritePrompt];
    if not Dlg.Execute then
      Exit;
    Job := BFJobs.Run(Api, DownloadWork, DownloadDone, Self, [Url, Dlg.FileName]);
  finally
    Dlg.Free;
  end;
end;

function TBFocusWidget.DownloadWork(Job: TBFJob): TBFJson;
begin
  Job.Api.DownloadTo(Job.Arg(0), Job.Stream);
  Result := nil;
end;

procedure TBFocusWidget.DownloadDone(Job: TBFJob);
begin
  if Job.Failed then
  begin
    HostError('DOWNLOAD_FAILED', Job.ErrorMessage);
    Exit;
  end;
  Job.Stream.SaveToFile(Job.Arg(1));
end;

procedure TBFocusWidget.DoResetUI(ClearData: Boolean);
begin
  if ClearData and (FTickets <> nil) then
    FTickets.ClearOriginData;
  FreeForms;
  if FNative <> nil then
    FNative.ResetUI;
end;

procedure TBFocusWidget.DoApiChanged;
begin
  if FNative <> nil then
    FNative.ApiChanged;
end;

end.
