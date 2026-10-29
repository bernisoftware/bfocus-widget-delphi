unit BFocusIntegrationTests;

{ Integração HTTP contra widgets-native/conformance/mock-server.mjs (BRIEF §5.2). Recebe a
  base do servidor (http://127.0.0.1:<porta>) de tests/run-tests.mjs. Usa o transporte
  padrão do compilador (fphttpclient no FPC fora do Windows). }

{$I BFocusDefines.inc}

interface

procedure RunIntegrationTests(const BaseUrl: string);

implementation

uses
  SysUtils, Classes, BFocusTestKit, BFocusText, BFocusJson, BFocusHttp, BFocusHttpDefault,
  BFocusConfig, BFocusModels, BFocusApi, BFocusLauncher, BFocusStorage;

var
  Base: string;
  Http: IBFocusHttp;

function Raw(const Method, Path: string; const Body: TBFRaw): TBFJson;
var
  Req: TBFHttpRequest;
  Resp: TBFHttpResponse;
begin
  Req := TBFHttpRequest.Create(Method, Base + Path);
  Resp := TBFHttpResponse.Create;
  try
    if Body <> '' then
    begin
      Req.Headers.SetValue('Content-Type', 'application/json');
      Req.SetBodyRaw(Body);
    end;
    Http.Execute(Req, Resp);
    Result := TBFJson.TryParse(Resp.BodyRaw);
  finally
    Resp.Free;
    Req.Free;
  end;
end;

procedure Reset;
begin
  Raw('POST', '/__reset', '{}').Free;
end;

{ Última request registrada pelo servidor para /api/…. }
function LastRequest(Log: TBFJson): TBFJson;
var
  Reqs: TBFJson;
begin
  Result := nil;
  Reqs := Log.ArrOf('requests');
  if (Reqs <> nil) and (Reqs.Count > 0) then
    Result := Reqs.Item(Reqs.Count - 1);
end;

function NewConfig: TBFocusConfig;
begin
  Result := TBFocusConfig.Create;
  Result.PublishableKey := 'bf_pk_test_123';
  Result.AppId := 'com.empresa.erp';
  Result.User.ExternalId := 'USR-1';
  Result.Customer.ExternalId := 'ACME-1';
  Result.Customer.Name := BFFromUtf8('A'#$C3#$A7'a'#$C3#$AD' & Cia');
  Result.ApiBaseUrl := Base;
  Result.EmbedBaseUrl := Base + '/v1';
end;

procedure TestLauncherState;
var
  Cfg: TBFocusConfig;
  Api: TBFocusApi;
  F: TBFLauncherFetch;
  Log, Req, H: TBFJson;
  L: TBFLauncherCore;
  Store: IBFocusStorage;
  Ev: TBFLauncherEvents;
begin
  Cfg := NewConfig;
  Store := TBFMemoryStorage.Create;
  L := TBFLauncherCore.Create(Cfg, Store);
  try
    // default
    Reset;
    Api := TBFocusApi.Create(Cfg, Http);
    try
      F := TBFLauncherCore.Fetch(Api);
      try
        Check(F.Ok, 'default: resposta ok');
        CheckEq(F.Data.StrOf('primary_color'), '#0EA5E9', 'default: data do envelope');
        Ev := L.Apply(F);
        Check(leFirstCall in Ev, 'default: primeira chamada');
      finally
        F.Free;
      end;
    finally
      Api.Free;
    end;
    Log := Raw('GET', '/__log', '');
    try
      Req := LastRequest(Log);
      Check(Req <> nil, 'log registrou a request');
      if Req <> nil then
      begin
        CheckEq(Req.StrOf('method'), 'POST', 'método');
        CheckEq(Req.StrOf('path'), '/api/v1/widget/launcher-state', 'caminho');
        CheckEq(Req.StrOf('body'), '{}', 'corpo {}');
        H := Req.ObjOf('headers');
        CheckEq(H.StrOf('x-bfocus-widget-key'), 'bf_pk_test_123', 'header chave');
        CheckEq(H.StrOf('x-bfocus-widget-user'), BFUserHeader(Cfg), 'header usuário (com Açaí)');
        CheckEq(H.StrOf('x-bfocus-parent-origin'), 'app://com.empresa.erp', 'header origem');
        CheckEq(H.StrOf('x-bfocus-client'), BF_CLIENT_FAMILY + '/' + BF_PACKAGE_VERSION, 'header cliente');
        Check(Pos('application/json', H.StrOf('content-type')) = 1, 'header content-type');
      end;
    finally
      Log.Free;
    end;

    // banner (produto/público vão na query)
    Reset;
    Raw('POST', '/__scenario', '{"name":"banner"}').Free;
    Cfg.Product := 'erp';
    Cfg.Audience := 'both';
    Api := TBFocusApi.Create(Cfg, Http);
    try
      F := TBFLauncherCore.Fetch(Api);
      try
        Check(F.Ok, 'banner: ok');
        Ev := L.Apply(F);
        Check(leBanner in Ev, 'banner: abre o banner');
        CheckEqInt(L.Pill.BannerIds.Count, 2, 'banner: 2 ids');
      finally
        F.Free;
      end;
    finally
      Api.Free;
    end;
    Log := Raw('GET', '/__log', '');
    try
      Req := LastRequest(Log);
      if Req <> nil then
      begin
        CheckEq(Req.Path('query').StrOf('product'), 'erp', 'query product');
        CheckEq(Req.Path('query').StrOf('audience'), 'both', 'query audience');
      end;
    finally
      Log.Free;
    end;

    // identity_error: 401 com o código no envelope
    Reset;
    Raw('POST', '/__scenario', '{"name":"identity_error"}').Free;
    Api := TBFocusApi.Create(Cfg, Http);
    try
      F := TBFLauncherCore.Fetch(Api);
      try
        Check(not F.Ok, 'identity_error: falha');
        CheckEqInt(F.Status, 401, 'identity_error: 401');
        CheckEq(F.ErrorCode, 'WIDGET_USER_HASH_INVALID', 'identity_error: código do envelope');
        Check(TBFLauncherCore.NeedsHashRetry(F), 'identity_error: pede hash novo');
        Ev := L.Apply(F);
        Check(leError in Ev, 'identity_error: onError');
      finally
        F.Free;
      end;
    finally
      Api.Free;
    end;
  finally
    L.Free;
    Cfg.Free;
  end;
end;

procedure TestApiEndpoints;
var
  Cfg: TBFocusConfig;
  Api: TBFocusApi;
  Log, Req: TBFJson;
  Data: TMemoryStream;
  Body: string;
  Hit: Boolean;

  procedure Expect404(const What, Path: string);
  begin
    Log := Raw('GET', '/__log', '');
    try
      Req := LastRequest(Log);
      Check((Req <> nil) and (Req.StrOf('path') = Path), What + ' → ' + Path);
    finally
      Log.Free;
    end;
  end;

begin
  Cfg := NewConfig;
  Cfg.Product := 'erp';
  Api := TBFocusApi.Create(Cfg, Http);
  try
    // Push existe no servidor simulado: 200 {data:{ok:true}}.
    Reset;
    Api.PushRegister('fcm-token-1', 'android');
    Log := Raw('GET', '/__log', '');
    try
      Req := LastRequest(Log);
      CheckEq(Req.StrOf('path'), '/api/v1/widget/push/devices', 'push register');
      Check(Pos('"app_id":"com.empresa.erp"', Req.StrOf('body')) > 0, 'push register corpo');
    finally
      Log.Free;
    end;
    Api.PushUnregister('fcm-token-1');
    Expect404('push unregister', '/api/v1/widget/push/devices/unregister');

    // O resto não existe no simulado (404), mas a request fica no log: confere o mapa.
    Hit := False;
    try
      Api.ListTickets.Free;
    except
      on E: EBFocusApiError do
      begin
        Hit := True;
        CheckEqInt(E.Status, 404, '404 vira EBFocusApiError');
        CheckEq(E.Code, 'not found', 'código do envelope');
      end;
    end;
    Check(Hit, 'erro HTTP levanta exceção');
    Expect404('tickets', '/api/v1/widget/tickets');
    Check(Api.ListTicketConversations('t-1') = nil, 'conversas: 404 = nil');
    Expect404('conversas', '/api/v1/widget/tickets/t-1/conversations');
    try Api.ChatEvents('c-1', 7).Free; except on EBFocusApiError do ; end;
    Log := Raw('GET', '/__log', '');
    try
      Req := LastRequest(Log);
      CheckEq(Req.Path('query').StrOf('after'), '7', 'events?after=');
    finally
      Log.Free;
    end;
    try Api.ChatAvailability.Free; except on EBFocusApiError do ; end;
    Expect404('availability', '/api/v1/widget/chat/availability');
    try Api.ReleaseNotesPending.Free; except on EBFocusApiError do ; end;
    Expect404('pending', '/api/v1/widget/release-notes/pending');
    try Api.ListReleaseNotes.Free; except on EBFocusApiError do ; end;
    Log := Raw('GET', '/__log', '');
    try
      Req := LastRequest(Log);
      CheckEq(Req.StrOf('path'), '/api/v1/widget/release-notes', 'release-notes (splash)');
      CheckEq(Req.Path('query').StrOf('product'), 'erp', 'splash com o produto do widget');
    finally
      Log.Free;
    end;
    try Api.GetConfig.Free; except on EBFocusApiError do ; end;
    Log := Raw('GET', '/__log', '');
    try
      Req := LastRequest(Log);
      CheckEq(Req.StrOf('path'), '/api/v1/widget/config', 'config');
      CheckEq(Req.ObjOf('headers').StrOf('x-bfocus-widget-user'), '', 'config sem usuário');
    finally
      Log.Free;
    end;
    try
      Api.CreateTicket('bug', 'T' + BFFromUtf8(#$C3#$AD) + 'tulo', '<p>x</p>', 'high', '', nil).Free;
    except
      on EBFocusApiError do ;
    end;
    Log := Raw('GET', '/__log', '');
    try
      Req := LastRequest(Log);
      Check(Pos('"product_slug":"erp"', Req.StrOf('body')) > 0, 'createTicket leva product_slug');
      Check(Pos('"priority":"high"', Req.StrOf('body')) > 0, 'createTicket prioridade');
    finally
      Log.Free;
    end;

    // Upload multipart (conteúdo binário com bytes altos).
    Data := TMemoryStream.Create;
    try
      BFRawToStream(#0#1#$FF#$C3'PNG', Data);
      try
        Api.Upload('foto ' + BFFromUtf8(#$C3#$A7) + '.png', Data).Free;
      except
        on EBFocusApiError do ;
      end;
    finally
      Data.Free;
    end;
    Log := Raw('GET', '/__log', '');
    try
      Req := LastRequest(Log);
      CheckEq(Req.StrOf('path'), '/api/v1/widget/upload', 'upload caminho');
      Check(Pos('multipart/form-data; boundary=', Req.ObjOf('headers').StrOf('content-type')) = 1,
        'upload content-type multipart');
      Body := Req.StrOf('body');
      Check(Pos('name="file"; filename="foto ' + BFFromUtf8(#$C3#$A7) + '.png"', Body) > 0,
        'upload nome do arquivo em UTF-8');
      Check(Pos('Content-Type: image/png', Body) > 0, 'upload tipo da parte');
      Check(Req.ObjOf('headers').StrOf('x-bfocus-widget-user') <> '', 'upload com usuário');
    finally
      Log.Free;
    end;

    // Download de URL absoluta (sem headers do widget).
    Data := TMemoryStream.Create;
    try
      Api.DownloadTo(Base + '/files/manual.pdf', Data);
      Check(Copy(BFRawFromStream(Data), 1, 5) = '%PDF-', 'download do PDF');
    finally
      Data.Free;
    end;
  finally
    Api.Free;
    Cfg.Free;
  end;
end;

procedure TestNetworkError;
var
  Cfg: TBFocusConfig;
  Api: TBFocusApi;
  F: TBFLauncherFetch;
begin
  Cfg := NewConfig;
  Cfg.ApiBaseUrl := 'http://127.0.0.1:1';
  Api := TBFocusApi.Create(Cfg, Http);
  try
    F := TBFLauncherCore.Fetch(Api);
    try
      Check(not F.Ok and (F.NetError <> neNone), 'porta fechada = erro de rede silencioso');
    finally
      F.Free;
    end;
  finally
    Api.Free;
    Cfg.Free;
  end;
end;

procedure RunIntegrationTests(const BaseUrl: string);
begin
  Base := BFTrimRightSlashes(BaseUrl);
  Http := BFDefaultHttp;
  RunTest('integração: launcher-state (default, banner, identity_error)', TestLauncherState);
  RunTest('integração: mapa da API, push, upload, download', TestApiEndpoints);
  RunTest('integração: erro de rede', TestNetworkError);
  Http := nil;
end;

end.
