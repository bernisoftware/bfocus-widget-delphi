unit BFocusHttpNet;

{ Transporte HTTP do Delphi 10.4+: System.Net.HttpClient (Windows, macOS, Linux; usa o
  TLS do sistema). Só compila em Delphi XE8+; o pacote o usa a partir do 10.4. }

{$I BFocusDefines.inc}

interface

uses
  System.SysUtils, System.Classes, BFocusHttp;

type
  TBFNetHttp = class(TInterfacedObject, IBFocusHttp)
  public
    procedure Execute(Request: TBFHttpRequest; Response: TBFHttpResponse);
  end;

implementation

uses
  System.Net.HttpClient, System.Net.URLClient;

procedure TBFNetHttp.Execute(Request: TBFHttpRequest; Response: TBFHttpResponse);
var
  Client: THTTPClient;
  Req: IHTTPRequest;
  Resp: IHTTPResponse;
  Headers: TNetHeaders;
  I: Integer;
  T0: Cardinal;
  Msg: string;
begin
  Response.Reset;
  Client := THTTPClient.Create;
  try
    Client.ConnectionTimeout := Request.TimeoutMs;
    Client.ResponseTimeout := Request.TimeoutMs;
    Client.HandleRedirects := True;
    T0 := TThread.GetTickCount;
    try
      Req := Client.GetRequest(Request.Method, Request.Url);
      for I := 0 to Request.Headers.Count - 1 do
        Req.SetHeaderValue(Request.Headers.Name(I), Request.Headers.Value(I));
      if Request.Body.Size > 0 then
      begin
        Request.Body.Position := 0;
        Req.SourceStream := Request.Body;
      end;
      // THTTPClient não levanta exceção em 4xx/5xx: o status volta na resposta.
      Resp := Client.Execute(Req, Response.Body);
      Response.Status := Resp.StatusCode;
      Response.StatusText := Resp.StatusText;
      Headers := Resp.Headers;
      for I := 0 to Length(Headers) - 1 do
        Response.Headers.SetValue(Headers[I].Name, Headers[I].Value);
    except
      on E: Exception do
      begin
        Msg := LowerCase(E.Message);
        if (Pos('timeout', Msg) > 0) or (Pos('timed out', Msg) > 0) or
          (TThread.GetTickCount - T0 >= Cardinal(Request.TimeoutMs)) then
          Response.Error := neTimeout
        else
          Response.Error := neNetwork;
        Response.ErrorMessage := E.Message;
        Response.Status := 0;
      end;
    end;
  finally
    Client.Free;
  end;
  Response.Body.Position := 0;
  Request.Body.Position := 0;
end;

end.
