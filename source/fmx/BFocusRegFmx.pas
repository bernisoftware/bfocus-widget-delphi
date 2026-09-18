unit BFocusRegFmx;

{ Registro dos componentes FMX na paleta "bFocus" (pacote de design do Delphi 10.4+). }

{$I BFocusDefines.inc}

interface

procedure Register;

implementation

uses
  System.Classes, FMX.Types, BFocusWidgetFmx;

procedure Register;
begin
  // Só aparecem no designer FMX.
  GroupDescendentsWith(TBFocusFmxWidget, TFmxObject);
  RegisterComponents('bFocus', [TBFocusFmxWidget, TBFocusFmxLauncherButton,
    TBFocusFmxReleaseBadge]);
end;

end.
