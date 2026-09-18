unit BFocusTestKit;

{ Mini-runner de testes (Delphi 7 não tem fpcunit e FPC não tem DUnit): conta checagens,
  imprime as falhas e devolve o código de saída. }

{$I BFocusDefines.inc}

interface

uses
  SysUtils, Classes;

type
  TBFTestProc = procedure;

procedure Section(const Name: string);
procedure Check(Cond: Boolean; const What: string);
procedure CheckEq(const Actual, Expected, What: string); overload;
procedure CheckEqInt(Actual, Expected: Int64; const What: string);
procedure CheckBool(Actual, Expected: Boolean; const What: string);
procedure RunTest(const Name: string; Proc: TBFTestProc);
function Summary: Integer; // código de saída (0 = tudo verde)
function PassedCount: Integer;
function FailedCount: Integer;

implementation

var
  GPassed, GFailed: Integer;
  GSection: string;

procedure Section(const Name: string);
begin
  GSection := Name;
  WriteLn('== ', Name);
end;

procedure Check(Cond: Boolean; const What: string);
begin
  if Cond then
    Inc(GPassed)
  else
  begin
    Inc(GFailed);
    WriteLn('  FALHOU [', GSection, '] ', What);
  end;
end;

procedure CheckEq(const Actual, Expected, What: string);
begin
  if Actual = Expected then
    Inc(GPassed)
  else
  begin
    Inc(GFailed);
    WriteLn('  FALHOU [', GSection, '] ', What);
    WriteLn('    esperado: ', Expected);
    WriteLn('    obtido:   ', Actual);
  end;
end;

procedure CheckEqInt(Actual, Expected: Int64; const What: string);
begin
  CheckEq(IntToStr(Actual), IntToStr(Expected), What);
end;

procedure CheckBool(Actual, Expected: Boolean; const What: string);
begin
  CheckEq(BoolToStr(Actual, True), BoolToStr(Expected, True), What);
end;

procedure RunTest(const Name: string; Proc: TBFTestProc);
begin
  Section(Name);
  try
    Proc;
  except
    on E: Exception do
    begin
      Inc(GFailed);
      WriteLn('  EXCEÇÃO [', Name, '] ', E.ClassName, ': ', E.Message);
    end;
  end;
end;

function Summary: Integer;
begin
  WriteLn;
  WriteLn(Format('checagens: %d ok, %d falhas', [GPassed, GFailed]));
  if GFailed = 0 then
    Result := 0
  else
    Result := 1;
end;

function PassedCount: Integer;
begin
  Result := GPassed;
end;

function FailedCount: Integer;
begin
  Result := GFailed;
end;

end.
