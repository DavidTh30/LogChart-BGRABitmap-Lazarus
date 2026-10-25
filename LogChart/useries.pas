{ ============================================================================
  useries - the series list of LogChart as a window of its own (useries.lfm)
    - check box = show / hide, double-click = only this one, All / None
    - tab Properties: everything about the selected series, changes are used at once
        column, type, values, range in the file (read only)
        display name, show, colour, line width / style, lines or steps, points,
        gain / offset / unit (shown value = file value x gain + offset), Y axis range
    - tab Statistics: of the selected series in the visible time range
  The main window fills the list and handles its events (umain). This window
  stays above the main window, closing it only hides it (View > Series window),
  and the menu shortcuts of the main window work here too.
  ============================================================================ }
unit useries;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls, CheckLst, Menus, LMessages,
  ComCtrls, Spin, Dialogs, Math, ucsvdata, uchart;

type

  { TSeriesForm }

  TSeriesForm = class(TForm)
    Bevel1: TBevel;
    Bevel2: TBevel;
    Bevel3: TBevel;
    BtnDefaults: TButton;
    BtnShowAll: TButton;
    BtnShowNone: TButton;
    CheckAutoY: TCheckBox;
    CheckVisible: TCheckBox;
    ColorBtn: TColorButton;
    ComboMode: TComboBox;
    ComboPoints: TComboBox;
    ComboStyle: TComboBox;
    EditGain: TEdit;
    EditOffset: TEdit;
    EditTitle: TEdit;
    EditUnit: TEdit;
    EditYMax: TEdit;
    EditYMin: TEdit;
    LabelSeries: TLabel;
    LabelStats: TLabel;
    LblColor: TLabel;
    LblColumn: TLabel;
    LblColumnC: TLabel;
    LblCount: TLabel;
    LblCountC: TLabel;
    LblFileRange: TLabel;
    LblFileRangeC: TLabel;
    LblGain: TLabel;
    LblMode: TLabel;
    LblOffset: TLabel;
    LblPoints: TLabel;
    LblScaleInfo: TLabel;
    LblStyle: TLabel;
    LblTitle: TLabel;
    LblType: TLabel;
    LblTypeC: TLabel;
    LblUnit: TLabel;
    LblWidth: TLabel;
    LblYAxis: TLabel;
    LblYMax: TLabel;
    LblYMin: TLabel;
    ListSeries: TCheckListBox;
    PageSeries: TPageControl;
    PanelListBtns: TPanel;
    PanelTop: TPanel;
    ScrollProps: TScrollBox;
    SpinPointSize: TFloatSpinEdit;
    SpinWidth: TFloatSpinEdit;
    Splitter1: TSplitter;
    TabProps: TTabSheet;
    TabStats: TTabSheet;
    procedure BtnDefaultsClick(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormShortCut(var Msg: TLMKey; var Handled: Boolean);
    procedure NumberDone(Sender: TObject);
    procedure PropChange(Sender: TObject);
  private
    FSer: TLogSeries;
    FChart: TLogChart;
    FUpdating: Boolean;
    FOnChanged: TNotifyEvent;
    procedure Changed;
    procedure EnableEditors(On: Boolean);
  public
    ShortcutMenu: TMainMenu;      // menu of the main window (its shortcuts work here too)
    { show the properties of S in the editors (nil = none) }
    procedure ShowSeries(S: TLogSeries; AChart: TLogChart);
    { the Y range of the chart changed (mouse): show it, unless the user types in it }
    procedure RefreshRange;
    property Series: TLogSeries read FSer;
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
  end;

implementation

{$R *.lfm}

function NumText(V: Double): string;
begin
  if IsNan(V) then Result := ''
  else Result := FloatToStrF(V, ffGeneral, 7, 0, ChartFmt);
end;

function ParseNum(const S: string; out V: Double): Boolean;
begin
  Result := TryStrToFloat(Trim(StringReplace(S, ',', '.', [])), V, ChartFmt);
end;

procedure TSeriesForm.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  CloseAction := caHide;          // shown again with View > Series window
end;

procedure TSeriesForm.FormShortCut(var Msg: TLMKey; var Handled: Boolean);
begin
  if Assigned(ShortcutMenu) then Handled := ShortcutMenu.IsShortCut(Msg);
end;

procedure TSeriesForm.EnableEditors(On: Boolean);
var
  I: Integer;
begin
  for I := 0 to ScrollProps.ControlCount - 1 do
    if not (ScrollProps.Controls[I] is TLabel) and not (ScrollProps.Controls[I] is TBevel) then
      ScrollProps.Controls[I].Enabled := On;
end;

procedure TSeriesForm.ShowSeries(S: TLogSeries; AChart: TLogChart);
var
  Lo, Hi: Double;
begin
  FSer := S;
  FChart := AChart;
  FUpdating := True;
  try
    EnableEditors((S <> nil) and S.Numeric);
    if S = nil then
    begin
      LblColumn.Caption := '-';
      LblType.Caption := '-';
      LblCount.Caption := '-';
      LblFileRange.Caption := '-';
      Exit;
    end;
    LblColumn.Caption := S.Name;
    LblColumn.Hint := S.Name;
    if not S.Numeric then LblType.Caption := 'text (not drawn)'
    else if S.IsBool then LblType.Caption := 'BOOL (only 0 / 1)'
    else LblType.Caption := 'number';
    LblCount.Caption := Format('%d', [S.NumCount]);
    if S.Numeric then LblFileRange.Caption := NumText(S.MinV) + ' .. ' + NumText(S.MaxV)
    else LblFileRange.Caption := '-';
    EditTitle.Text := S.Title;
    EditTitle.TextHint := S.Name;
    CheckVisible.Checked := S.Visible;
    ColorBtn.ButtonColor := TColor(S.Color);
    SpinWidth.Value := S.LineWidth;
    ComboStyle.ItemIndex := EnsureRange(S.LineStyle, 0, 3);
    ComboMode.ItemIndex := EnsureRange(S.DrawMode, 0, 2);
    ComboPoints.ItemIndex := EnsureRange(S.PointMode, 0, 2);
    SpinPointSize.Value := S.PointSize;
    EditGain.Text := NumText(S.Gain);
    EditOffset.Text := NumText(S.Offset);
    EditUnit.Text := S.UnitText;
    CheckAutoY.Checked := not S.YManual;
    if (FChart <> nil) and FChart.CurrentRange(S, Lo, Hi) then
    begin
      EditYMin.Text := NumText(Lo);
      EditYMax.Text := NumText(Hi);
    end
    else if S.YManual then
    begin
      EditYMin.Text := NumText(S.YLo);
      EditYMax.Text := NumText(S.YHi);
    end
    else
    begin
      S.ScaledMinMax(Lo, Hi);
      EditYMin.Text := NumText(Lo);
      EditYMax.Text := NumText(Hi);
    end;
  finally
    FUpdating := False;
  end;
end;

procedure TSeriesForm.RefreshRange;
var
  Lo, Hi: Double;
begin
  if (FSer = nil) or (FChart = nil) or EditYMin.Focused or EditYMax.Focused then Exit;
  FUpdating := True;
  try
    CheckAutoY.Checked := not FSer.YManual;
    if FChart.CurrentRange(FSer, Lo, Hi) then
    begin
      EditYMin.Text := NumText(Lo);
      EditYMax.Text := NumText(Hi);
    end;
  finally
    FUpdating := False;
  end;
end;

procedure TSeriesForm.Changed;
begin
  if Assigned(FOnChanged) then FOnChanged(Self);
end;

{ editors that are used at once (text, check boxes, lists, colour) }
procedure TSeriesForm.PropChange(Sender: TObject);
var
  Lo, Hi: Double;
begin
  if FUpdating or (FSer = nil) then Exit;
  FSer.Title := Trim(EditTitle.Text);
  FSer.Visible := CheckVisible.Checked;
  FSer.Color := Cardinal(ColorToRGB(ColorBtn.ButtonColor));
  FSer.LineWidth := SpinWidth.Value;
  FSer.LineStyle := Max(0, ComboStyle.ItemIndex);
  FSer.DrawMode := Max(0, ComboMode.ItemIndex);
  FSer.PointMode := Max(0, ComboPoints.ItemIndex);
  FSer.PointSize := SpinPointSize.Value;
  FSer.UnitText := Trim(EditUnit.Text);
  if Sender = CheckAutoY then
  begin
    if CheckAutoY.Checked then
      FSer.YManual := False
    else if ParseNum(EditYMin.Text, Lo) and ParseNum(EditYMax.Text, Hi) and (Hi > Lo) then
    begin
      FSer.YManual := True;
      FSer.YLo := Lo;
      FSer.YHi := Hi;
    end;
  end;
  Changed;
end;

{ number editors: used when the editing is done (Enter / leaving the field) }
procedure TSeriesForm.NumberDone(Sender: TObject);
var
  V, Lo, Hi: Double;
begin
  if FUpdating or (FSer = nil) then Exit;
  if (Sender = EditGain) and ParseNum(EditGain.Text, V) and (V <> 0) then FSer.Gain := V;
  if (Sender = EditOffset) and ParseNum(EditOffset.Text, V) then FSer.Offset := V;
  if (Sender = EditYMin) or (Sender = EditYMax) then
    if ParseNum(EditYMin.Text, Lo) and ParseNum(EditYMax.Text, Hi) and (Hi > Lo) then
    begin
      { a typed range = manual Y axis }
      FSer.YManual := True;
      FSer.YLo := Lo;
      FSer.YHi := Hi;
      FUpdating := True;
      CheckAutoY.Checked := False;
      FUpdating := False;
    end;
  if Sender = EditGain then EditGain.Text := NumText(FSer.Gain);
  if Sender = EditOffset then EditOffset.Text := NumText(FSer.Offset);
  Changed;
end;

procedure TSeriesForm.BtnDefaultsClick(Sender: TObject);
var
  C: Cardinal;
  T: string;
begin
  if FSer = nil then Exit;
  C := FSer.Color;
  T := FSer.Title;
  FSer.ResetProps;
  FSer.Color := C;
  FSer.Title := T;
  ShowSeries(FSer, FChart);
  Changed;
end;

end.
