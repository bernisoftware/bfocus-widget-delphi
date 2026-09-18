unit BFocusRegVcl;

{ Registro para o Delphi 10.4+ (pacote de design): widget híbrido (WebView2), widget
  nativo (reserva sem WebView2 / Windows 7) e os componentes visuais. }

{$I BFocusDefines.inc}

interface

procedure Register;

implementation

uses
  System.Classes, BFocusWidgetVcl, BFocusNativeWidget, BFocusGraphics;

procedure Register;
begin
  RegisterComponents('bFocus', [TBFocusWidget, TBFocusNativeWidget, TBFocusLauncherButton,
    TBFocusReleaseBadge]);
end;

end.
