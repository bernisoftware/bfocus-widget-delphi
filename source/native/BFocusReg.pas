unit BFocusReg;

{ Registro dos componentes na paleta "bFocus" (Delphi 7+ e Lazarus). O pacote do
  Delphi 10.4+ usa BFocusRegVcl, que acrescenta o TBFocusWidget híbrido. }

{$I BFocusDefines.inc}

interface

procedure Register;

implementation

uses
  Classes, BFocusNativeWidget, BFocusGraphics;

procedure Register;
begin
  RegisterComponents('bFocus', [TBFocusNativeWidget, TBFocusLauncherButton,
    TBFocusReleaseBadge]);
end;

end.
