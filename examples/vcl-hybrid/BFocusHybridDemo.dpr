program BFocusHybridDemo;

{ Exemplo mínimo do Delphi 10.4+ (VCL): widget híbrido com WebView2. Copie o
  WebView2Loader.dll (redist do RAD Studio) para a pasta do .exe. }

uses
  Vcl.Forms,
  DemoHybridMain in 'DemoHybridMain.pas';

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TDemoForm, DemoForm);
  Application.Run;
end.
