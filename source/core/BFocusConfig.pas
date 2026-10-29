unit BFocusConfig;

{ Configuração do widget (BRIEF §3) e as construções exatas do Host Protocol v1:
  payload do usuário, URL do embed e request do launcher-state. Funções puras, testadas
  contra widgets-native/conformance/scenarios.json. }

{$I BFocusDefines.inc}

interface

uses
  SysUtils, Classes, BFocusText, BFocusJson, BFocusHttp;

const
  BF_PACKAGE_VERSION = '0.1.1';
  { Família do header X-bFocus-Client: o mesmo núcleo serve aos dois pacotes. }
  {$IFDEF BF_FPC}
  BF_CLIENT_FAMILY = 'lazarus';
  {$ELSE}
  BF_CLIENT_FAMILY = 'delphi';
  {$ENDIF}
  BF_DEFAULT_API = 'https://api.bfocus.com.br';
  BF_DEFAULT_EMBED = 'https://widget.bfocus.com.br/v1';
  BF_DEFAULT_POLL_SECONDS = 60;
  BF_HOST_PROTOCOL = 1;

type
  TBFocusUser = class(TPersistent)
  private
    FExternalId: string;
    FName: string;
    FEmail: string;
    FPhone: string;
  public
    procedure Assign(Source: TPersistent); override;
  published
    property ExternalId: string read FExternalId write FExternalId;
    property Name: string read FName write FName;
    property Email: string read FEmail write FEmail;
    property Phone: string read FPhone write FPhone;
  end;

  TBFocusCustomer = class(TPersistent)
  private
    FExternalId: string;
    FName: string;
    FDocument: string;
    FEmail: string;
    FPhone: string;
    FWebsite: string;
  public
    procedure Assign(Source: TPersistent); override;
  published
    property ExternalId: string read FExternalId write FExternalId;
    property Name: string read FName write FName;
    property Document: string read FDocument write FDocument;
    property Email: string read FEmail write FEmail;
    property Phone: string read FPhone write FPhone;
    property Website: string read FWebsite write FWebsite;
  end;

  TBFEmbedPage = (epEmbed, epReleaseNotes);
  TBFHostMode = (hmNative, hmBrowser);
  { Tela inicial do open(target): list (padrão) | new | ticket(id) | chat. }
  TBFOpenView = (ovList, ovNew, ovTicket, ovChat);

  TBFocusConfig = class(TPersistent)
  private
    FPublishableKey: string;
    FAppId: string;
    FUser: TBFocusUser;
    FCustomer: TBFocusCustomer;
    FUserHash: string;
    FProduct: string;
    FAudience: string;
    FLocale: string;
    FShowReleaseNotes: Boolean;
    FAutoShowReleaseBanner: Boolean;
    FApiBaseUrl: string;
    FEmbedBaseUrl: string;
    FPollIntervalSeconds: Integer;
    FNotifications: Boolean;
    FClientId: string;
    procedure SetUser(Value: TBFocusUser);
    procedure SetCustomer(Value: TBFocusCustomer);
    function GetClientId: string;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Assign(Source: TPersistent); override;
    { '' quando válida; senão, o motivo (em português, para o log do integrador). }
    function Validate: string;
    { Valor do X-bFocus-Client ("delphi/0.1.0"). Os testes sobrescrevem. }
    property ClientId: string read GetClientId write FClientId;
  published
    property PublishableKey: string read FPublishableKey write FPublishableKey;
    property AppId: string read FAppId write FAppId;
    property User: TBFocusUser read FUser write SetUser;
    property Customer: TBFocusCustomer read FCustomer write SetCustomer;
    property UserHash: string read FUserHash write FUserHash;
    property Product: string read FProduct write FProduct;
    property Audience: string read FAudience write FAudience;
    property Locale: string read FLocale write FLocale;
    property ShowReleaseNotes: Boolean read FShowReleaseNotes write FShowReleaseNotes default True;
    property AutoShowReleaseBanner: Boolean read FAutoShowReleaseBanner
      write FAutoShowReleaseBanner default True;
    property ApiBaseUrl: string read FApiBaseUrl write FApiBaseUrl;
    property EmbedBaseUrl: string read FEmbedBaseUrl write FEmbedBaseUrl;
    property PollIntervalSeconds: Integer read FPollIntervalSeconds write FPollIntervalSeconds
      default BF_DEFAULT_POLL_SECONDS;
    property Notifications: Boolean read FNotifications write FNotifications default False;
  end;

{ pt* → pt_BR, es* → es, resto → en. '' continua ''. }
function BFNormalizeLocale(const S: string): string;
{ Idioma do sistema operacional, já normalizado. }
function BFDeviceLocale: string;
{ Idioma efetivo da configuração ('' = pt_BR, igual ao embed). }
function BFLocaleOf(Config: TBFocusConfig): string;

{ JSON compacto do usuário, nesta ordem: externalId, name, email, phone, userHash, locale,
  customer(externalId, name, document, email, phone, website). Vazios somem. }
function BFUserJson(Config: TBFocusConfig): TBFRaw;
{ Base64 do JSON acima (header X-bFocus-Widget-User e parâmetro user=). }
function BFUserHeader(Config: TBFocusConfig): string;
function BFParentOrigin(Config: TBFocusConfig): string;
function BFApiBase(Config: TBFocusConfig): string;
function BFEmbedBase(Config: TBFocusConfig): string;
{ Valor do parâmetro open= ('' para a lista). }
function BFOpenParam(View: TBFOpenView; const Id: string): string;
{ URL do embed com os parâmetros no fragmento, na ordem do protocolo. Extra (só testes,
  ex.: 'script=all') vai no fim. }
function BFEmbedUrl(Config: TBFocusConfig; Page: TBFEmbedPage; Mode: TBFHostMode;
  const Open, View: string; const Ids: array of string; const Extra: string = ''): string;
function BFEmbedUrlIds(Config: TBFocusConfig; Page: TBFEmbedPage; Mode: TBFHostMode;
  const Open, View: string; Ids: TStrings; const Extra: string = ''): string;
function BFLauncherStateUrl(Config: TBFocusConfig): string;
{ Cabeçalhos de identidade de toda chamada do widget. }
procedure BFApplyWidgetHeaders(Config: TBFocusConfig; Request: TBFHttpRequest;
  WithUser, JsonBody: Boolean);
{ Request exato do launcher-state (quem chama libera). }
function BFLauncherStateRequest(Config: TBFocusConfig): TBFHttpRequest;
{ chave:usuário:cliente — escopo do last_seen e da leitura local dos chamados. }
function BFScopeKey(Config: TBFocusConfig): string;
function BFLastSeenStorageKey(Config: TBFocusConfig): string;

implementation

{$IFDEF MSWINDOWS}
uses
  Windows;
{$ENDIF}

{ ── classes ────────────────────────────────────────────────────────────── }

procedure TBFocusUser.Assign(Source: TPersistent);
begin
  if Source is TBFocusUser then
  begin
    FExternalId := TBFocusUser(Source).FExternalId;
    FName := TBFocusUser(Source).FName;
    FEmail := TBFocusUser(Source).FEmail;
    FPhone := TBFocusUser(Source).FPhone;
  end
  else
    inherited Assign(Source);
end;

procedure TBFocusCustomer.Assign(Source: TPersistent);
begin
  if Source is TBFocusCustomer then
  begin
    FExternalId := TBFocusCustomer(Source).FExternalId;
    FName := TBFocusCustomer(Source).FName;
    FDocument := TBFocusCustomer(Source).FDocument;
    FEmail := TBFocusCustomer(Source).FEmail;
    FPhone := TBFocusCustomer(Source).FPhone;
    FWebsite := TBFocusCustomer(Source).FWebsite;
  end
  else
    inherited Assign(Source);
end;

constructor TBFocusConfig.Create;
begin
  inherited Create;
  FUser := TBFocusUser.Create;
  FCustomer := TBFocusCustomer.Create;
  FShowReleaseNotes := True;
  FAutoShowReleaseBanner := True;
  FPollIntervalSeconds := BF_DEFAULT_POLL_SECONDS;
end;

destructor TBFocusConfig.Destroy;
begin
  FUser.Free;
  FCustomer.Free;
  inherited Destroy;
end;

procedure TBFocusConfig.SetUser(Value: TBFocusUser);
begin
  FUser.Assign(Value);
end;

procedure TBFocusConfig.SetCustomer(Value: TBFocusCustomer);
begin
  FCustomer.Assign(Value);
end;

function TBFocusConfig.GetClientId: string;
begin
  if FClientId <> '' then
    Result := FClientId
  else
    Result := BF_CLIENT_FAMILY + '/' + BF_PACKAGE_VERSION;
end;

procedure TBFocusConfig.Assign(Source: TPersistent);
var
  S: TBFocusConfig;
begin
  if Source is TBFocusConfig then
  begin
    S := TBFocusConfig(Source);
    FPublishableKey := S.FPublishableKey;
    FAppId := S.FAppId;
    FUser.Assign(S.FUser);
    FCustomer.Assign(S.FCustomer);
    FUserHash := S.FUserHash;
    FProduct := S.FProduct;
    FAudience := S.FAudience;
    FLocale := S.FLocale;
    FShowReleaseNotes := S.FShowReleaseNotes;
    FAutoShowReleaseBanner := S.FAutoShowReleaseBanner;
    FApiBaseUrl := S.FApiBaseUrl;
    FEmbedBaseUrl := S.FEmbedBaseUrl;
    FPollIntervalSeconds := S.FPollIntervalSeconds;
    FNotifications := S.FNotifications;
    FClientId := S.FClientId;
  end
  else
    inherited Assign(Source);
end;

function TBFocusConfig.Validate: string;
begin
  Result := '';
  // Segredos nunca entram no app (BRIEF §6): recusa em vez de enviar.
  if BFStartsText(FPublishableKey, 'bf_whs_') or BFStartsText(FPublishableKey, 'bf_live_') or
    BFStartsText(FPublishableKey, 'bf_sk_') or BFStartsText(FUserHash, 'bf_') then
    Result := 'segredo do bFocus no app: use so a chave publica bf_pk_ e o userHash'
  else if not BFStartsWith(FPublishableKey, 'bf_pk_') then
    Result := 'publishableKey deve comecar com bf_pk_'
  else if Trim(FAppId) = '' then
    Result := 'appId e obrigatorio no desktop'
  else if Trim(FUser.ExternalId) = '' then
    Result := 'user.externalId e obrigatorio'
  else if Trim(FCustomer.ExternalId) = '' then
    Result := 'customer.externalId e obrigatorio'
  else if (FApiBaseUrl <> '') and not BFUrlAllowed(FApiBaseUrl) then
    Result := 'apiBaseUrl: http:// so para 127.0.0.1/localhost'
  else if (FEmbedBaseUrl <> '') and not BFUrlAllowed(FEmbedBaseUrl) then
    Result := 'embedBaseUrl: http:// so para 127.0.0.1/localhost'
  else if (FAudience <> '') and (FAudience <> 'external') and (FAudience <> 'internal') and
    (FAudience <> 'both') then
    Result := 'audience deve ser external, internal ou both';
end;

{ ── idioma ─────────────────────────────────────────────────────────────── }

function BFNormalizeLocale(const S: string): string;
var
  L: string;
begin
  L := BFLowerAscii(Trim(S));
  if L = '' then
    Result := ''
  else if BFStartsWith(L, 'pt') then
    Result := 'pt_BR'
  else if BFStartsWith(L, 'es') then
    Result := 'es'
  else
    Result := 'en';
end;

function BFDeviceLocale: string;
{$IFDEF MSWINDOWS}
var
  Lang: Word;
begin
  // Idioma primário do usuário: $16 português, $0A espanhol.
  Lang := GetUserDefaultLangID and $3FF;
  case Lang of
    $16: Result := 'pt_BR';
    $0A: Result := 'es';
  else
    Result := 'en';
  end;
end;
{$ELSE}
var
  V: string;
begin
  V := GetEnvironmentVariable('LC_ALL');
  if V = '' then
    V := GetEnvironmentVariable('LC_MESSAGES');
  if V = '' then
    V := GetEnvironmentVariable('LANG');
  if (V = '') or (V = 'C') or (V = 'POSIX') then
    Result := 'en'
  else
    Result := BFNormalizeLocale(V);
end;
{$ENDIF}

function BFLocaleOf(Config: TBFocusConfig): string;
begin
  Result := BFNormalizeLocale(Config.Locale);
  if Result = '' then
    Result := 'pt_BR';
end;

{ ── payload do usuário ─────────────────────────────────────────────────── }

procedure PutIf(Obj: TBFJson; const Key, Value: string);
begin
  if Value <> '' then
    Obj.PutStr(Key, Value);
end;

function BFUserJson(Config: TBFocusConfig): TBFRaw;
var
  Root, Cust: TBFJson;
begin
  Root := TBFJson.NewObject;
  try
    PutIf(Root, 'externalId', Config.User.ExternalId);
    PutIf(Root, 'name', Config.User.Name);
    PutIf(Root, 'email', Config.User.Email);
    PutIf(Root, 'phone', Config.User.Phone);
    PutIf(Root, 'userHash', Config.UserHash);
    Root.PutStr('locale', BFLocaleOf(Config));
    Cust := Root.Put('customer', TBFJson.NewObject);
    PutIf(Cust, 'externalId', Config.Customer.ExternalId);
    PutIf(Cust, 'name', Config.Customer.Name);
    PutIf(Cust, 'document', Config.Customer.Document);
    PutIf(Cust, 'email', Config.Customer.Email);
    PutIf(Cust, 'phone', Config.Customer.Phone);
    PutIf(Cust, 'website', Config.Customer.Website);
    Result := Root.ToJson;
  finally
    Root.Free;
  end;
end;

function BFUserHeader(Config: TBFocusConfig): string;
begin
  Result := BFBase64Encode(BFUserJson(Config));
end;

function BFParentOrigin(Config: TBFocusConfig): string;
begin
  Result := 'app://' + BFLowerAscii(Trim(Config.AppId));
end;

function BFApiBase(Config: TBFocusConfig): string;
begin
  if Trim(Config.ApiBaseUrl) = '' then
    Result := BF_DEFAULT_API
  else
    Result := BFTrimRightSlashes(Trim(Config.ApiBaseUrl));
end;

function BFEmbedBase(Config: TBFocusConfig): string;
begin
  if Trim(Config.EmbedBaseUrl) = '' then
    Result := BF_DEFAULT_EMBED
  else
    Result := BFTrimRightSlashes(Trim(Config.EmbedBaseUrl));
end;

function BFOpenParam(View: TBFOpenView; const Id: string): string;
begin
  case View of
    ovNew: Result := 'new';
    ovTicket: Result := 'ticket:' + Id;
    ovChat:
      if Id <> '' then Result := 'chat:' + Id else Result := 'chat';
  else
    Result := '';
  end;
end;

{ ── URL do embed ───────────────────────────────────────────────────────── }

function BuildEmbedUrl(Config: TBFocusConfig; Page: TBFEmbedPage; Mode: TBFHostMode;
  const Open, View, IdsJoined, Extra: string): string;
var
  Params: string;

  procedure P(const K, V: string);
  begin
    if Params <> '' then
      Params := Params + '&';
    Params := Params + K + '=' + BFUrlEncode(V);
  end;

begin
  Params := '';
  if Mode = hmBrowser then P('host', 'browser') else P('host', 'native');
  P('hp', IntToStr(BF_HOST_PROTOCOL));
  P('client', Config.ClientId);
  P('key', Config.PublishableKey);
  P('user', BFUserHeader(Config));
  P('locale', BFLocaleOf(Config));
  P('parentOrigin', BFParentOrigin(Config));
  if Config.Product <> '' then P('product', Config.Product);
  if Config.Audience <> '' then P('audience', Config.Audience);
  if BFApiBase(Config) <> BF_DEFAULT_API then P('api', BFApiBase(Config));
  if (Page = epEmbed) and not Config.ShowReleaseNotes then P('showReleaseNotes', '0');
  if Open <> '' then P('open', Open);
  if View <> '' then P('view', View);
  if IdsJoined <> '' then P('ids', IdsJoined);
  if Extra <> '' then
    Params := Params + '&' + Extra;
  if Page = epEmbed then
    Result := BFEmbedBase(Config) + '/embed.html#' + Params
  else
    Result := BFEmbedBase(Config) + '/release-notes.html#' + Params;
end;

function BFEmbedUrl(Config: TBFocusConfig; Page: TBFEmbedPage; Mode: TBFHostMode;
  const Open, View: string; const Ids: array of string; const Extra: string): string;
var
  I: Integer;
  Joined: string;
begin
  Joined := '';
  for I := 0 to High(Ids) do
  begin
    if I > 0 then
      Joined := Joined + ',';
    Joined := Joined + Ids[I];
  end;
  Result := BuildEmbedUrl(Config, Page, Mode, Open, View, Joined, Extra);
end;

function BFEmbedUrlIds(Config: TBFocusConfig; Page: TBFEmbedPage; Mode: TBFHostMode;
  const Open, View: string; Ids: TStrings; const Extra: string): string;
var
  I: Integer;
  Joined: string;
begin
  Joined := '';
  if Ids <> nil then
    for I := 0 to Ids.Count - 1 do
    begin
      if I > 0 then
        Joined := Joined + ',';
      Joined := Joined + Ids[I];
    end;
  Result := BuildEmbedUrl(Config, Page, Mode, Open, View, Joined, Extra);
end;

{ ── launcher-state ─────────────────────────────────────────────────────── }

function BFLauncherStateUrl(Config: TBFocusConfig): string;
var
  Q: string;
begin
  Q := '';
  if Config.Product <> '' then
    Q := 'product=' + BFUrlEncode(Config.Product);
  if Config.Audience <> '' then
  begin
    if Q <> '' then
      Q := Q + '&';
    Q := Q + 'audience=' + BFUrlEncode(Config.Audience);
  end;
  Result := BFApiBase(Config) + '/api/v1/widget/launcher-state';
  if Q <> '' then
    Result := Result + '?' + Q;
end;

procedure BFApplyWidgetHeaders(Config: TBFocusConfig; Request: TBFHttpRequest;
  WithUser, JsonBody: Boolean);
begin
  if JsonBody then
    Request.Headers.SetValue('Content-Type', 'application/json');
  Request.Headers.SetValue('X-bFocus-Widget-Key', Config.PublishableKey);
  if WithUser then
    Request.Headers.SetValue('X-bFocus-Widget-User', BFUserHeader(Config));
  Request.Headers.SetValue('X-bFocus-Parent-Origin', BFParentOrigin(Config));
  Request.Headers.SetValue('X-bFocus-Client', Config.ClientId);
end;

function BFLauncherStateRequest(Config: TBFocusConfig): TBFHttpRequest;
begin
  Result := TBFHttpRequest.Create('POST', BFLauncherStateUrl(Config));
  BFApplyWidgetHeaders(Config, Result, True, True);
  Result.SetBodyRaw('{}');
end;

function BFScopeKey(Config: TBFocusConfig): string;
begin
  Result := Config.PublishableKey + ':' + Config.User.ExternalId + ':' +
    Config.Customer.ExternalId;
end;

function BFLastSeenStorageKey(Config: TBFocusConfig): string;
begin
  Result := 'bf:lastSeen:' + BFScopeKey(Config);
end;

end.
