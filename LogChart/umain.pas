{ ============================================================================
  LogChart - main window (normal Lazarus form, umain.lfm)
  Shows the CSV files of the PLC Data Logger as a chart (BGRABitmap, uchart).
    - File: Open (several days at once) / Add files / Open folder / Reload / Export PNG / Copy
    - series list in its own window (useries): show / hide, colour, double-click = only this one,
      statistics of the selected series in the visible time range
    - all commands in the menu (no tool bar)
    - big files: Loading window with progress and Cancel (uloading)
    - Snapshot to CSV: the visible time range and series as a new CSV file
    - Live: reads the rows the logger adds, every second, and follows the end
    - files can also be dropped on the window or given on the command line
  ============================================================================ }
unit umain;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, Menus, ExtCtrls, StdCtrls,
  CheckLst, ComCtrls, Clipbrd, IniFiles, Math, LCLType, LCLIntf, Themes,
  BGRABitmap, BGRABitmapTypes, ucsvdata, uchart, useries, uchartprops, uloading;

type

  { TMainForm }

  TMainForm = class(TForm)
    MainMenu1: TMainMenu;
    MenuAbout: TMenuItem;
    MenuAdd: TMenuItem;
    MenuAutoY: TMenuItem;
    MenuCopy: TMenuItem;
    MenuExit: TMenuItem;
    MenuFile: TMenuItem;
    MenuFit: TMenuItem;
    MenuFitY: TMenuItem;
    MenuFolder: TMenuItem;
    MenuHelp: TMenuItem;
    MenuLanes: TMenuItem;
    MenuLive: TMenuItem;
    MenuMouse: TMenuItem;
    MenuOpen: TMenuItem;
    MenuPng: TMenuItem;
    MenuPoints: TMenuItem;
    MenuReload: TMenuItem;
    MenuSep1: TMenuItem;
    MenuSep2: TMenuItem;
    MenuSep3: TMenuItem;
    MenuSep4: TMenuItem;
    MenuSeriesWin: TMenuItem;
    MenuSep5: TMenuItem;
    MenuBoxMode: TMenuItem;
    MenuChartProps: TMenuItem;
    MenuZoomBack: TMenuItem;
    MenuSnapshot: TMenuItem;
    SaveCsvDialog: TSaveDialog;
    MenuView: TMenuItem;
    MenuZoomIn: TMenuItem;
    MenuZoomOut: TMenuItem;
    OpenDialog1: TOpenDialog;
    SavePngDialog: TSaveDialog;
    SelectDirectoryDialog1: TSelectDirectoryDialog;
    StatusBar1: TStatusBar;
    TimerLive: TTimer;
    procedure BtnShowAllClick(Sender: TObject);
    procedure BtnShowNoneClick(Sender: TObject);

    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormDropFiles(Sender: TObject; const FileNames: array of string);
    procedure FormShow(Sender: TObject);
    procedure MenuSeriesWinClick(Sender: TObject);
    procedure MenuBoxModeClick(Sender: TObject);
    procedure MenuChartPropsClick(Sender: TObject);
    procedure MenuZoomBackClick(Sender: TObject);
    procedure MenuSnapshotClick(Sender: TObject);
    procedure ListSeriesClickCheck(Sender: TObject);
    procedure ListSeriesDblClick(Sender: TObject);
    procedure ListSeriesDrawItem(Control: TWinControl; Index: Integer; ARect: TRect; State: TOwnerDrawState);
    procedure ListSeriesSelectionChange(Sender: TObject; User: Boolean);
    procedure MenuAboutClick(Sender: TObject);
    procedure MenuAddClick(Sender: TObject);
    procedure MenuAutoYClick(Sender: TObject);
    procedure MenuCopyClick(Sender: TObject);
    procedure MenuExitClick(Sender: TObject);
    procedure MenuFitClick(Sender: TObject);
    procedure MenuFitYClick(Sender: TObject);
    procedure MenuFolderClick(Sender: TObject);
    procedure MenuLanesClick(Sender: TObject);
    procedure MenuLiveClick(Sender: TObject);
    procedure MenuMouseClick(Sender: TObject);
    procedure MenuOpenClick(Sender: TObject);
    procedure MenuPngClick(Sender: TObject);
    procedure MenuPointsClick(Sender: TObject);
    procedure MenuReloadClick(Sender: TObject);
    procedure MenuZoomInClick(Sender: TObject);
    procedure MenuZoomOutClick(Sender: TObject);
    procedure TimerLiveTimer(Sender: TObject);
  private
    FData: TLogData;
    FChart: TLogChart;
    FLastDir: string;
    FBusy: Boolean;
    FProgressTick: QWord;
    FSeries: TSeriesForm;          // the series list window
    FLoad: TLoadingForm;           // shown while a big file is read
    FLoadPopup: Boolean;           // OpenFiles: a Loading window may be shown
    FStartFiles: array of string;  // from the command line, opened when the window is visible
    FSeriesShow: Boolean;
    FSeriesPlaced: Boolean;        // position from the ini
    procedure SeriesWinHide(Sender: TObject);
    procedure OpenStartFiles(Data: PtrInt);
    procedure SeriesPropsChanged(Sender: TObject);
    procedure ApplyChartOptions(const O: TChartOptions);
    function CurSeries: TLogSeries;
    procedure LoadSeriesProps;
    procedure SaveSeriesProps;    procedure OpenFiles(const Names: array of string; Replace: Boolean);
    procedure LoadProgress(Sender: TObject; Done, Total: Int64);
    procedure AssignColors;
    procedure FillSeriesList;
    procedure ChartViewChange(Sender: TObject);
    procedure ChartCursor(Sender: TObject);
    procedure UpdateStats;
    procedure UpdateStatus;
    procedure SyncChecks;
    function ChartBitmap: TBGRABitmap;
    function IniName: string;
    procedure LoadSettings;
    procedure SaveSettings;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

const
  { series colours ($BBGGRR) }
  Palette: array[0..11] of Cardinal = ($B4771F, $2827D6, $2CA02C, $0E7FFF, $BD6794, $4B568C,
    $C277E3, $CFBE17, $22BDBC, $7F7F7F, $00008B, $808000);

var
  UiFmt: TFormatSettings;

function Fmt(V: Double): string;
begin
  if IsNan(V) then Result := '---'
  else Result := FloatToStrF(V, ffGeneral, 7, 0, UiFmt);
end;

function SpanText(Days: Double): string;
var
  S: Double;
begin
  S := Days * 86400;
  if S < 1 then Result := Format('%.0f ms', [S * 1000], UiFmt)
  else if S < 120 then Result := Format('%.1f s', [S], UiFmt)
  else if S < 7200 then Result := Format('%.1f min', [S / 60], UiFmt)
  else if S < 172800 then Result := Format('%.1f h', [S / 3600], UiFmt)
  else Result := Format('%.1f days', [Days], UiFmt);
end;

{ TMainForm }

procedure TMainForm.FormCreate(Sender: TObject);
var
  I: Integer;
  L: array of string;
begin
  FData := TLogData.Create;
  FData.OnProgress := @LoadProgress;
  FChart := TLogChart.Create(Self);
  FChart.Parent := Self;
  FChart.Align := alClient;
  FChart.Data := FData;
  FChart.OnViewChange := @ChartViewChange;
  FChart.OnCursor := @ChartCursor;
  { series list: a window of its own, above the main window }
  FSeries := TSeriesForm.Create(Self);
  FSeries.PopupMode := pmExplicit;
  FSeries.PopupParent := Self;
  FSeries.ShortcutMenu := MainMenu1;
  FSeries.OnHide := @SeriesWinHide;
  FSeries.ListSeries.OnClickCheck := @ListSeriesClickCheck;
  FSeries.ListSeries.OnDblClick := @ListSeriesDblClick;
  FSeries.ListSeries.OnDrawItem := @ListSeriesDrawItem;
  FSeries.ListSeries.OnSelectionChange := @ListSeriesSelectionChange;
  FSeries.BtnShowAll.OnClick := @BtnShowAllClick;
  FSeries.BtnShowNone.OnClick := @BtnShowNoneClick;
  FSeries.OnChanged := @SeriesPropsChanged;
  MenuFit.ShortCut := ShortCut(VK_HOME, [ssCtrl]);
  MenuZoomIn.ShortCut := ShortCut(VK_ADD, [ssCtrl]);
  MenuZoomOut.ShortCut := ShortCut(VK_SUBTRACT, [ssCtrl]);
  LoadSettings;
  { files on the command line (e.g. a CSV dropped on LogChart.exe) }
  L := nil;
  for I := 1 to ParamCount do
    if FileExists(ParamStr(I)) then
    begin
      SetLength(L, Length(L) + 1);
      L[High(L)] := ParamStr(I);
    end;
  FStartFiles := L;                // opened in FormShow: the Loading window needs the main window
  UpdateStatus;
end;

{ the series window: first time left of the main window (or inside it on the right
  when the screen has no room), later where the user left it }
procedure TMainForm.FormShow(Sender: TObject);
var
  WA: TRect;
begin
  if not FSeriesPlaced then
  begin
    WA := Screen.WorkAreaRect;
    if Left - FSeries.Width - 4 >= WA.Left then
      FSeries.SetBounds(Left - FSeries.Width - 4, Top + 40, FSeries.Width, Min(FSeries.Height, Height - 40))
    else
      FSeries.SetBounds(Left + Width - FSeries.Width - 30, Top + 90, FSeries.Width,
        Min(FSeries.Height, Height - 140));
    FSeriesPlaced := True;
  end;
  MenuSeriesWin.Checked := FSeriesShow;
  if FSeriesShow then FSeries.Show;
  if Length(FStartFiles) > 0 then Application.QueueAsyncCall(@OpenStartFiles, 0);
end;

procedure TMainForm.OpenStartFiles(Data: PtrInt);
var
  L: array of string;
begin
  L := FStartFiles;
  FStartFiles := nil;
  OpenFiles(L, True);
end;

procedure TMainForm.MenuSeriesWinClick(Sender: TObject);
begin
  if FSeries.Visible then FSeries.Hide
  else
  begin
    FSeries.Show;
    FSeries.BringToFront;
  end;
  MenuSeriesWin.Checked := FSeries.Visible;
end;

procedure TMainForm.SeriesWinHide(Sender: TObject);
begin
  if not (csDestroying in ComponentState) then MenuSeriesWin.Checked := False;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  FData.Free;
end;

procedure TMainForm.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  TimerLive.Enabled := False;
  SaveSettings;
  SaveSeriesProps;
end;

{ ------------------------------ settings -------------------------------- }

function TMainForm.IniName: string;
begin
  Result := ChangeFileExt(ParamStr(0), '.ini');
end;

procedure TMainForm.LoadSettings;
var
  Ini: TIniFile;
  O: TChartOptions;
begin
  Ini := TIniFile.Create(IniName);
  try
    FLastDir := Ini.ReadString('App', 'LastDir', '');
    MenuLanes.Checked := Ini.ReadBool('View', 'Lanes', True);
    MenuFitY.Checked := Ini.ReadBool('View', 'FitY', False);
    MenuPoints.Checked := Ini.ReadBool('View', 'Points', False);
    FSeriesShow := Ini.ReadBool('SeriesWindow', 'Visible', True);
    FSeriesPlaced := Ini.ValueExists('SeriesWindow', 'Left');
    if FSeriesPlaced then
    begin
      if Ini.ReadInteger('SeriesWindow', 'Layout', 1) >= 2 then
        FSeries.SetBounds(Ini.ReadInteger('SeriesWindow', 'Left', 40), Ini.ReadInteger('SeriesWindow', 'Top', 60),
          Ini.ReadInteger('SeriesWindow', 'Width', 290), Ini.ReadInteger('SeriesWindow', 'Height', 640))
      else                       // older, smaller window: keep only the place
        FSeries.SetBounds(Ini.ReadInteger('SeriesWindow', 'Left', 40), Max(0, Ini.ReadInteger('SeriesWindow', 'Top', 60) - 100),
          FSeries.Width, Min(FSeries.Height, Screen.WorkAreaHeight - 20));
    end;
    O := DefaultChartOptions;
    O.BackColor := TColor(Ini.ReadInteger('Chart', 'BackColor', O.BackColor));
    O.PlotColor := TColor(Ini.ReadInteger('Chart', 'PlotColor', O.PlotColor));
    O.PlotColor2 := TColor(Ini.ReadInteger('Chart', 'PlotColor2', O.PlotColor2));
    O.GridColor := TColor(Ini.ReadInteger('Chart', 'GridColor', O.GridColor));
    O.AxisColor := TColor(Ini.ReadInteger('Chart', 'AxisColor', O.AxisColor));
    O.TextColor := TColor(Ini.ReadInteger('Chart', 'TextColor', O.TextColor));
    O.CursorColor := TColor(Ini.ReadInteger('Chart', 'CursorColor', O.CursorColor));
    O.BoxColor := TColor(Ini.ReadInteger('Chart', 'BoxColor', O.BoxColor));
    O.FontName := Ini.ReadString('Chart', 'FontName', O.FontName);
    O.AxisFont := Ini.ReadInteger('Chart', 'AxisFont', O.AxisFont);
    O.LabelFont := Ini.ReadInteger('Chart', 'LabelFont', O.LabelFont);
    O.GridX := Ini.ReadBool('Chart', 'GridX', O.GridX);
    O.GridY := Ini.ReadBool('Chart', 'GridY', O.GridY);
    O.TimeFormat := Ini.ReadInteger('Chart', 'TimeFormat', O.TimeFormat);
    O.ShowDate := Ini.ReadBool('Chart', 'ShowDate', O.ShowDate);
    O.LaneNames := Ini.ReadBool('Chart', 'LaneNames', O.LaneNames);
    O.LaneGap := Ini.ReadInteger('Chart', 'LaneGap', O.LaneGap);
    O.ShowReadout := Ini.ReadBool('Chart', 'ShowReadout', O.ShowReadout);
    O.Crosshair := Ini.ReadBool('Chart', 'Crosshair', O.Crosshair);
    { settings from before version 2 had 'left drag = move': the new default is the zoom box }
    if Ini.ReadInteger('Chart', 'Version', 1) >= 2 then
      O.LeftDrag := Ini.ReadInteger('Chart', 'LeftDrag', O.LeftDrag);
    O.StartRows := Ini.ReadInteger('Chart', 'StartRows', O.StartRows);
    O.WheelPercent := Ini.ReadInteger('Chart', 'WheelPercent', O.WheelPercent);
    O.LineWidth := Ini.ReadFloat('Chart', 'LineWidth', O.LineWidth);
    O.ShowGaps := Ini.ReadBool('Chart', 'ShowGaps', O.ShowGaps);
    O.LiveMs := Ini.ReadInteger('Chart', 'LiveMs', O.LiveMs);
    O.ExportW := Ini.ReadInteger('Chart', 'ExportW', O.ExportW);
    O.ExportH := Ini.ReadInteger('Chart', 'ExportH', O.ExportH);
    ApplyChartOptions(O);
  finally
    Ini.Free;
  end;
  { first start: the log folder of the data logger next to this program }
  if (FLastDir = '') or not DirectoryExists(FLastDir) then
  begin
    FLastDir := ExpandFileName(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'Logs');
    if not DirectoryExists(FLastDir) then FLastDir := ExtractFilePath(ParamStr(0));
  end;
  SyncChecks;
end;

procedure TMainForm.SaveSettings;
var
  Ini: TIniFile;
begin
  try
    Ini := TIniFile.Create(IniName);
    try
      Ini.WriteString('App', 'LastDir', FLastDir);
      Ini.WriteBool('View', 'Lanes', FChart.Lanes);
      Ini.WriteBool('View', 'FitY', FChart.FitY);
      Ini.WriteBool('View', 'Points', FChart.ShowPoints);
      Ini.WriteBool('SeriesWindow', 'Visible', MenuSeriesWin.Checked);
      Ini.WriteInteger('SeriesWindow', 'Left', FSeries.Left);
      Ini.WriteInteger('SeriesWindow', 'Top', FSeries.Top);
      Ini.WriteInteger('SeriesWindow', 'Width', FSeries.Width);
      Ini.WriteInteger('SeriesWindow', 'Height', FSeries.Height);
      Ini.WriteInteger('SeriesWindow', 'Layout', 2);
      with FChart.Options do
      begin
        Ini.WriteInteger('Chart', 'BackColor', BackColor);
        Ini.WriteInteger('Chart', 'PlotColor', PlotColor);
        Ini.WriteInteger('Chart', 'PlotColor2', PlotColor2);
        Ini.WriteInteger('Chart', 'GridColor', GridColor);
        Ini.WriteInteger('Chart', 'AxisColor', AxisColor);
        Ini.WriteInteger('Chart', 'TextColor', TextColor);
        Ini.WriteInteger('Chart', 'CursorColor', CursorColor);
        Ini.WriteInteger('Chart', 'BoxColor', BoxColor);
        Ini.WriteString('Chart', 'FontName', FontName);
        Ini.WriteInteger('Chart', 'AxisFont', AxisFont);
        Ini.WriteInteger('Chart', 'LabelFont', LabelFont);
        Ini.WriteBool('Chart', 'GridX', GridX);
        Ini.WriteBool('Chart', 'GridY', GridY);
        Ini.WriteInteger('Chart', 'TimeFormat', TimeFormat);
        Ini.WriteBool('Chart', 'ShowDate', ShowDate);
        Ini.WriteBool('Chart', 'LaneNames', LaneNames);
        Ini.WriteInteger('Chart', 'LaneGap', LaneGap);
        Ini.WriteBool('Chart', 'ShowReadout', ShowReadout);
        Ini.WriteBool('Chart', 'Crosshair', Crosshair);
        Ini.WriteInteger('Chart', 'Version', 2);
        Ini.WriteInteger('Chart', 'LeftDrag', LeftDrag);
        Ini.WriteInteger('Chart', 'StartRows', StartRows);
        Ini.WriteInteger('Chart', 'WheelPercent', WheelPercent);
        Ini.WriteFloat('Chart', 'LineWidth', LineWidth);
        Ini.WriteBool('Chart', 'ShowGaps', ShowGaps);
        Ini.WriteInteger('Chart', 'LiveMs', LiveMs);
        Ini.WriteInteger('Chart', 'ExportW', ExportW);
        Ini.WriteInteger('Chart', 'ExportH', ExportH);
      end;
    finally
      Ini.Free;
    end;
  except
    { read-only folder: settings are not kept }
  end;
end;

{ ------------------------------ files ----------------------------------- }

const
  POPUP_BYTES = 2 * 1024 * 1024;      // smaller loads: no Loading window (no flicker)

procedure TMainForm.LoadProgress(Sender: TObject; Done, Total: Int64);
begin
  { Loading window for big files (Open / Add / folder; not for the small live reads) }
  if FLoadPopup and (FLoad = nil) and (Total > POPUP_BYTES) then
  begin
    FLoad := TLoadingForm.Create(Self);
    FLoad.PopupMode := pmExplicit;
    FLoad.PopupParent := Self;
    FLoad.Start('Reading CSV files ...', 'Loading');
    FLoad.Show;
  end;
  if FLoad <> nil then
  begin
    FLoad.Progress(FData.CurrentFile, Done, Total, FData.Count, True);
    if FLoad.Cancelled then Abort;        // EAbort: OpenFiles keeps the rows read so far
    Exit;
  end;
  if GetTickCount64 - FProgressTick < 150 then Exit;
  FProgressTick := GetTickCount64;
  if Total > 0 then
    StatusBar1.Panels[0].Text := Format('Reading ... %d %%  (%d rows)', [Done * 100 div Total, FData.Count])
  else
    StatusBar1.Panels[0].Text := Format('Reading ... %d rows', [FData.Count]);
end;

procedure TMainForm.OpenFiles(const Names: array of string; Replace: Boolean);
var
  T0: QWord;
  Cancelled: Boolean;
begin
  if FBusy or (Length(Names) = 0) then Exit;
  FBusy := True;
  Screen.Cursor := crHourGlass;
  try
    T0 := GetTickCount64;
    if Replace then
    begin
      SaveSeriesProps;              // settings of these columns for the next time
      FChart.ForgetLayout;          // the old series objects are freed
      FSeries.ShowSeries(nil, FChart);
      FData.Clear;
    end;
    { while reading: the chart does not touch the data, the windows wait }
    FChart.Data := nil;
    Enabled := False;
    FSeries.Enabled := False;
    FLoadPopup := True;
    Cancelled := False;
    try
      try
        FData.LoadFiles(Names);
      except
        on E: EAbort do
        begin
          FData.SortByTime;                 // the rows read until Cancel
          Cancelled := True;
        end;
        on E: Exception do MessageDlg('Open', 'Cannot read the file:' + LineEnding + E.Message, mtError, [mbOK], 0);
      end;
    finally
      FLoadPopup := False;
      FreeAndNil(FLoad);
      FSeries.Enabled := True;
      Enabled := True;
      FChart.Data := FData;
    end;
    FLastDir := ExtractFilePath(Names[0]);
    AssignColors;
    LoadSeriesProps;
    FillSeriesList;
    FChart.ShowLastRows(FChart.Options.StartRows);   // the newest rows (Whole file: Ctrl+Home)
    StatusBar1.Panels[0].Text := '';
    UpdateStatus;
    StatusBar1.Hint := Format('read in %d ms', [GetTickCount64 - T0]);
    if Cancelled then
      StatusBar1.Panels[0].Text := Format('Loading cancelled: %d rows read', [FData.Count]);
  finally
    Screen.Cursor := crDefault;
    FBusy := False;
  end;
  FChart.Invalidate;
end;

procedure TMainForm.MenuOpenClick(Sender: TObject);
var
  L: array of string;
  I: Integer;
begin
  OpenDialog1.Title := 'Open CSV files of the data logger (several days: select several)';
  OpenDialog1.InitialDir := FLastDir;
  if not OpenDialog1.Execute then Exit;
  SetLength(L, OpenDialog1.Files.Count);
  for I := 0 to OpenDialog1.Files.Count - 1 do L[I] := OpenDialog1.Files[I];
  OpenFiles(L, True);
end;

procedure TMainForm.MenuAddClick(Sender: TObject);
var
  L: array of string;
  I: Integer;
begin
  OpenDialog1.Title := 'Add CSV files (e.g. the next days)';
  OpenDialog1.InitialDir := FLastDir;
  if not OpenDialog1.Execute then Exit;
  SetLength(L, OpenDialog1.Files.Count);
  for I := 0 to OpenDialog1.Files.Count - 1 do L[I] := OpenDialog1.Files[I];
  OpenFiles(L, False);
end;

procedure TMainForm.MenuFolderClick(Sender: TObject);
var
  SR: TSearchRec;
  L: array of string;
  D: string;
begin
  SelectDirectoryDialog1.Title := 'Folder of a month (mm-yyyy): all days in it';
  SelectDirectoryDialog1.InitialDir := FLastDir;
  if not SelectDirectoryDialog1.Execute then Exit;
  D := IncludeTrailingPathDelimiter(SelectDirectoryDialog1.FileName);
  L := nil;
  if FindFirst(D + '*.csv', faAnyFile, SR) = 0 then
  begin
    repeat
      SetLength(L, Length(L) + 1);
      L[High(L)] := D + SR.Name;
    until FindNext(SR) <> 0;
    FindClose(SR);
  end;
  if Length(L) = 0 then
    MessageDlg('Open folder', 'No CSV files in' + LineEnding + D, mtInformation, [mbOK], 0)
  else
    OpenFiles(L, True);
end;

procedure TMainForm.FormDropFiles(Sender: TObject; const FileNames: array of string);
begin
  OpenFiles(FileNames, True);
end;

procedure TMainForm.MenuReloadClick(Sender: TObject);
begin
  TimerLiveTimer(nil);
end;

{ new rows (live): if the view shows the end of the data, it keeps following the end }
procedure TMainForm.TimerLiveTimer(Sender: TObject);
var
  OldLast, Span: Double;
  Follow: Boolean;
  OldSeries: Integer;
begin
  if FBusy or (Length(FData.Files) = 0) then Exit;
  FBusy := True;
  try
    OldLast := FData.LastTime;
    OldSeries := Length(FData.Series);
    Follow := (FData.Count > 0) and (FChart.X1 >= OldLast);
    if not FData.LoadMore then Exit;
    if Length(FData.Series) <> OldSeries then
    begin
      AssignColors;
      LoadSeriesProps;
      FillSeriesList;
    end;
    if Follow then
    begin
      Span := FChart.X1 - FChart.X0;
      FChart.SetView(FData.LastTime - Span * 0.98, FData.LastTime + Span * 0.02);
    end
    else
      FChart.Invalidate;
    UpdateStatus;
    FSeries.ListSeries.Invalidate;
  finally
    FBusy := False;
  end;
end;

{ ------------------------------ series list ----------------------------- }

procedure TMainForm.AssignColors;
var
  I: Integer;
begin
  for I := 0 to High(FData.Series) do
    if FData.Series[I].Color = 0 then FData.Series[I].Color := Palette[I mod Length(Palette)];
end;

function SeriesSection(const S: TLogSeries): string;
begin
  Result := 'Series ' + StringReplace(StringReplace(S.Name, '[', '(', [rfReplaceAll]), ']', ')', [rfReplaceAll]);
end;

{ display properties saved for this column name (earlier days / earlier runs) }
procedure TMainForm.LoadSeriesProps;
var
  Ini: TIniFile;
  I: Integer;
  S: TLogSeries;
  Sec: string;
begin
  Ini := TIniFile.Create(IniName);
  try
    for I := 0 to High(FData.Series) do
    begin
      S := FData.Series[I];
      if S.PropsLoaded then Continue;
      S.PropsLoaded := True;
      Sec := SeriesSection(S);
      if not Ini.SectionExists(Sec) then Continue;
      S.Title := Ini.ReadString(Sec, 'Title', S.Title);
      S.Color := Cardinal(Ini.ReadInteger(Sec, 'Color', S.Color));
      S.Visible := Ini.ReadBool(Sec, 'Visible', S.Visible);
      S.LineWidth := Ini.ReadFloat(Sec, 'LineWidth', S.LineWidth);
      S.LineStyle := Ini.ReadInteger(Sec, 'LineStyle', S.LineStyle);
      S.DrawMode := Ini.ReadInteger(Sec, 'DrawMode', S.DrawMode);
      S.PointMode := Ini.ReadInteger(Sec, 'PointMode', S.PointMode);
      S.PointSize := Ini.ReadFloat(Sec, 'PointSize', S.PointSize);
      S.Gain := Ini.ReadFloat(Sec, 'Gain', S.Gain);
      if S.Gain = 0 then S.Gain := 1;
      S.Offset := Ini.ReadFloat(Sec, 'Offset', S.Offset);
      S.UnitText := Ini.ReadString(Sec, 'Unit', S.UnitText);
    end;
  finally
    Ini.Free;
  end;
end;

procedure TMainForm.SaveSeriesProps;
var
  Ini: TIniFile;
  I: Integer;
  S: TLogSeries;
  Sec: string;
begin
  try
    Ini := TIniFile.Create(IniName);
    try
      for I := 0 to High(FData.Series) do
      begin
        S := FData.Series[I];
        if not S.Numeric then Continue;
        Sec := SeriesSection(S);
        Ini.WriteString(Sec, 'Title', S.Title);
        Ini.WriteInteger(Sec, 'Color', Integer(S.Color));
        Ini.WriteBool(Sec, 'Visible', S.Visible);
        Ini.WriteFloat(Sec, 'LineWidth', S.LineWidth);
        Ini.WriteInteger(Sec, 'LineStyle', S.LineStyle);
        Ini.WriteInteger(Sec, 'DrawMode', S.DrawMode);
        Ini.WriteInteger(Sec, 'PointMode', S.PointMode);
        Ini.WriteFloat(Sec, 'PointSize', S.PointSize);
        Ini.WriteFloat(Sec, 'Gain', S.Gain);
        Ini.WriteFloat(Sec, 'Offset', S.Offset);
        Ini.WriteString(Sec, 'Unit', S.UnitText);
      end;
    finally
      Ini.Free;
    end;
  except
    { read-only folder }
  end;
end;

function TMainForm.CurSeries: TLogSeries;
var
  K: Integer;
begin
  K := FSeries.ListSeries.ItemIndex;
  if (K < 0) or (K > High(FData.Series)) then Result := nil else Result := FData.Series[K];
end;

{ a property was changed in the series window }
procedure TMainForm.SeriesPropsChanged(Sender: TObject);
var
  I: Integer;
begin
  for I := 0 to Min(FSeries.ListSeries.Count, Length(FData.Series)) - 1 do
    FSeries.ListSeries.Checked[I] := FData.Series[I].Visible and FData.Series[I].Numeric;
  FSeries.ListSeries.Invalidate;
  FChart.Invalidate;
  UpdateStats;
end;

procedure TMainForm.FillSeriesList;
var
  I: Integer;
begin
  FSeries.ListSeries.Items.BeginUpdate;
  try
    FSeries.ListSeries.Items.Clear;
    for I := 0 to High(FData.Series) do
    begin
      FSeries.ListSeries.Items.Add(FData.Series[I].Name);
      FSeries.ListSeries.Checked[I] := FData.Series[I].Visible and FData.Series[I].Numeric;
      FSeries.ListSeries.ItemEnabled[I] := FData.Series[I].Numeric;
    end;
  finally
    FSeries.ListSeries.Items.EndUpdate;
  end;
  if FSeries.ListSeries.Count > 0 then FSeries.ListSeries.ItemIndex := 0;
  FSeries.ShowSeries(CurSeries, FChart);
  UpdateStats;
end;

procedure TMainForm.ListSeriesDrawItem(Control: TWinControl; Index: Integer; ARect: TRect;
  State: TOwnerDrawState);
var
  C: TCanvas;
  S: TLogSeries;
  Info, ShownName: string;
  R: TRect;
  Avail: Integer;
  Box: TThemedButton;
  Lo, Hi: Double;
begin
  C := FSeries.ListSeries.Canvas;
  if (Index < 0) or (Index > High(FData.Series)) then Exit;
  S := FData.Series[Index];
  if odSelected in State then C.Brush.Color := clHighlight else C.Brush.Color := clWindow;
  C.FillRect(ARect);
  { check box: in owner-draw mode the LCL does not draw it, but a click on the
    left square (item height wide) still ticks it }
  R := Rect(ARect.Left + 2, ARect.Top + 2, ARect.Left + ARect.Bottom - ARect.Top - 2, ARect.Bottom - 2);
  if not S.Numeric then Box := tbCheckBoxUncheckedDisabled
  else if FSeries.ListSeries.Checked[Index] then Box := tbCheckBoxCheckedNormal
  else Box := tbCheckBoxUncheckedNormal;
  C.Brush.Color := clWindow;
  C.FillRect(R);
  ThemeServices.DrawElement(C.Handle, ThemeServices.GetElementDetails(Box), R);
  if odSelected in State then C.Brush.Color := clHighlight else C.Brush.Color := clWindow;
  Inc(ARect.Left, ARect.Bottom - ARect.Top + 2);
  R := Rect(ARect.Left + 2, ARect.Top + 4, ARect.Left + 14, ARect.Bottom - 4);
  if S.Numeric then
  begin
    C.Brush.Color := TColor(S.Color);
    C.Pen.Color := clGray;
    C.Rectangle(R);
  end;
  C.Brush.Style := bsClear;
  if odSelected in State then C.Font.Color := clHighlightText
  else if S.Numeric then C.Font.Color := clWindowText
  else C.Font.Color := clGrayText;
  if not S.Numeric then Info := '(text)'
  else if S.IsBool and (S.Gain = 1) and (S.Offset = 0) then Info := 'BOOL'
  else
  begin
    S.ScaledMinMax(Lo, Hi);            // shown values (gain / offset) and unit
    Info := Fmt(Lo) + '..' + Fmt(Hi);
    if S.UnitText <> '' then Info := Info + ' ' + S.UnitText;
  end;
  { long names: shortened with ... so the range stays readable (full name in the chart) }
  ShownName := S.Caption;
  Avail := ARect.Right - ARect.Left - 20 - C.TextWidth(Info) - 12;
  if C.TextWidth(ShownName) > Avail then
  begin
    while (Length(ShownName) > 1) and (C.TextWidth(ShownName + '...') > Avail) do SetLength(ShownName, Length(ShownName) - 1);
    ShownName := ShownName + '...';
  end;
  C.TextOut(ARect.Left + 20, ARect.Top + 2, ShownName);
  if not (odSelected in State) then C.Font.Color := clGrayText;
  C.TextOut(ARect.Right - C.TextWidth(Info) - 4, ARect.Top + 2, Info);
  C.Brush.Style := bsSolid;
end;

procedure TMainForm.ListSeriesClickCheck(Sender: TObject);
var
  I: Integer;
begin
  for I := 0 to Min(FSeries.ListSeries.Count, Length(FData.Series)) - 1 do
    FData.Series[I].Visible := FSeries.ListSeries.Checked[I];
  FSeries.ListSeries.Invalidate;            // the check boxes are drawn by us
  FSeries.ShowSeries(CurSeries, FChart);
  FChart.Invalidate;
end;

{ double-click on the NAME: only this series. On the check box the double-click is only
  a click (the LCL ticks the box on button down and on double-click: our "only this one"
  came between the two and in the end every box was empty) }
procedure TMainForm.ListSeriesDblClick(Sender: TObject);
var
  I: Integer;
  P: TPoint;
begin
  if FSeries.ListSeries.ItemIndex < 0 then Exit;
  P := FSeries.ListSeries.ScreenToClient(Mouse.CursorPos);
  if P.X < FSeries.ListSeries.ItemHeight + 2 then
  begin
    { the box was ticked twice by the double-click: count it as one click }
    I := FSeries.ListSeries.ItemIndex;       // the row of the click (the list may have scrolled)
    if (I >= 0) and FData.Series[I].Numeric then
      FSeries.ListSeries.Checked[I] := not FSeries.ListSeries.Checked[I];
    ListSeriesClickCheck(nil);
    Exit;
  end;
  for I := 0 to FSeries.ListSeries.Count - 1 do
    FSeries.ListSeries.Checked[I] := (I = FSeries.ListSeries.ItemIndex) and FData.Series[I].Numeric;
  ListSeriesClickCheck(nil);
end;

procedure TMainForm.ListSeriesSelectionChange(Sender: TObject; User: Boolean);
begin
  FSeries.ShowSeries(CurSeries, FChart);
  UpdateStats;
end;

procedure TMainForm.BtnShowAllClick(Sender: TObject);
var
  I: Integer;
begin
  for I := 0 to FSeries.ListSeries.Count - 1 do FSeries.ListSeries.Checked[I] := FData.Series[I].Numeric;
  ListSeriesClickCheck(nil);
end;

procedure TMainForm.BtnShowNoneClick(Sender: TObject);
var
  I: Integer;
begin
  for I := 0 to FSeries.ListSeries.Count - 1 do FSeries.ListSeries.Checked[I] := False;
  ListSeriesClickCheck(nil);
end;

{ statistics of the selected series in the visible time range (shown values: gain / offset) }
procedure TMainForm.UpdateStats;
var
  S: TLogSeries;
  I, I0, I1, N, IFirst, ILast, IMin, IMax: Integer;
  V, Lo, Hi, Sum, Sum2, Sd: Double;
  U: string;

  function TimeOf(K: Integer): string;
  begin
    Result := FormatDateTime('hh:nn:ss.zzz', FData.Times[K], UiFmt);
  end;

begin
  S := CurSeries;
  if (S = nil) or (FData.Count = 0) then
  begin
    FSeries.LabelStats.Caption := '-';
    Exit;
  end;
  I0 := FData.IndexAtOrAfter(FChart.X0);
  I1 := Min(FData.Count - 1, FData.IndexAtOrAfter(FChart.X1) - 1);
  N := 0;
  Lo := NaN;
  Hi := NaN;
  Sum := 0;
  Sum2 := 0;
  IFirst := -1;
  ILast := -1;
  IMin := -1;
  IMax := -1;
  for I := I0 to I1 do
  begin
    if IsNan(S.Values[I]) then Continue;
    V := S.Scaled(S.Values[I]);
    Inc(N);
    Sum := Sum + V;
    Sum2 := Sum2 + V * V;
    if IFirst < 0 then IFirst := I;
    ILast := I;
    if IsNan(Lo) or (V < Lo) then
    begin
      Lo := V;
      IMin := I;
    end;
    if IsNan(Hi) or (V > Hi) then
    begin
      Hi := V;
      IMax := I;
    end;
  end;
  U := '';
  if S.UnitText <> '' then U := ' ' + S.UnitText;
  if N = 0 then
    FSeries.LabelStats.Caption := S.Caption + LineEnding + LineEnding + 'no values in this range'
  else
  begin
    Sd := Sqrt(Max(0, Sum2 / N - Sqr(Sum / N)));
    FSeries.LabelStats.Caption := S.Caption + LineEnding + LineEnding +
      Format('min      %s%s', [Fmt(Lo), U]) + LineEnding +
      Format('         at %s', [TimeOf(IMin)]) + LineEnding +
      Format('max      %s%s', [Fmt(Hi), U]) + LineEnding +
      Format('         at %s', [TimeOf(IMax)]) + LineEnding +
      Format('average  %s%s', [Fmt(Sum / N), U]) + LineEnding +
      Format('std.dev. %s%s', [Fmt(Sd), U]) + LineEnding +
      Format('span     %s%s', [Fmt(Hi - Lo), U]) + LineEnding +
      Format('first    %s%s', [Fmt(S.Scaled(S.Values[IFirst])), U]) + LineEnding +
      Format('         at %s', [TimeOf(IFirst)]) + LineEnding +
      Format('last     %s%s', [Fmt(S.Scaled(S.Values[ILast])), U]) + LineEnding +
      Format('         at %s', [TimeOf(ILast)]) + LineEnding +
      Format('values   %d of %d rows', [N, Max(0, I1 - I0 + 1)]) + LineEnding + LineEnding +
      Format('from %s', [FormatDateTime('dd-mm-yyyy hh:nn:ss.zzz', FChart.X0, UiFmt)]) + LineEnding +
      Format('to   %s', [FormatDateTime('dd-mm-yyyy hh:nn:ss.zzz', FChart.X1, UiFmt)]);
  end;
end;
{ ------------------------------ chart ----------------------------------- }

procedure TMainForm.ChartViewChange(Sender: TObject);
begin
  UpdateStats;
  UpdateStatus;
  FSeries.RefreshRange;
end;

procedure TMainForm.ChartCursor(Sender: TObject);
var
  K: Integer;
begin
  K := FChart.CursorIndex;
  if (K < 0) or (K >= FData.Count) then
    StatusBar1.Panels[2].Text := ''
  else
    StatusBar1.Panels[2].Text := Format('row %d   %s', [K + 1,
      FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', FData.Times[K], UiFmt)]);
end;

procedure TMainForm.UpdateStatus;
var
  S: string;
  I: Integer;
begin
  if Length(FData.Files) = 0 then
  begin
    Caption := 'LogChart - charts of the PLC Data Logger CSV files';
    StatusBar1.Panels[0].Text := 'No file';
    StatusBar1.Panels[1].Text := '';
    Exit;
  end;
  S := '';
  for I := 0 to High(FData.Files) do
  begin
    if I > 0 then S := S + ', ';
    if I >= 3 then
    begin
      S := S + Format('... (%d files)', [Length(FData.Files)]);
      Break;
    end;
    S := S + ExtractFileName(FData.Files[I].FileName);
  end;
  Caption := 'LogChart - ' + S;
  StatusBar1.Panels[0].Text := S;
  if FData.Count = 0 then
    StatusBar1.Panels[1].Text := 'no rows'
  else
    StatusBar1.Panels[1].Text := Format('%d rows   %s .. %s   view %s', [FData.Count,
      FormatDateTime('dd-mm hh:nn:ss', FData.FirstTime, UiFmt),
      FormatDateTime('dd-mm hh:nn:ss', FData.LastTime, UiFmt), SpanText(FChart.X1 - FChart.X0)]);
end;

procedure TMainForm.MenuFitClick(Sender: TObject);
begin
  FChart.PushView;
  FChart.FitAll;
end;

procedure TMainForm.MenuAutoYClick(Sender: TObject);
begin
  FChart.PushView;
  FChart.ResetY;
  FSeries.RefreshRange;
end;

procedure TMainForm.MenuZoomInClick(Sender: TObject);
begin
  FChart.PushView;
  FChart.ZoomBy(0.5);
end;

procedure TMainForm.MenuZoomOutClick(Sender: TObject);
begin
  FChart.PushView;
  FChart.ZoomBy(2);
end;

procedure TMainForm.MenuZoomBackClick(Sender: TObject);
begin
  if not FChart.ZoomBack then StatusBar1.Panels[0].Text := 'No earlier zoom';
  FSeries.RefreshRange;
end;

procedure TMainForm.MenuBoxModeClick(Sender: TObject);
var
  O: TChartOptions;
begin
  O := FChart.Options;
  if O.LeftDrag = 1 then O.LeftDrag := 0 else O.LeftDrag := 1;
  ApplyChartOptions(O);
end;

procedure TMainForm.ApplyChartOptions(const O: TChartOptions);
begin
  FChart.Options := O;
  TimerLive.Interval := Max(200, O.LiveMs);
  MenuBoxMode.Checked := O.LeftDrag = 1;
end;

procedure TMainForm.MenuChartPropsClick(Sender: TObject);
var
  O, Before: TChartOptions;
begin
  Before := FChart.Options;
  O := Before;
  if TChartPropsForm.Execute(Self, O, @ApplyChartOptions) then
  begin
    ApplyChartOptions(O);
    SaveSettings;
  end
  else
    ApplyChartOptions(Before);       // Cancel: also undo what Apply showed
end;

{ menu items and check boxes show the same switches }
{ the switches are the ticks of the View menu }
procedure TMainForm.SyncChecks;
begin
  if FChart = nil then Exit;
  FChart.Lanes := MenuLanes.Checked;
  FChart.FitY := MenuFitY.Checked;
  FChart.ShowPoints := MenuPoints.Checked;
  TimerLive.Enabled := MenuLive.Checked;
end;

procedure TMainForm.MenuLanesClick(Sender: TObject);
begin
  MenuLanes.Checked := not MenuLanes.Checked;
  SyncChecks;
end;

procedure TMainForm.MenuFitYClick(Sender: TObject);
begin
  MenuFitY.Checked := not MenuFitY.Checked;
  SyncChecks;
end;

procedure TMainForm.MenuPointsClick(Sender: TObject);
begin
  MenuPoints.Checked := not MenuPoints.Checked;
  SyncChecks;
end;

procedure TMainForm.MenuLiveClick(Sender: TObject);
begin
  MenuLive.Checked := not MenuLive.Checked;
  SyncChecks;
  if MenuLive.Checked then TimerLiveTimer(nil);
  UpdateStatus;
end;

{ ------------------------------ picture --------------------------------- }

function TMainForm.ChartBitmap: TBGRABitmap;
begin
  if (FChart.Options.ExportW > 0) and (FChart.Options.ExportH > 0) then
    Result := TBGRABitmap.Create(Max(200, FChart.Options.ExportW), Max(150, FChart.Options.ExportH))
  else
    Result := TBGRABitmap.Create(Max(200, FChart.ClientWidth), Max(150, FChart.ClientHeight));
  FChart.RenderTo(Result, False);
end;

function CsvQ(const S: string): string;
begin
  if (Pos(',', S) > 0) or (Pos('"', S) > 0) then
    Result := '"' + StringReplace(S, '"', '""', [rfReplaceAll]) + '"'
  else
    Result := S;
end;

{ the visible time range of the shown series as a new CSV file (logger format: LogChart
  can open it again). Display names, units and gain / offset as in the chart. }
procedure TMainForm.MenuSnapshotClick(Sender: TObject);
const
  FLUSH_BYTES = 1 shl 20;
var
  Ser: array of TLogSeries;
  I, K, I0, I1, N, P: Integer;
  Buf, H, Line: string;
  F: TFileStream;
  W: TLoadingForm;
  Cancelled: Boolean;

  procedure Flush;
  begin
    if P > 1 then F.WriteBuffer(Buf[1], P - 1);
    P := 1;
  end;

  { fixed 1 MB buffer: no string that grows (S := S + ... copied it for every row) }
  procedure Put(const X: string);
  begin
    if X = '' then Exit;
    if P + Length(X) > Length(Buf) then Flush;
    Move(X[1], Buf[P], Length(X));
    Inc(P, Length(X));
  end;

begin
  if FData.Count = 0 then Exit;
  Ser := nil;
  for I := 0 to High(FData.Series) do
    if FData.Series[I].Visible and FData.Series[I].Numeric then
    begin
      SetLength(Ser, Length(Ser) + 1);
      Ser[High(Ser)] := FData.Series[I];
    end;
  I0 := FData.IndexAtOrAfter(FChart.X0);
  I1 := Min(FData.Count - 1, FData.IndexAtOrAfter(FChart.X1) - 1);
  N := I1 - I0 + 1;
  if (Length(Ser) = 0) or (N <= 0) then
  begin
    MessageDlg('Snapshot', 'Nothing to save: no series shown or no rows in the visible range.',
      mtInformation, [mbOK], 0);
    Exit;
  end;
  SaveCsvDialog.InitialDir := FLastDir;
  SaveCsvDialog.FileName := ChangeFileExt(ExtractFileName(FData.Files[0].FileName), '') + '_snapshot_' +
    FormatDateTime('hh"-"nn"-"ss', FData.Times[I0]) + '.csv';
  if not SaveCsvDialog.Execute then Exit;
  W := nil;
  Cancelled := False;
  Screen.Cursor := crHourGlass;
  F := TFileStream.Create(SaveCsvDialog.FileName, fmCreate);
  SetLength(Buf, FLUSH_BYTES + 4096);
  P := 1;
  try
    if N > 50000 then
    begin
      W := TLoadingForm.Create(Self);
      W.PopupMode := pmExplicit;
      W.PopupParent := Self;
      W.Start('Saving snapshot ...', 'Snapshot to CSV');
      W.Show;
      Enabled := False;
    end;
    { header like the logger: Date,Time,Status,<name [unit]> ... }
    H := 'Date,Time,Status';
    for K := 0 to High(Ser) do
      if Ser[K].UnitText <> '' then H := H + ',' + CsvQ(Ser[K].Caption + ' [' + Ser[K].UnitText + ']')
      else H := H + ',' + CsvQ(Ser[K].Caption);
    Put(H + #13#10);
    for I := I0 to I1 do
    begin
      Line := FormatDateTime('yyyy"-"mm"-"dd","hh":"nn":"ss"."zzz', FData.Times[I], UiFmt);
      case FData.Status[I] of
        rsOk: Line := Line + ',OK';
        rsTagError: Line := Line + ',TAG ERROR';
        rsNoConnection: Line := Line + ',NO CONNECTION';
      else
        Line := Line + ',';
      end;
      for K := 0 to High(Ser) do
        if IsNan(Ser[K].Values[I]) then Line := Line + ','
        else Line := Line + ',' + FloatToStrF(Ser[K].Scaled(Ser[K].Values[I]), ffGeneral, 7, 0, UiFmt);   // 7: values are Single
      Put(Line);
      Put(#13#10);
      if (W <> nil) and ((I - I0) and $3FFF = 0) then
      begin
        begin
          W.Progress(SaveCsvDialog.FileName, I - I0 + 1, N, I - I0 + 1, False);
          if W.Cancelled then
          begin
            Cancelled := True;
            Break;
          end;
        end;
      end;
    end;
    Flush;
  finally
    F.Free;
    FreeAndNil(W);
    Enabled := True;
    Screen.Cursor := crDefault;
  end;
  if Cancelled then
    StatusBar1.Panels[0].Text := 'Snapshot cancelled (file is incomplete)'
  else
    StatusBar1.Panels[0].Text := Format('Snapshot: %d rows, %d series -> %s',
      [N, Length(Ser), ExtractFileName(SaveCsvDialog.FileName)]);
end;

procedure TMainForm.MenuPngClick(Sender: TObject);
var
  B: TBGRABitmap;
begin
  SavePngDialog.InitialDir := FLastDir;
  if Length(FData.Files) > 0 then
    SavePngDialog.FileName := ChangeFileExt(ExtractFileName(FData.Files[0].FileName), '') + '_chart.png'
  else
    SavePngDialog.FileName := 'chart.png';
  if not SavePngDialog.Execute then Exit;
  B := ChartBitmap;
  try
    B.SaveToFile(SavePngDialog.FileName);
  finally
    B.Free;
  end;
  StatusBar1.Panels[0].Text := 'Saved ' + ExtractFileName(SavePngDialog.FileName);
end;

procedure TMainForm.MenuCopyClick(Sender: TObject);
var
  B: TBGRABitmap;
begin
  B := ChartBitmap;
  try
    Clipboard.Assign(B.Bitmap);
  finally
    B.Free;
  end;
  StatusBar1.Panels[0].Text := 'Chart copied (paste it into Word, Excel, Paint ...)';
end;

{ ------------------------------ help ------------------------------------ }

procedure TMainForm.MenuMouseClick(Sender: TObject);
begin
  MessageDlg('Mouse and keys',
    'Mouse wheel            zoom the time axis (around the mouse)' + LineEnding +
    'Left drag              zoom box: time and Y axes to the frame (only in the plot)' + LineEnding +
    'Right drag / Shift+left  move along the time axis (in the plot)' + LineEnding +
    'On the time axis       left or right drag moves the time' + LineEnding +
    '(View > Left drag = zoom box, Ctrl+B: switch the two)' + LineEnding +
    'Ctrl+Z / Backspace     zoom back' + LineEnding +
    'Double-click           whole file, all Y axes automatic' + LineEnding +
    'After opening: the last 1000 rows (Chart properties > Data & export)' + LineEnding + LineEnding +
    'On a Y axis (the axis turns light in the series colour):' + LineEnding +
    '  drag up / down       move this series (offset)' + LineEnding +
    '  mouse wheel          zoom this series only' + LineEnding +
    '  double-click         this axis automatic again' + LineEnding +
    'Lanes off: one plot, every series with its own Y axis (left, right, left ...)' + LineEnding + LineEnding +
    'Move the mouse         time and values of the nearest row' + LineEnding + LineEnding +
    'Chart focused:  Home = whole file,  + / - = zoom,  Left / Right = move' + LineEnding +
    'Ctrl+O open,  F5 reload,  F6 live,  Ctrl+L lanes,  Ctrl+Y Y fit,  Ctrl+R auto Y,  Ctrl+P points,' + LineEnding +
    'Ctrl+E export PNG,  Ctrl+Shift+C copy chart' + LineEnding + LineEnding +
    'Series list: tick = show, double-click = only this one.' + LineEnding +
    'Red marks on the time axis = rows with NO CONNECTION.',
    mtInformation, [mbOK], 0);
end;

procedure TMainForm.MenuAboutClick(Sender: TObject);
begin
  MessageDlg('About', 'LogChart' + LineEnding +
    'Charts of the CSV files of the PLC Data Logger' + LineEnding +
    '(<folder>\mm-yyyy\dd-mm-yyyy.csv), drawn with BGRABitmap.', mtInformation, [mbOK], 0);
end;

procedure TMainForm.MenuExitClick(Sender: TObject);
begin
  Close;
end;

initialization
  UiFmt := DefaultFormatSettings;
  UiFmt.DecimalSeparator := '.';
  UiFmt.ThousandSeparator := ',';
end.
