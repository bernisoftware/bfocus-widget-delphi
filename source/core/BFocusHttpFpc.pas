unit BFocusHttpFpc;

{ Transporte HTTP do Free Pascal (Lazarus em Linux/macOS): fphttpclient + OpenSSL.
  No Windows o Lazarus usa BFocusHttpWinInet (sem depender das DLLs do OpenSSL). }

{$I BFocusDefines.inc}

interface

uses
  SysUtils, Classes, BFocusHttp;

type
  TBFFpHttp = class(TInterfacedObject, IBFocusHttp)
  public
    procedure Execute(Request: TBFHttpRequest; Response: TBFHttpResponse);
  end;

implementation

uses
  fphttpclient, opensslsockets;

procedure TBFFpHttp.Execute(Request: TBFHttpRequest; Response: TBFHttpResponse);
var
  Client: TFPHTTPClient;
  I: Integer;
  T0: QWord;
  Msg: string;
begin
  Response.Reset;
  Client := TFPHTTPClient.Create(nil);
  try
    // fphttpclient não tem tempo total: conexão e cada leitura usam o mesmo limite.
    Client.ConnectTimeout := Request.TimeoutMs;
    Client.IOTimeout := Request.TimeoutMs;
    Client.AllowRedirect := True;
    Client.KeepConnection := False;
    for I := 0 to Request.Headers.Count - 1 do
      Client.AddHeader(Request.Headers.Name(I), Request.Headers.Value(I));
    if Request.Body.Size > 0 then
    begin
      Request.Body.Position := 0;
      Client.RequestBody := Request.Body;
    end;
    T0 := GetTickCount64;
    try
      // Lista vazia de códigos permitidos = aceita qualquer status (401, 404…).
      Client.HTTPMethod(Request.Method, Request.Url, Response.Body, []);
      Response.Status := Client.ResponseStatusCode;
      Response.StatusText := Client.ResponseStatusText;
      for I := 0 to Client.ResponseHeaders.Count - 1 do
        Response.Headers.AddLine(Client.ResponseHeaders[I]);
    except
      on E: Exception do
      begin
        Msg := LowerCase(E.Message);
        if (Pos('timeout', Msg) > 0) or (Pos('timed out', Msg) > 0) or
          (GetTickCount64 - T0 >= QWord(Request.TimeoutMs)) then
          Response.Error := neTimeout
        else
          Response.Error := neNetwork;
        Response.ErrorMessage := E.Message;
        Response.Status := 0;
      end;
    end;
  finally
    Client.RequestBody := nil; // o corpo é do request, não do cliente
    Client.Free;
  end;
  Response.Body.Position := 0;
  Request.Body.Position := 0;
end;

end.
