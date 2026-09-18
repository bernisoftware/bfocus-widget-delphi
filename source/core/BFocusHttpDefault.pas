unit BFocusHttpDefault;

{ Escolhe o transporte HTTP do compilador/plataforma:
  - Delphi 10.4+          → System.Net.HttpClient
  - Delphi 7 … 10.3       → WinInet
  - FPC/Lazarus Windows   → WinInet (sem DLLs do OpenSSL)
  - FPC/Lazarus Unix/mac  → fphttpclient + OpenSSL }

{$I BFocusDefines.inc}

interface

uses
  BFocusHttp;

function BFDefaultHttp: IBFocusHttp;

implementation

uses
{$IFDEF BF_FPC}
  {$IFDEF MSWINDOWS}
  BFocusHttpWinInet;
  {$ELSE}
  BFocusHttpFpc;
  {$ENDIF}
{$ELSE}
  {$IFDEF BF_D104}
  BFocusHttpNet;
  {$ELSE}
  BFocusHttpWinInet;
  {$ENDIF}
{$ENDIF}

function BFDefaultHttp: IBFocusHttp;
begin
{$IFDEF BF_FPC}
  {$IFDEF MSWINDOWS}
  Result := TBFWinInetHttp.Create;
  {$ELSE}
  Result := TBFFpHttp.Create;
  {$ENDIF}
{$ELSE}
  {$IFDEF BF_D104}
  Result := TBFNetHttp.Create;
  {$ELSE}
  Result := TBFWinInetHttp.Create;
  {$ENDIF}
{$ENDIF}
end;

end.
