program BFocusTests;

{ Testes do núcleo (compila em Delphi 7+, Delphi 10.4+ e FPC):
    BFocusTests [--scenarios <arquivo>] [--mock <http://127.0.0.1:porta>]
  Sem --mock roda só os testes sem rede. tests/run-tests.mjs sobe o servidor simulado e
  passa --mock. Saída 0 = tudo verde. }

{$IFDEF FPC}
  {$MODE DELPHI}{$H+}
{$ELSE}
  {$APPTYPE CONSOLE}
{$ENDIF}

uses
  SysUtils,
  BFocusTestKit in 'BFocusTestKit.pas',
  BFocusCoreTests in 'BFocusCoreTests.pas',
  BFocusVMTests in 'BFocusVMTests.pas',
  BFocusIntegrationTests in 'BFocusIntegrationTests.pas';

function Arg(const Name, Default: string): string;
var
  I: Integer;
begin
  Result := Default;
  for I := 1 to ParamCount - 1 do
    if ParamStr(I) = Name then
      Result := ParamStr(I + 1);
end;

var
  Scenarios, Mock: string;
begin
  Scenarios := Arg('--scenarios', ExtractFilePath(ParamStr(0)) + 'scenarios.json');
  Mock := Arg('--mock', '');
  RunCoreTests(Scenarios);
  RunVMTests;
  if Mock <> '' then
    RunIntegrationTests(Mock)
  else
    WriteLn('(integração HTTP pulada: sem --mock)');
  Halt(Summary);
end.
