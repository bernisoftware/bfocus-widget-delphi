unit BFocusCoreTests;

{ Testes do núcleo sobre conformance/scenarios.json (cópia em tests/) e unidades puras. }

{$I BFocusDefines.inc}

interface

procedure RunCoreTests(const ScenariosFile: string);

implementation

uses
  SysUtils, Classes, BFocusTestKit, BFocusText, BFocusJson, BFocusHttp, BFocusConfig,
  BFocusModels, BFocusFormat, BFocusI18n, BFocusTokens, BFocusLauncher, BFocusStorage;

var
  Scen: TBFJson;

function LoadFile(const FileName: string): TBFRaw;
var
  F: TFileStream;
begin
  F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    Result := BFRawFromStream(F);
  finally
    F.Free;
  end;
end;

{ Configuração de scenarios.configs[name]. Quem chama libera. }
function ConfigNamed(const Name: string): TBFocusConfig;
var
  C, U, Cu: TBFJson;
begin
  C := Scen.Path('configs.' + Name);
  Result := TBFocusConfig.Create;
  Result.PublishableKey := C.StrOf('publishableKey');
  Result.AppId := C.StrOf('appId');
  Result.ClientId := C.StrOf('client');
  U := C.ObjOf('user');
  Result.User.ExternalId := U.StrOf('externalId');
  Result.User.Name := U.StrOf('name');
  Result.User.Email := U.StrOf('email');
  Result.User.Phone := U.StrOf('phone');
  Cu := C.ObjOf('customer');
  Result.Customer.ExternalId := Cu.StrOf('externalId');
  Result.Customer.Name := Cu.StrOf('name');
  Result.Customer.Document := Cu.StrOf('document');
  Result.Customer.Email := Cu.StrOf('email');
  Result.Customer.Phone := Cu.StrOf('phone');
  Result.Customer.Website := Cu.StrOf('website');
  Result.UserHash := C.StrOf('userHash');
  Result.Locale := C.StrOf('locale');
  Result.Product := C.StrOf('product');
  Result.Audience := C.StrOf('audience');
  Result.ApiBaseUrl := C.StrOf('apiBaseUrl');
  Result.ShowReleaseNotes := C.BoolOf('showReleaseNotes', True);
end;

{ ── cenários ───────────────────────────────────────────────────────────── }

procedure TestUserPayload;
var
  Arr, Case_: TBFJson;
  I: Integer;
  Cfg: TBFocusConfig;
begin
  Arr := Scen.ArrOf('userPayload');
  Check(Arr.Count >= 2, 'userPayload tem casos');
  for I := 0 to Arr.Count - 1 do
  begin
    Case_ := Arr.Item(I);
    Cfg := ConfigNamed(Case_.StrOf('config'));
    try
      Check(BFUserJson(Cfg) = Case_.Utf8Of('json'), 'userPayload.json ' + Case_.StrOf('name') +
        ': ' + string(BFUserJson(Cfg)));
      CheckEq(BFUserHeader(Cfg), Case_.StrOf('base64'), 'userPayload.base64 ' + Case_.StrOf('name'));
      Check(BFBase64Decode(Case_.StrOf('base64')) = Case_.Utf8Of('json'),
        'base64 decodifica de volta ' + Case_.StrOf('name'));
    finally
      Cfg.Free;
    end;
  end;
end;

procedure TestEmbedUrl;
var
  Arr, C, IdsJ: TBFJson;
  I, J: Integer;
  Cfg: TBFocusConfig;
  Page: TBFEmbedPage;
  Mode: TBFHostMode;
  Ids: TStringList;
begin
  Arr := Scen.ArrOf('embedUrl');
  Check(Arr.Count >= 5, 'embedUrl tem casos');
  for I := 0 to Arr.Count - 1 do
  begin
    C := Arr.Item(I);
    Cfg := ConfigNamed(C.StrOf('config'));
    Ids := TStringList.Create;
    try
      if C.StrOf('page') = 'embed' then Page := epEmbed else Page := epReleaseNotes;
      if C.StrOf('mode') = 'browser' then Mode := hmBrowser else Mode := hmNative;
      IdsJ := C.ArrOf('ids');
      if IdsJ <> nil then
        for J := 0 to IdsJ.Count - 1 do
          Ids.Add(IdsJ.Item(J).AsString);
      CheckEq(BFEmbedUrlIds(Cfg, Page, Mode, C.StrOf('open'), C.StrOf('view'), Ids),
        C.StrOf('expect'), 'embedUrl ' + C.StrOf('name'));
    finally
      Ids.Free;
      Cfg.Free;
    end;
  end;
end;

procedure CheckRequest(Req: TBFHttpRequest; Expect: TBFJson; const Name: string);
var
  H: TBFJson;
  I: Integer;
begin
  CheckEq(Req.Method, Expect.StrOf('method'), Name + ' method');
  CheckEq(Req.Url, Expect.StrOf('url'), Name + ' url');
  H := Expect.ObjOf('headers');
  if H <> nil then
  begin
    CheckEqInt(Req.Headers.Count, H.Count, Name + ' quantidade de headers');
    for I := 0 to H.Count - 1 do
      CheckEq(Req.Headers.GetValue(H.Key(I)), H.Item(I).AsString, Name + ' header ' + H.Key(I));
  end;
  if Expect.Has('body') then
    Check(Req.BodyRaw = Expect.Utf8Of('body'), Name + ' body');
end;

procedure TestLauncherStateRequest;
var
  Arr, C: TBFJson;
  I: Integer;
  Cfg: TBFocusConfig;
  Req: TBFHttpRequest;
begin
  Arr := Scen.ArrOf('launcherStateRequest');
  Check(Arr.Count >= 2, 'launcherStateRequest tem casos');
  for I := 0 to Arr.Count - 1 do
  begin
    C := Arr.Item(I);
    Cfg := ConfigNamed(C.StrOf('config'));
    Req := BFLauncherStateRequest(Cfg);
    try
      CheckRequest(Req, C.ObjOf('expect'), 'launcherState ' + C.StrOf('name'));
    finally
      Req.Free;
      Cfg.Free;
    end;
  end;
end;

procedure TestBadge;
var
  Arr, C, Steps, St, Ex: TBFJson;
  I, J: Integer;
  B: TBFBadgeModel;
  Op, Name: string;
begin
  Arr := Scen.ArrOf('badge');
  Check(Arr.Count >= 5, 'badge tem casos');
  for I := 0 to Arr.Count - 1 do
  begin
    C := Arr.Item(I);
    Name := C.StrOf('name');
    B := TBFBadgeModel.Create;
    try
      B.LastSeen := C.Path('initial').StrOf('last_seen');
      B.Text := C.Path('initial').StrOf('label');
      Steps := C.ArrOf('steps');
      for J := 0 to Steps.Count - 1 do
      begin
        St := Steps.Item(J);
        Op := St.StrOf('op');
        if Op = 'state' then B.ApplyState(St.StrOf('latest_event_at'))
        else if Op = 'unread' then B.ApplyUnread(Integer(St.IntOf('count')))
        else if Op = 'seen' then B.ApplySeen(St.StrOf('latest_event_at'))
        else if Op = 'open' then B.Open
        else if Op = 'close' then B.Close;
        Ex := St.ObjOf('expect');
        if Ex.Has('label') then
          CheckEq(B.Text, Ex.StrOf('label'), Format('badge "%s" passo %d label', [Name, J]));
        if Ex.Has('last_seen') then
          CheckEq(B.LastSeen, Ex.StrOf('last_seen'), Format('badge "%s" passo %d last_seen', [Name, J]));
      end;
    finally
      B.Free;
    end;
  end;
end;

procedure TestPill;
var
  Arr, C, Ex, Ids: TBFJson;
  I, J: Integer;
  P: TBFPill;
begin
  Arr := Scen.ArrOf('pill');
  Check(Arr.Count >= 4, 'pill tem casos');
  for I := 0 to Arr.Count - 1 do
  begin
    C := Arr.Item(I);
    Ex := C.ObjOf('expect');
    P := TBFPill.Create;
    try
      P.Apply(C.ObjOf('releaseNotes'));
      CheckEq(P.Text, Ex.StrOf('label'), 'pill ' + C.StrOf('name') + ' label');
      CheckBool(P.Dot, Ex.BoolOf('dot'), 'pill ' + C.StrOf('name') + ' dot');
      Ids := Ex.ArrOf('bannerIds');
      CheckEqInt(P.BannerIds.Count, Ids.Count, 'pill ' + C.StrOf('name') + ' bannerIds');
      for J := 0 to Ids.Count - 1 do
        CheckEq(P.BannerIds[J], Ids.Item(J).AsString, 'pill id');
    finally
      P.Free;
    end;
  end;
end;

procedure CheckPushRequest(Req: TBFHttpRequest; Expect: TBFJson; const Name: string);
var
  Body: TBFJson;
begin
  CheckEq(Req.Method, Expect.StrOf('method'), Name + ' method');
  CheckEq(Req.Url, Expect.StrOf('url'), Name + ' url');
  Body := TBFJson.Parse(Req.BodyRaw);
  try
    Check(Body.SameAs(Expect.ObjOf('json')), Name + ' json: ' + string(Body.ToJson));
  finally
    Body.Free;
  end;
  Check(Req.Headers.GetValue('X-bFocus-Widget-User') <> '', Name + ' com headers do widget');
end;

procedure BuildStrings(Data: TBFJson; SL: TStrings);
var
  I: Integer;
begin
  SL.Clear;
  if Data <> nil then
    for I := 0 to Data.Count - 1 do
      SL.Add(Data.Key(I) + '=' + Data.Item(I).AsString);
end;

procedure TestPush;
var
  P, C, H, Nav: TBFJson;
  I: Integer;
  Cfg: TBFocusConfig;
  Req: TBFHttpRequest;
  Handled: Boolean;
  SL: TStringList;
  NavS: TBFJson;
begin
  P := Scen.ObjOf('push');
  C := P.ObjOf('register');
  Cfg := ConfigNamed(C.StrOf('config'));
  Req := BFPushRegisterRequest(Cfg, C.StrOf('token'), C.StrOf('platform'));
  try
    CheckPushRequest(Req, C.ObjOf('expect'), 'push.register');
  finally
    Req.Free;
    Cfg.Free;
  end;
  C := P.ObjOf('unregister');
  Cfg := ConfigNamed(C.StrOf('config'));
  Req := BFPushUnregisterRequest(Cfg, C.StrOf('token'));
  try
    CheckPushRequest(Req, C.ObjOf('expect'), 'push.unregister');
  finally
    Req.Free;
    Cfg.Free;
  end;
  H := P.ArrOf('handle');
  for I := 0 to H.Count - 1 do
  begin
    C := H.Item(I);
    Handled := BFHandlePushJson(C.ObjOf('data'), Nav);
    try
      CheckBool(Handled, C.Path('expect.handled').AsBool, 'push.handle ' + C.StrOf('name'));
      if C.Path('expect.navigate').IsNull then
        Check(Nav = nil, 'push.handle sem navigate ' + C.StrOf('name'))
      else
        Check((Nav <> nil) and Nav.SameAs(C.Path('expect.navigate')),
          'push.handle navigate ' + C.StrOf('name'));
    finally
      Nav.Free;
    end;
    // Mesma regra com pares Nome=Valor.
    SL := TStringList.Create;
    try
      NavS := nil;
      BuildStrings(C.ObjOf('data'), SL);
      Handled := BFHandlePushStrings(SL, NavS);
      try
        CheckBool(Handled, C.Path('expect.handled').AsBool, 'push.handle(strings) ' + C.StrOf('name'));
      finally
        NavS.Free;
      end;
    finally
      SL.Free;
    end;
  end;
end;

{ ── unidades puras ─────────────────────────────────────────────────────── }

procedure TestJson;
var
  J: TBFJson;
  R: TBFRaw;
begin
  J := TBFJson.Parse('{"a":1,"b":[true,false,null],"c":"x\"y\\z\n\'#$75'00e7\'#$75'd83d\'#$75'de00","d":-1.5e3}');
  try
    CheckEqInt(J.IntOf('a'), 1, 'int');
    CheckEqInt(J.ArrOf('b').Count, 3, 'array');
    Check(J.ArrOf('b').Item(2).IsNull, 'null');
    Check(J.Utf8Of('c') = 'x"y\z'#10#$C3#$A7#$F0#$9F#$98#$80, 'escapes e par substituto');
    R := J.ToJson;
    Check(R = '{"a":1,"b":[true,false,null],"c":"x\"y\\z\n'#$C3#$A7#$F0#$9F#$98#$80'","d":-1.5e3}',
      'saída compacta sem escapar não-ASCII: ' + string(R));
    Check(Abs(J.Get('d').AsFloat - (-1500)) < 0.001, 'float');
  finally
    J.Free;
  end;
  Check(TBFJson.TryParse('{"a":') = nil, 'JSON inválido vira nil');
  Check(TBFJson.TryParse('[1,]') = nil, 'vírgula sobrando');
  J := TBFJson.Parse(#$EF#$BB#$BF'  [ ]  ');
  try
    Check(J.IsArray and (J.Count = 0), 'BOM + espaços');
  finally
    J.Free;
  end;
  J := TBFJson.NewObject;
  try
    J.PutStr('z', 'a/b<c>&');
    J.PutInt('a', 2);
    J.PutStr('z', 'troca');
    Check(J.ToJson = '{"z":"troca","a":2}', 'Put substitui mantendo a ordem');
    Check(BFJsonQuote(#1#31'/') = '"\'#$75'0001\'#$75'001f/"', 'controle vira \u00XX, "/" fica');
  finally
    J.Free;
  end;
end;

procedure TestTextUtils;
var
  Ms: Int64;
begin
  CheckEq(BFUrlEncode('a b&c=d/é~'), 'a%20b%26c%3Dd%2F%C3%A9~', 'url encode RFC 3986');
  CheckEq(BFUrlEncode('!''()*'), '%21%27%28%29%2A', 'url encode !''()*');
  CheckEq(BFUrlDecode('a%20b%C3%A9'), 'a b' + BFFromUtf8(#$C3#$A9), 'url decode');
  CheckEq(BFBase64Encode('Ma'), 'TWE=', 'base64 1 pad');
  CheckEq(BFBase64Encode('M'), 'TQ==', 'base64 2 pad');
  Check(BFBase64Decode('TWFu') = 'Man', 'base64 decode');
  Check(BFIsoToUnixMs('2026-09-01T10:00:00+00:00', Ms), 'iso válido');
  CheckEqInt(Ms, 1788256800000, 'iso → unix ms');
  CheckEqInt(BFIsoToUnixMsDef('2026-09-01T07:00:00-03:00'), 1788256800000, 'fuso −03:00');
  CheckEqInt(BFIsoToUnixMsDef('2026-09-01T10:00:00.250Z'), 1788256800250, 'milissegundos Z');
  CheckEqInt(BFIsoToUnixMsDef('2026-09-01T10:00:00.123456+00:00'), 1788256800123, 'microssegundos');
  CheckEq(BFUnixMsToIso(1788256800250), '2026-09-01T10:00:00.250Z', 'unix → iso');
  Check(not BFIsoToUnixMs('ontem', Ms), 'iso inválido');
  CheckEq(BFOriginOf('https://Widget.bfocus.com.br:443/v1/embed.html#x'), 'https://widget.bfocus.com.br', 'origem');
  CheckEq(BFOriginOf('http://127.0.0.1:8787/v1/embed.html'), 'http://127.0.0.1:8787', 'origem com porta');
  Check(BFUrlAllowed('http://localhost:1/x') and not BFUrlAllowed('http://evil.com'), 'http só local');
  CheckEq(BFTrimRightSlashes('https://a.b//'), 'https://a.b', 'barras finais');
end;

procedure TestFormat;
begin
  CheckEq(BFTextToHtml(#10'oi <b>'#10#10'tchau'#10), '<p>oi &lt;b&gt;</p><p></p><p>tchau</p>', 'textToHtml');
  CheckEq(BFTextToHtml('   '), '', 'textToHtml vazio');
  Check(BFIsHtmlEmpty('<p>&nbsp;</p><p></p>'), 'html vazio');
  Check(not BFIsHtmlEmpty('<p><img src="x"></p>'), 'imagem não é vazio');
  CheckEq(BFMarkupToHtml('Oi **forte** e *leve*'#10'- um'#10'- dois'#10'1. a'),
    '<p>Oi <strong>forte</strong> e <em>leve</em></p><ul><li>um</li><li>dois</li></ul><ol><li>a</li></ol>',
    'marcação leve do editor');
  CheckEq(BFHtmlToText('<p>Olá&nbsp;<b>mundo</b></p><ul><li>a</li><li>b</li></ul><ol><li>x</li></ol>'),
    'Olá mundo' + sLineBreak + BFBadgeDot + ' a' + sLineBreak + BFBadgeDot + ' b' + sLineBreak + '1. x',
    'html → texto');
  CheckEq(BFHtmlToText('a &amp; b &#231; &#xE7;'), 'a & b ' + BFFromUtf8(#$C3#$A7) + ' ' +
    BFFromUtf8(#$C3#$A7), 'entidades');
  CheckEq(BFMarkupToHtml('> cita `x<y`'#10'veja [site](https://a.b/?q=1&r=2) e [js](javascript:x)'),
    '<blockquote><p>cita <code>x&lt;y</code></p></blockquote><p>veja <a href="https://a.b/?q=1&amp;r=2">site</a> e [js](javascript:x)</p>',
    'citacao, codigo e link seguro');
  CheckEq(BFNormalizeLinkUrl(' bfocus.com.br '), 'https://bfocus.com.br', 'link sem esquema vira https');
  CheckEq(BFNormalizeLinkUrl('mailto:a@b.c'), 'mailto:a@b.c', 'mailto preservado');
  CheckEq(BFHtmlToText('<p>veja <a href="https://x.y/a?b=1&amp;c=2">docs</a></p>'), 'veja docs (https://x.y/a?b=1&c=2)',
    'link visivel no texto reserva');
  CheckEq(BFPrettyBytes(512), '512 B', 'bytes');
  CheckEq(BFPrettyBytes(1536), '1.5 KB', 'KB');
  CheckEq(BFPrettyBytes(3 * 1024 * 1024), '3.0 MB', 'MB');
  Check(BFSemverCompare('v4.10.0', '4.9.9') > 0, 'semver');
  CheckEq(BFInitials('ana maria souza'), 'AM', 'iniciais');
end;

procedure TestI18nTokens;
var
  I: Integer;
  Missing: Integer;
begin
  CheckEq(BFT('pt_BR', 'header_title'), 'Suporte', 'pt_BR');
  CheckEq(BFT('en', 'header_title'), 'Support', 'en');
  CheckEq(BFT('es', 'header_title'), 'Soporte', 'es');
  CheckEq(BFT('xx', 'btn_send'), 'Enviar', 'idioma desconhecido cai em pt_BR');
  CheckEq(BFT('en', 'nao_existe'), 'nao_existe', 'chave desconhecida');
  CheckEq(BFFill(BFT('en', 'chat_queue_size'), 'n', '3'), '3 in the queue now', 'fill');
  CheckEq(BFRN('en', 'ackButton'), 'I have read and acknowledge the new features and changes', 'releaseNotes');
  CheckEq(BFT('pt_BR', 'status_in_progress'), 'Em andamento', 'status');
  CheckEq(BFT('pt_BR', 'empty_state_desc'), 'Abra seu primeiro chamado para come' + BFFromUtf8(#$C3#$A7) + 'ar.', 'acento');
  // Cenário 14: en/es sem nenhuma chave caindo no português.
  Missing := 0;
  for I := 0 to BFTicketKeyCount - 1 do
    if (BFT('en', BFTicketKey(I)) = BFT('pt_BR', BFTicketKey(I))) and
      (BFT('es', BFTicketKey(I)) = BFT('pt_BR', BFTicketKey(I))) and
      (Pos(' ', BFT('pt_BR', BFTicketKey(I))) > 0) then
      Inc(Missing);
  CheckEqInt(Missing, 0, 'frases iguais em pt/en/es (tradução faltando)');
  CheckEq(BFTokenColor('ticketStatus', 'resolved'), '#10b981', 'token status');
  CheckEq(BFTokenColor('chatStatus', 'bot'), '#0ea5e9', 'token chat');
  CheckEq(BFTokenColor('priority', 'critical'), '#ef4444', 'token prioridade');
  CheckEq(BFTokenColor('x', 'y', '#000'), '#000', 'token padrão');
  CheckEq(BF_BRAND_FALLBACK, '#6366F1', 'marca reserva');
end;

procedure TestConfig;
var
  Cfg: TBFocusConfig;
begin
  CheckEq(BFNormalizeLocale('pt-PT'), 'pt_BR', 'locale pt*');
  CheckEq(BFNormalizeLocale('es_AR.UTF-8'), 'es', 'locale es*');
  CheckEq(BFNormalizeLocale('de_DE'), 'en', 'locale resto');
  Cfg := TBFocusConfig.Create;
  try
    Cfg.PublishableKey := 'bf_sk_123';
    Cfg.AppId := 'x';
    Cfg.User.ExternalId := 'u';
    Cfg.Customer.ExternalId := 'c';
    Check(Pos('segredo', Cfg.Validate) > 0, 'recusa chave secreta');
    Cfg.PublishableKey := 'bf_pk_1';
    CheckEq(Cfg.Validate, '', 'config válida');
    Cfg.ApiBaseUrl := 'http://api.exemplo.com';
    Check(Cfg.Validate <> '', 'http fora de localhost recusado');
    CheckEq(Cfg.ClientId, BF_CLIENT_FAMILY + '/' + BF_PACKAGE_VERSION, 'X-bFocus-Client padrão');
    CheckEq(BFOpenParam(ovTicket, 'abc'), 'ticket:abc', 'open ticket');
    CheckEq(BFOpenParam(ovList, ''), '', 'open lista omitido');
  finally
    Cfg.Free;
  end;
end;

procedure TestHostProtocol;
var
  M, P: TBFJson;
  T: string;
begin
  M := BFParseHostMessage('{"type":"bfocus:unread","payload":{"count":3}}', T);
  try
    CheckEq(T, 'bfocus:unread', 'tipo');
    CheckEqInt(M.Path('payload.count').AsInt64, 3, 'payload');
  finally
    M.Free;
  end;
  Check(BFParseHostMessage('{"type":"bfocus:inventado"}', T) = nil, 'tipo desconhecido ignorado');
  Check(BFParseHostMessage('{"type":"outra:coisa"}', T) = nil, 'fora do prefixo ignorado');
  Check(BFParseHostMessage('lixo', T) = nil, 'não-JSON ignorado');
  P := BFNavigatePayload(ovTicket, 't-1', '');
  CheckEq(string(BFHostCommand('bfocus:navigate', P)),
    '{"type":"bfocus:navigate","payload":{"view":"ticket","ticketId":"t-1"}}', 'navigate');
  CheckEq(BFReceiveScript('{"type":"bfocus:open"}'),
    'window.bFocusEmbed && window.bFocusEmbed.receive({"type":"bfocus:open"})', 'receive script');
end;

function Fixture(const Name: string): TBFLauncherFetch;
begin
  Result := TBFLauncherFetch.Create;
  Result.Ok := True;
  Result.Data := Scen.Path('launcherStateFixtures.' + Name).Clone;
end;

function Failure(Status: Integer; const Code: string): TBFLauncherFetch;
begin
  Result := TBFLauncherFetch.Create;
  Result.Status := Status;
  Result.ErrorCode := Code;
end;

procedure TestLauncherCore;
var
  Cfg: TBFocusConfig;
  Store: IBFocusStorage;
  L: TBFLauncherCore;
  F: TBFLauncherFetch;
  Ev: TBFLauncherEvents;
begin
  Cfg := ConfigNamed('min');
  Cfg.Notifications := True;
  Store := TBFMemoryStorage.Create;
  L := TBFLauncherCore.Create(Cfg, Store);
  try
    L.LoadPersisted;
    F := Fixture('default');
    Ev := L.Apply(F);
    F.Free;
    Check(leFirstCall in Ev, 'primeira chamada marcada');
    Check(not (leBadge in Ev), 'primeira visita não acende');
    CheckEq(Store.ReadValue(BFLastSeenStorageKey(Cfg)), '2026-09-01T12:00:00+00:00', 'last_seen persistido');
    CheckEq(L.PrimaryColor, '#0EA5E9', 'primary_color');
    CheckEq(L.Pill.Text, 'v4.2.0', 'pílula');
    Check(L.ChatEnabled, 'chat habilitado');
    // Evento novo → "•" + notificação do sistema.
    F := Fixture('default');
    F.Data.ObjOf('tickets').PutStr('latest_event_at', '2026-09-01T12:05:00+00:00');
    Ev := L.Apply(F);
    F.Free;
    Check((leBadge in Ev) and (leNotify in Ev), 'transição para • notifica');
    F := Fixture('default');
    F.Data.ObjOf('tickets').PutStr('latest_event_at', '2026-09-01T12:06:00+00:00');
    Ev := L.Apply(F);
    F.Free;
    Check(not (leNotify in Ev), 'continua • sem notificar de novo');
    // Banner: abre uma vez; aberto não reabre; fechado reabre com a mesma fila.
    F := Fixture('banner');
    Ev := L.Apply(F);
    F.Free;
    Check(leBanner in Ev, 'banner_ids abre o banner');
    L.BannerOpened;
    F := Fixture('banner');
    Ev := L.Apply(F);
    F.Free;
    Check(not (leBanner in Ev), 'mesmo conjunto não reabre com o banner aberto');
    L.BannerClosed;
    L.BrowserMode := True;
    F := Fixture('banner');
    Ev := L.Apply(F);
    F.Free;
    Check(not (leBanner in Ev) and L.Pill.Dot, 'modo navegador: banner não abre sozinho, ponto acende');
    L.BrowserMode := False;
    // Identidade: avisa uma vez por código; volta a avisar depois de um sucesso.
    F := Failure(401, 'WIDGET_USER_HASH_EXPIRED');
    Check(TBFLauncherCore.NeedsHashRetry(F), 'assinatura v2 vencida também pede hash novo');
    F.Free;
    { Mensagem aditiva do Host Protocol: o embed pede identidade nova. }
    Check(BFIsKnownEmbedType('bfocus:identity-expired'), 'bfocus:identity-expired é conhecida');
    Check(not BFIsKnownEmbedType('bfocus:algo-novo'), 'tipo desconhecido segue ignorado');
    F := Failure(401, 'WIDGET_USER_HASH_INVALID');
    Check(TBFLauncherCore.NeedsHashRetry(F), '401 de identidade pede hash novo');
    Ev := L.Apply(F);
    F.Free;
    Check(leError in Ev, '401 chega ao onError');
    CheckEq(L.LastErrorCode, 'WIDGET_USER_HASH_INVALID', 'código do erro');
    F := Failure(401, 'WIDGET_USER_HASH_INVALID');
    Ev := L.Apply(F);
    F.Free;
    Check(not (leError in Ev), 'mesmo código não repete');
    F := Failure(403, '');
    Ev := L.Apply(F);
    F.Free;
    Check(leError in Ev, 'outro 4xx avisa');
    CheckEq(L.LastErrorCode, 'HTTP_403', 'código HTTP_<status>');
    F := Failure(503, '');
    Ev := L.Apply(F);
    F.Free;
    Check(not (leError in Ev), '5xx em silêncio');
    F := Fixture('empty');
    L.Apply(F);
    F.Free;
  finally
    L.Free;
    Cfg.Free;
  end;
end;

procedure TestStorage;
var
  S: IBFocusStorage;
  FileName: string;
begin
  S := TBFMemoryStorage.Create;
  S.WriteValue('bf:read:k:u=1:c:t1', '10');
  S.WriteValue('bf:read:k:u=1:c:t1', '11');
  S.WriteValue('bf:read:k:u=1:c:t2', '12');
  S.WriteValue('bf:lastSeen:k:u=1:c', 'x');
  CheckEq(S.ReadValue('bf:read:k:u=1:c:t1'), '11', 'memória: sobrescreve');
  S.DeletePrefix('bf:read:k:u=1:c:');
  CheckEq(S.ReadValue('bf:read:k:u=1:c:t2'), '', 'memória: apaga por prefixo');
  CheckEq(S.ReadValue('bf:lastSeen:k:u=1:c'), 'x', 'memória: mantém o resto');
  FileName := ExtractFilePath(ParamStr(0)) + 'bfocus-test-' +
    IntToStr(Random(1000000)) + '.ini';
  S := TBFIniStorage.Create(FileName);
  S.WriteValue('bf:lastSeen:k:u=1:c', '2026');
  S := TBFIniStorage.Create(FileName);
  CheckEq(S.ReadValue('bf:lastSeen:k:u=1:c'), '2026', 'ini: persiste em disco');
  S := nil;
  DeleteFile(FileName);
end;

procedure RunCoreTests(const ScenariosFile: string);
begin
  Scen := TBFJson.Parse(LoadFile(ScenariosFile));
  try
    CheckEqInt(Scen.IntOf('hostProtocol'), 1, 'scenarios.hostProtocol');
    RunTest('scenarios.userPayload', TestUserPayload);
    RunTest('scenarios.embedUrl', TestEmbedUrl);
    RunTest('scenarios.launcherStateRequest', TestLauncherStateRequest);
    RunTest('scenarios.badge', TestBadge);
    RunTest('scenarios.pill', TestPill);
    RunTest('scenarios.push', TestPush);
    RunTest('json', TestJson);
    RunTest('texto/url/base64/datas', TestTextUtils);
    RunTest('formatação/html', TestFormat);
    RunTest('i18n e tokens', TestI18nTokens);
    RunTest('configuração', TestConfig);
    RunTest('host protocol', TestHostProtocol);
    RunTest('launcher (núcleo)', TestLauncherCore);
    RunTest('armazenamento local', TestStorage);
  finally
    FreeAndNil(Scen);
  end;
end;

end.
