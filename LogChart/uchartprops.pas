{ ============================================================================
  uchartprops - "Chart properties" window of LogChart (uchartprops.lfm)
    Appearance     : theme (light / dark), 8 colours, font, font sizes
    Axes & lines   : grid lines, time format, date line, line width, lanes
    Mouse & cursor : left drag = move or zoom box, wheel step, value box, crosshair, gaps
    Data & export  : live interval, rows shown after loading, PNG / copy size
  Use:  if TChartPropsForm.Execute(Self, Opt, @ApplyOptions) then ...
  Apply shows the settings in the chart without closing the window.
  ============================================================================ }
unit uchartprops;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls, ComCtrls, Spin, Dialogs, Math,
  uchart;

type
  TOptionsEvent = procedure(const O: TChartOptions) of object;

  { TChartPropsForm }

  TChartPropsForm = class(TForm)
    Bevel1: TBevel;
    Bevel2: TBevel;
    BtnApply: TButton;
    BtnCancel: TButton;
    BtnDark: TButton;
    BtnDefaults: TButton;
    BtnLight: TButton;
    BtnOK: TButton;
    CheckCross: TCheckBox;
    CheckDate: TCheckBox;
    CheckGaps: TCheckBox;
    CheckGridX: TCheckBox;
    CheckGridY: TCheckBox;
    CheckLaneNames: TCheckBox;
    CheckReadout: TCheckBox;
    ColAxis: TColorButton;
    ColBack: TColorButton;
    ColBox: TColorButton;
    ColCursor: TColorButton;
    ColGrid: TColorButton;
    ColPlot: TColorButton;
    ColPlot2: TColorButton;
    ColText: TColorButton;
    ComboFont: TComboBox;
    ComboLeft: TComboBox;
    ComboTimeFmt: TComboBox;
    LblAxis: TLabel;
    LblAxisFont: TLabel;
    LblBack: TLabel;
    LblBox: TLabel;
    LblCursor: TLabel;
    LblExpHint: TLabel;
    LblExport: TLabel;
    LblFont: TLabel;
    LblGap: TLabel;
    LblGrid: TLabel;
    LblLabelFont: TLabel;
    LblLeft: TLabel;
    LblLive: TLabel;
    LblPlot: TLabel;
    LblPlot2: TLabel;
    LblText: TLabel;
    LblTheme: TLabel;
    LblTimeFmt: TLabel;
    LblWheel: TLabel;
    LblWidth: TLabel;
    LblX: TLabel;
    LblStartRows: TLabel;
    LblStartHint: TLabel;
    SpinStartRows: TSpinEdit;
    Pages: TPageControl;
    PanelBtns: TPanel;
    SpinAxisFont: TSpinEdit;
    SpinExpH: TSpinEdit;
    SpinExpW: TSpinEdit;
    SpinGap: TSpinEdit;
    SpinLabelFont: TSpinEdit;
    SpinLive: TSpinEdit;
    SpinWheel: TSpinEdit;
    SpinWidth: TFloatSpinEdit;
    TabAxes: TTabSheet;
    TabLive: TTabSheet;
    TabLook: TTabSheet;
    TabMouse: TTabSheet;
    procedure BtnApplyClick(Sender: TObject);
    procedure BtnDarkClick(Sender: TObject);
    procedure BtnDefaultsClick(Sender: TObject);
    procedure BtnLightClick(Sender: TObject);
  private
    FOnApply: TOptionsEvent;
    procedure ToEditors(const O: TChartOptions);
    procedure ToColours(const O: TChartOptions);
    function FromEditors: TChartOptions;
  public
    class function Execute(AOwner: TComponent; var O: TChartOptions; OnApply: TOptionsEvent): Boolean;
  end;

implementation

{$R *.lfm}

procedure TChartPropsForm.ToColours(const O: TChartOptions);
begin
  ColBack.ButtonColor := O.BackColor;
  ColPlot.ButtonColor := O.PlotColor;
  ColPlot2.ButtonColor := O.PlotColor2;
  ColGrid.ButtonColor := O.GridColor;
  ColAxis.ButtonColor := O.AxisColor;
  ColText.ButtonColor := O.TextColor;
  ColCursor.ButtonColor := O.CursorColor;
  ColBox.ButtonColor := O.BoxColor;
end;

procedure TChartPropsForm.ToEditors(const O: TChartOptions);
begin
  ToColours(O);
  ComboFont.Text := O.FontName;
  SpinAxisFont.Value := O.AxisFont;
  SpinLabelFont.Value := O.LabelFont;
  CheckGridX.Checked := O.GridX;
  CheckGridY.Checked := O.GridY;
  ComboTimeFmt.ItemIndex := O.TimeFormat;
  CheckDate.Checked := O.ShowDate;
  SpinWidth.Value := O.LineWidth;
  CheckLaneNames.Checked := O.LaneNames;
  SpinGap.Value := O.LaneGap;
  ComboLeft.ItemIndex := O.LeftDrag;
  SpinWheel.Value := O.WheelPercent;
  CheckReadout.Checked := O.ShowReadout;
  CheckCross.Checked := O.Crosshair;
  CheckGaps.Checked := O.ShowGaps;
  SpinLive.Value := O.LiveMs;
  SpinExpW.Value := O.ExportW;
  SpinExpH.Value := O.ExportH;
  SpinStartRows.Value := O.StartRows;
end;

function TChartPropsForm.FromEditors: TChartOptions;
begin
  Result := DefaultChartOptions;
  Result.BackColor := ColBack.ButtonColor;
  Result.PlotColor := ColPlot.ButtonColor;
  Result.PlotColor2 := ColPlot2.ButtonColor;
  Result.GridColor := ColGrid.ButtonColor;
  Result.AxisColor := ColAxis.ButtonColor;
  Result.TextColor := ColText.ButtonColor;
  Result.CursorColor := ColCursor.ButtonColor;
  Result.BoxColor := ColBox.ButtonColor;
  if Trim(ComboFont.Text) <> '' then Result.FontName := Trim(ComboFont.Text);
  Result.AxisFont := SpinAxisFont.Value;
  Result.LabelFont := SpinLabelFont.Value;
  Result.GridX := CheckGridX.Checked;
  Result.GridY := CheckGridY.Checked;
  Result.TimeFormat := Max(0, ComboTimeFmt.ItemIndex);
  Result.ShowDate := CheckDate.Checked;
  Result.LineWidth := SpinWidth.Value;
  Result.LaneNames := CheckLaneNames.Checked;
  Result.LaneGap := SpinGap.Value;
  Result.LeftDrag := Max(0, ComboLeft.ItemIndex);
  Result.WheelPercent := SpinWheel.Value;
  Result.ShowReadout := CheckReadout.Checked;
  Result.Crosshair := CheckCross.Checked;
  Result.ShowGaps := CheckGaps.Checked;
  Result.LiveMs := SpinLive.Value;
  Result.ExportW := SpinExpW.Value;
  Result.ExportH := SpinExpH.Value;
  Result.StartRows := SpinStartRows.Value;
end;

procedure TChartPropsForm.BtnLightClick(Sender: TObject);
begin
  ToColours(DefaultChartOptions);
end;

procedure TChartPropsForm.BtnDarkClick(Sender: TObject);
begin
  ToColours(DarkChartOptions);
end;

procedure TChartPropsForm.BtnDefaultsClick(Sender: TObject);
begin
  ToEditors(DefaultChartOptions);
end;

procedure TChartPropsForm.BtnApplyClick(Sender: TObject);
begin
  if Assigned(FOnApply) then FOnApply(FromEditors);
end;

class function TChartPropsForm.Execute(AOwner: TComponent; var O: TChartOptions;
  OnApply: TOptionsEvent): Boolean;
var
  F: TChartPropsForm;
begin
  F := TChartPropsForm.Create(AOwner);
  try
    F.ComboFont.Items.Assign(Screen.Fonts);
    F.FOnApply := OnApply;
    F.Pages.ActivePageIndex := 0;
    F.ToEditors(O);
    Result := F.ShowModal = mrOK;
    if Result then O := F.FromEditors;
  finally
    F.Free;
  end;
end;

end.
