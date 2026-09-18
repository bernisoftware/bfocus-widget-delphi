unit BFocusAsync;

{ Chamadas à API fora da thread da UI (Delphi 7 não tem métodos anônimos nem TTask):
  cada TBFJob roda Work numa thread com um clone próprio da Api e chama Done na thread
  principal (Synchronize). Exceções não cruzam threads: o erro é copiado em campos e
  reconstruído por MakeError. Quem fecha uma tela chama BFJobs.CancelOwner para que um
  Done atrasado não toque num formulário já liberado.
  FPC/Lazarus no Unix: o programa precisa de "cthreads" como primeira unit (padrão nos
  projetos Lazarus). }

{$I BFocusDefines.inc}

interface

uses
  SysUtils, Classes, BFocusText, BFocusJson, BFocusHttp, BFocusApi;

type
  TBFJob = class;
  { Roda na thread de trabalho: só pode usar Job.Api e os argumentos do job. }
  TBFJobWork = function(Job: TBFJob): TBFJson of object;
  { Roda na thread principal. }
  TBFJobDone = procedure(Job: TBFJob) of object;

  TBFJob = class(TThread)
  private
    FApi: TBFocusApi;
    FWork: TBFJobWork;
    FDone: TBFJobDone;
    FOwner: TObject;
    FData: TBFJson;
    FFailed: Boolean;
    FErrorClass: string;
    FErrorMessage: string;
    FErrorCode: string;
    FErrorStatus: Integer;
    FNetKind: TBFNetError;
    procedure Finish;
  protected
    procedure Execute; override;
  public
    { Argumentos livres para o Work (texto, stream de upload, números). }
    Args: TStringList;
    Stream: TMemoryStream;
    Number: Int64;
    Tag: Integer;
    StartedAt: Int64;
    constructor Create(Api: TBFocusApi; Work: TBFJobWork; Done: TBFJobDone; Owner: TObject;
      const AArgs: array of string);
    destructor Destroy; override;
    { Tira o resultado do job (quem chama vira dono). }
    function TakeData: TBFJson;
    { Exceção equivalente à que o Work levantou (quem chama libera); nil se deu certo. }
    function MakeError: Exception;
    function IsIdentityError: Boolean;
    function Arg(I: Integer): string;
    property Api: TBFocusApi read FApi;
    property Data: TBFJson read FData;
    property Failed: Boolean read FFailed;
    property ErrorCode: string read FErrorCode;
    property ErrorStatus: Integer read FErrorStatus;
    property ErrorMessage: string read FErrorMessage;
    property NetKind: TBFNetError read FNetKind;
    property Owner: TObject read FOwner;
  end;

  TBFJobs = class
  private
    FList: TList;
  public
    constructor Create;
    destructor Destroy; override;
    function Run(Api: TBFocusApi; Work: TBFJobWork; Done: TBFJobDone; Owner: TObject;
      const Args: array of string): TBFJob;
    { Jobs desse dono terminam sem chamar Done. }
    procedure CancelOwner(Owner: TObject);
    function RunningFor(Owner: TObject): Integer;
    procedure Remove(Job: TBFJob);
  end;

{ Registro global (só usado na thread principal). }
function BFJobs: TBFJobs;

implementation

var
  GJobs: TBFJobs;

function BFJobs: TBFJobs;
begin
  if GJobs = nil then
    GJobs := TBFJobs.Create;
  Result := GJobs;
end;

{ ── TBFJob ─────────────────────────────────────────────────────────────── }

constructor TBFJob.Create(Api: TBFocusApi; Work: TBFJobWork; Done: TBFJobDone; Owner: TObject;
  const AArgs: array of string);
var
  I: Integer;
begin
  // A thread começa no AfterConstruction (Delphi 6+ e FPC): os campos já estão prontos.
  inherited Create(False);
  FreeOnTerminate := True;
  FApi := Api.Clone;
  FWork := Work;
  FDone := Done;
  FOwner := Owner;
  Args := TStringList.Create;
  for I := 0 to High(AArgs) do
    Args.Add(AArgs[I]);
  Stream := TMemoryStream.Create;
  StartedAt := BFNowUnixMs;
end;

destructor TBFJob.Destroy;
begin
  FData.Free;
  FApi.Free;
  Args.Free;
  Stream.Free;
  inherited Destroy;
end;

procedure TBFJob.Execute;
begin
  try
    FData := FWork(Self);
  except
    on E: Exception do
    begin
      FFailed := True;
      FErrorClass := E.ClassName;
      FErrorMessage := E.Message;
      if E is EBFocusApiError then
      begin
        FErrorStatus := EBFocusApiError(E).Status;
        FErrorCode := EBFocusApiError(E).Code;
      end
      else if E is EBFocusNetworkError then
        FNetKind := EBFocusNetworkError(E).Kind;
    end;
  end;
  Synchronize(Finish);
end;

procedure TBFJob.Finish;
begin
  BFJobs.Remove(Self);
  if Assigned(FDone) then
    FDone(Self);
end;

function TBFJob.TakeData: TBFJson;
begin
  Result := FData;
  FData := nil;
end;

function TBFJob.MakeError: Exception;
begin
  if not FFailed then
    Result := nil
  else if FErrorStatus > 0 then
    Result := EBFocusApiError.CreateCode(FErrorStatus, FErrorCode, FErrorMessage)
  else if FNetKind <> neNone then
    Result := EBFocusNetworkError.CreateNet(FNetKind, FErrorMessage)
  else
    Result := EBFocusError.Create(FErrorMessage);
end;

function TBFJob.IsIdentityError: Boolean;
begin
  Result := (FErrorStatus = 401) and ((FErrorCode = 'WIDGET_USER_HASH_INVALID') or
    (FErrorCode = 'WIDGET_VERIFIED_SESSION_REQUIRED'));
end;

function TBFJob.Arg(I: Integer): string;
begin
  if (I >= 0) and (I < Args.Count) then
    Result := Args[I]
  else
    Result := '';
end;

{ ── TBFJobs ────────────────────────────────────────────────────────────── }

constructor TBFJobs.Create;
begin
  inherited Create;
  FList := TList.Create;
end;

destructor TBFJobs.Destroy;
var
  I: Integer;
begin
  for I := 0 to FList.Count - 1 do
    TBFJob(FList[I]).FDone := nil;
  FList.Free;
  inherited Destroy;
end;

function TBFJobs.Run(Api: TBFocusApi; Work: TBFJobWork; Done: TBFJobDone; Owner: TObject;
  const Args: array of string): TBFJob;
begin
  Result := TBFJob.Create(Api, Work, Done, Owner, Args);
  FList.Add(Result);
end;

procedure TBFJobs.CancelOwner(Owner: TObject);
var
  I: Integer;
begin
  for I := 0 to FList.Count - 1 do
    if TBFJob(FList[I]).FOwner = Owner then
      TBFJob(FList[I]).FDone := nil;
end;

function TBFJobs.RunningFor(Owner: TObject): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to FList.Count - 1 do
    if (TBFJob(FList[I]).FOwner = Owner) and Assigned(TBFJob(FList[I]).FDone) then
      Inc(Result);
end;

procedure TBFJobs.Remove(Job: TBFJob);
begin
  FList.Remove(Job);
end;

initialization

finalization
  FreeAndNil(GJobs);

end.
