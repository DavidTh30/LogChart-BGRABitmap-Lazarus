program LogChart;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, umain, uchart, ucsvdata, useries, uchartprops, uloading;

{$R *.res}

begin
  RequireDerivedFormResource := True;
  Application.Title := 'LogChart';
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
