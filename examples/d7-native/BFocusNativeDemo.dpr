program BFocusNativeDemo;

{ Exemplo mínimo do Delphi 7+ (VCL): telas nativas do widget bFocus. Também compila no
  Delphi 10.4+ (útil para testar a reserva sem WebView2). }

uses
  Forms,
  DemoNativeMain in 'DemoNativeMain.pas';

begin
  Application.Initialize;
  Application.CreateForm(TDemoForm, DemoForm);
  Application.Run;
end.
