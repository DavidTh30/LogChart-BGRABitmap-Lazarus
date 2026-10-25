{ ============================================================================
  uchart - chart of the logger data, drawn with BGRABitmap (antialiased)
    - time axis with "nice" ticks (1 ms ... 1 month), date line under the times
    - Lanes: every series in its own strip with its own scale (default)
      Overlay: all series in one plot, every series with its OWN Y axis (all on the left,
               each only as wide as its numbers)
    - Y axis of a series: drag = move (offset), wheel = zoom, double-click = automatic again
    - big files: per pixel column only min / max are drawn (fast with millions of rows)
    - gaps: empty cells / NO CONNECTION rows (red marks on the time axis)
    - mouse: wheel = zoom time, left drag = zoom box (time + Y; only in the plot, kept inside it),
      right drag / Shift+left = move (in the plot); on the time axis left or right drag moves,
      double-click = whole file, Backspace = zoom back; the cursor shows all values of the nearest row
    - everything adjustable: TChartOptions (Chart Properties window), per series: TLogSeries
    - the chart is drawn once into a cache; moving the mouse only draws the cursor on top
  ============================================================================ }
unit uchart;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, Math, Types, LCLType,
  BGRABitmap, BGRABitmapTypes, ucsvdata;

type
  TDragMode = (dmNone, dmPan, dmZoom, dmAxis);

  { look and behaviour of the chart (Chart Properties window, LogChart.ini [Chart]) }
  TChartOptions = record
    BackColor, PlotColor, PlotColor2, GridColor, AxisColor, TextColor, CursorColor, BoxColor: TColor;
    FontName: string;
    AxisFont: Integer;          // pixel height of the axis numbers (time + Y)
    LabelFont: Integer;         // lane names, value box, messages
    GridX, GridY: Boolean;
    TimeFormat: Integer;        // 0 auto, 1 hh:nn, 2 hh:nn:ss, 3 hh:nn:ss.zzz, 4 dd-mm hh:nn
    ShowDate: Boolean;          // date line under the times
    LaneNames: Boolean;
    LaneGap: Integer;           // pixels between two lanes
    ShowReadout: Boolean;       // value box at the cursor
    Crosshair: Boolean;         // horizontal cursor line too
    LeftDrag: Integer;          // 1 = zoom box (right drag moves), 0 = move the time (right drag = zoom box)
    StartRows: Integer;         // after loading: show the last ... rows (0 = whole file)
    WheelPercent: Integer;      // zoom step of the mouse wheel
    LineWidth: Single;          // width of the lines (series with width 0)
    ShowGaps: Boolean;          // red marks for NO CONNECTION
    LiveMs: Integer;            // Live: read new rows every ... ms
    ExportW, ExportH: Integer;  // PNG / copy size, 0 = size of the window
  end;

  { one step of the zoom history }
  TViewState = record
    X0, X1: Double;
    Ser: array of TLogSeries;
    Man: array of Boolean;
    Lo, Hi: array of Double;
  end;

  { TLogChart }

  TLogChart = class(TCustomControl)
  private
    FData: TLogData;
    FOpt: TChartOptions;
    FX0, FX1: Double;            // visible time range (TDateTime)
    FLanes: Boolean;
    FFitY: Boolean;              // Y scale from the visible part only
    FShowPoints: Boolean;
    FMouse: TPoint;
    FMouseIn: Boolean;
    FDrag: TDragMode;
    FDragStart: TPoint;
    FDragX0, FDragX1: Double;
    FCursorIndex: Integer;
    { layout of the last drawing (for the mouse) }
    FPlotR: TRect;
    FLaySer: array of TLogSeries;     // visible series in drawing order
    FAxisR: array of TRect;           // Y axis area of each series
    FSerR: array of TRect;            // area the series is drawn in (lane or plot)
    FRanges: array of TPointF;        // Y range of each series (X = low, Y = high)
    FHoverAxis: Integer;
    FDragAxis: Integer;
    FAxisLo0, FAxisHi0: Double;
    FHist: array of TViewState;
    FCache: TBGRABitmap;              // the chart without cursor
    FDirty: Boolean;                  // the cache must be drawn again
    { colours of FOpt as BGRA }
    CBack, CPlot, CPlot2, CGrid, CAxis, CText, CTextDim, CCursor, CBox, CGap: TBGRAPixel;
    FOnViewChange: TNotifyEvent;
    FOnCursor: TNotifyEvent;
    function VisibleSeries: TList;
    procedure SeriesRange(S: TLogSeries; out Lo, Hi: Double);
    procedure DrawSeries(B: TBGRABitmap; S: TLogSeries; const R: TRect; Lo, Hi: Double);
    procedure DrawLaneAxis(B: TBGRABitmap; const LR: TRect; Lo, Hi: Double; S: TLogSeries);
    procedure DrawSideAxis(B: TBGRABitmap; const AR, R: TRect; Lo, Hi: Double; S: TLogSeries;
      Grid, Hover: Boolean);
    procedure DrawTimeAxis(B: TBGRABitmap; const R: TRect);
    procedure DrawGaps(B: TBGRABitmap; const R: TRect);
    procedure DrawCursor(B: TBGRABitmap; const R: TRect);
    function AxisAt(X, Y: Integer): Integer;
    function InPlot(X, Y: Integer): Boolean;
    function OnTimeAxis(X, Y: Integer): Boolean;
    function BoxRect: TRect;
    function TimeAtX(X: Integer): Double;
    function AxisWidth(B: TBGRABitmap; S: TLogSeries; Lo, Hi: Double; H: Integer): Integer;
    procedure SetLanes(AValue: Boolean);
    procedure SetFitY(AValue: Boolean);
    procedure SetShowPoints(AValue: Boolean);
    procedure SetOptions(const AValue: TChartOptions);
    procedure RenderBase(B: TBGRABitmap);
    procedure DrawOverlay(B: TBGRABitmap);
    procedure RepaintCursor;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
    procedure DblClick; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { something changed: draw the chart again (not only the cursor) }
    procedure Invalidate; override;
    { draw the whole chart into B (also for PNG export / copy) }
    procedure RenderTo(B: TBGRABitmap; WithCursor: Boolean);
    procedure FitAll;
    { the last N rows (N <= 0 or fewer rows: the whole file) }
    procedure ShowLastRows(N: Integer);
    procedure SetView(A, B: Double);
    procedure ZoomBy(Factor: Double);          // < 1 = zoom in, around the middle
    procedure PanBy(Fraction: Double);         // part of the visible span
    procedure ResetY;                          // all Y axes automatic again
    procedure ForgetLayout;                    // call when the data is cleared
    procedure PushView;                        // remember the view (zoom back)
    function ZoomBack: Boolean;
    function CanZoomBack: Boolean;
    { Y range the series has in the last drawing (False = not visible) }
    function CurrentRange(S: TLogSeries; out Lo, Hi: Double): Boolean;
    property Data: TLogData read FData write FData;
    property Options: TChartOptions read FOpt write SetOptions;
    property X0: Double read FX0;
    property X1: Double read FX1;
    property Lanes: Boolean read FLanes write SetLanes;
    property FitY: Boolean read FFitY write SetFitY;
    property ShowPoints: Boolean read FShowPoints write SetShowPoints;
    property CursorIndex: Integer read FCursorIndex;   // row under the mouse (-1 = none)
    property OnViewChange: TNotifyEvent read FOnViewChange write FOnViewChange;
    property OnCursor: TNotifyEvent read FOnCursor write FOnCursor;
  end;

function DefaultChartOptions: TChartOptions;
function DarkChartOptions: TChartOptions;
function SeriesPixel(const S: TLogSeries): TBGRAPixel;
function FormatLogValue(const S: TLogSeries; V: Double): string;

var
  ChartFmt: TFormatSettings;

implementation

const
  MS_PER_DAY = 86400000.0;
  MIN_SPAN = 5 / MS_PER_DAY;       // 5 ms
  MAX_HIST = 50;
  { "nice" time steps in ms }
  TimeSteps: array[0..29] of Double = (1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000, 5000,
    10000, 15000, 30000, 60000, 120000, 300000, 600000, 900000, 1800000, 3600000, 7200000,
    10800000, 21600000, 43200000, 86400000, 172800000, 604800000, 2592000000);
  TimeFormats: array[1..4] of string = ('hh:nn', 'hh:nn:ss', 'hh:nn:ss.zzz', 'dd-mm hh:nn');

type
  TTick = record
    V: Double;
    T: string;
  end;
  TTicks = array of TTick;

function DefaultChartOptions: TChartOptions;
begin
  Result.BackColor := RGBToColor(246, 247, 249);
  Result.PlotColor := clWhite;
  Result.PlotColor2 := RGBToColor(250, 251, 253);
  Result.GridColor := RGBToColor(228, 231, 236);
  Result.AxisColor := RGBToColor(150, 156, 166);
  Result.TextColor := RGBToColor(40, 44, 52);
  Result.CursorColor := RGBToColor(60, 60, 60);
  Result.BoxColor := RGBToColor(40, 120, 220);
  Result.FontName := 'Segoe UI';
  Result.AxisFont := 8;              // 40 % smaller than the 13 px before
  Result.LabelFont := 12;
  Result.GridX := True;
  Result.GridY := True;
  Result.TimeFormat := 0;
  Result.ShowDate := True;
  Result.LaneNames := True;
  Result.LaneGap := 4;
  Result.ShowReadout := True;
  Result.Crosshair := False;
  Result.LeftDrag := 1;
  Result.StartRows := 1000;
  Result.WheelPercent := 20;
  Result.LineWidth := 1;
  Result.ShowGaps := True;
  Result.LiveMs := 1000;
  Result.ExportW := 0;
  Result.ExportH := 0;
end;

function DarkChartOptions: TChartOptions;
begin
  Result := DefaultChartOptions;
  Result.BackColor := RGBToColor(30, 32, 36);
  Result.PlotColor := RGBToColor(22, 24, 28);
  Result.PlotColor2 := RGBToColor(28, 30, 35);
  Result.GridColor := RGBToColor(52, 56, 64);
  Result.AxisColor := RGBToColor(110, 116, 128);
  Result.TextColor := RGBToColor(220, 223, 228);
  Result.CursorColor := RGBToColor(230, 230, 230);
  Result.BoxColor := RGBToColor(90, 160, 255);
end;

function Px(C: TColor; Alpha: Byte = 255): TBGRAPixel;
var
  RGB: LongInt;
begin
  RGB := ColorToRGB(C);
  Result := BGRA(RGB and $FF, (RGB shr 8) and $FF, (RGB shr 16) and $FF, Alpha);
end;

function SeriesPixel(const S: TLogSeries): TBGRAPixel;
begin
  Result := BGRA(S.Color and $FF, (S.Color shr 8) and $FF, (S.Color shr 16) and $FF);
end;

{ V is already scaled (gain / offset) }
function FormatLogValue(const S: TLogSeries; V: Double): string;
begin
  if IsNan(V) then Exit('---');
  if S.IsBool and (S.Gain = 1) and (S.Offset = 0) then Result := IntToStr(Round(V))
  else Result := FloatToStrF(V, ffGeneral, 7, 0, ChartFmt);
  if S.UnitText <> '' then Result := Result + ' ' + S.UnitText;
end;

{ Ceil without the 32-bit limit of Math.Ceil (time in ms / step is far above 2^31:
  Ceil overflowed and the time axis started weeks too early -> endless loop) }
function CeilD(X: Double): Double;
begin
  Result := Int(X);
  if Result < X then Result := Result + 1;
end;

function NiceStep(Range: Double; MaxTicks: Integer): Double;
var
  Raw, Mag, F: Double;
begin
  if (Range <= 0) or (MaxTicks < 1) then Exit(1);
  Raw := Range / MaxTicks;
  Mag := Power(10, Floor(Log10(Raw)));
  F := Raw / Mag;
  if F <= 1 then Result := Mag
  else if F <= 2 then Result := 2 * Mag
  else if F <= 5 then Result := 5 * Mag
  else Result := 10 * Mag;
end;

{ ticks of one Y axis (value + text); Gap = pixels per tick }
function MakeTicks(S: TLogSeries; Lo, Hi: Double; H, Gap: Integer): TTicks;
var
  Stp, V: Double;
  N: Integer;
begin
  Result := nil;
  if S.IsBool then
  begin
    SetLength(Result, 2);
    Result[0].V := S.Scaled(0);
    Result[1].V := S.Scaled(1);
    if (S.Gain = 1) and (S.Offset = 0) then
    begin
      Result[0].T := '0';
      Result[1].T := '1';
    end
    else
    begin
      Result[0].T := FloatToStrF(Result[0].V, ffGeneral, 5, 0, ChartFmt);
      Result[1].T := FloatToStrF(Result[1].V, ffGeneral, 5, 0, ChartFmt);
    end;
    Exit;
  end;
  Stp := NiceStep(Hi - Lo, Max(1, H div Max(10, Gap)));
  V := CeilD(Lo / Stp) * Stp;
  N := 0;
  while (V <= Hi + Stp * 1e-9) and (N < 200) do
  begin
    SetLength(Result, N + 1);
    Result[N].V := V;
    if Abs(V) < Stp * 1e-6 then Result[N].T := '0'
    else Result[N].T := FloatToStrF(V, ffGeneral, 5, 0, ChartFmt);
    Inc(N);
    V := V + Stp;
  end;
end;

{ ============================== TLogChart ============================== }

constructor TLogChart.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  TabStop := True;
  FLanes := True;
  FCursorIndex := -1;
  FHoverAxis := -1;
  FPlotR := Rect(70, 12, 300, 200);
  FX0 := Now - 1 / 24;
  FX1 := Now;
  SetOptions(DefaultChartOptions);
  FDirty := True;
end;

destructor TLogChart.Destroy;
begin
  FreeAndNil(FCache);
  inherited Destroy;
end;

procedure TLogChart.Invalidate;
begin
  FDirty := True;
  inherited Invalidate;
end;

{ only the cursor / zoom box changed: the cached chart stays }
procedure TLogChart.RepaintCursor;
begin
  inherited Invalidate;
end;

procedure TLogChart.SetOptions(const AValue: TChartOptions);
begin
  FOpt := AValue;
  CBack := Px(FOpt.BackColor);
  CPlot := Px(FOpt.PlotColor);
  CPlot2 := Px(FOpt.PlotColor2);
  CGrid := Px(FOpt.GridColor);
  CAxis := Px(FOpt.AxisColor);
  CText := Px(FOpt.TextColor);
  CTextDim := Px(FOpt.TextColor, 150);
  CCursor := Px(FOpt.CursorColor, 160);
  CBox := Px(FOpt.BoxColor);
  CGap := BGRA(230, 60, 60, 40);
  Invalidate;
end;

procedure TLogChart.SetLanes(AValue: Boolean);
begin
  FLanes := AValue;
  Invalidate;
end;

procedure TLogChart.SetFitY(AValue: Boolean);
begin
  FFitY := AValue;
  Invalidate;
end;

procedure TLogChart.SetShowPoints(AValue: Boolean);
begin
  FShowPoints := AValue;
  Invalidate;
end;

function TLogChart.VisibleSeries: TList;
var
  I: Integer;
begin
  Result := TList.Create;
  if FData = nil then Exit;
  for I := 0 to High(FData.Series) do
    if FData.Series[I].Visible and FData.Series[I].Numeric then Result.Add(FData.Series[I]);
end;

procedure TLogChart.SetView(A, B: Double);
var
  M: Double;
begin
  if B - A < MIN_SPAN then
  begin
    M := (A + B) / 2;
    A := M - MIN_SPAN / 2;
    B := M + MIN_SPAN / 2;
  end;
  FX0 := A;
  FX1 := B;
  Invalidate;
  if Assigned(FOnViewChange) then FOnViewChange(Self);
end;

procedure TLogChart.FitAll;
var
  A, B, Pad: Double;
begin
  if (FData = nil) or (FData.Count = 0) then Exit;
  A := FData.FirstTime;
  B := FData.LastTime;
  if B - A < 1 / 86400 then
  begin
    Pad := (1 / 86400 - (B - A)) / 2;          // at least one second
    A := A - Pad;
    B := B + Pad;
  end;
  Pad := (B - A) * 0.01;
  SetView(A - Pad, B + Pad);
end;

procedure TLogChart.ShowLastRows(N: Integer);
var
  A, B, Pad: Double;
begin
  if (FData = nil) or (FData.Count = 0) then Exit;
  if (N <= 0) or (N >= FData.Count) then
  begin
    FitAll;
    Exit;
  end;
  A := FData.Times[FData.Count - N];
  B := FData.LastTime;
  Pad := Max((B - A) * 0.01, 1 / MS_PER_DAY);
  SetView(A - Pad, B + Pad);
end;

procedure TLogChart.ZoomBy(Factor: Double);
var
  M, H: Double;
begin
  M := (FX0 + FX1) / 2;
  H := (FX1 - FX0) / 2 * Factor;
  SetView(M - H, M + H);
end;

procedure TLogChart.PanBy(Fraction: Double);
var
  D: Double;
begin
  D := (FX1 - FX0) * Fraction;
  SetView(FX0 + D, FX1 + D);
end;

procedure TLogChart.ResetY;
var
  I: Integer;
begin
  if FData <> nil then
    for I := 0 to High(FData.Series) do FData.Series[I].YManual := False;
  Invalidate;
end;

procedure TLogChart.ForgetLayout;
begin
  FLaySer := nil;
  FAxisR := nil;
  FSerR := nil;
  FRanges := nil;
  FHist := nil;
  FHoverAxis := -1;
  FDrag := dmNone;
end;

procedure TLogChart.PushView;
var
  N, I: Integer;
begin
  if FData = nil then Exit;
  if Length(FHist) >= MAX_HIST then Delete(FHist, 0, 1);
  N := Length(FHist);
  SetLength(FHist, N + 1);
  FHist[N].X0 := FX0;
  FHist[N].X1 := FX1;
  SetLength(FHist[N].Ser, Length(FData.Series));
  SetLength(FHist[N].Man, Length(FData.Series));
  SetLength(FHist[N].Lo, Length(FData.Series));
  SetLength(FHist[N].Hi, Length(FData.Series));
  for I := 0 to High(FData.Series) do
  begin
    FHist[N].Ser[I] := FData.Series[I];
    FHist[N].Man[I] := FData.Series[I].YManual;
    FHist[N].Lo[I] := FData.Series[I].YLo;
    FHist[N].Hi[I] := FData.Series[I].YHi;
  end;
end;

function TLogChart.CanZoomBack: Boolean;
begin
  Result := Length(FHist) > 0;
end;

function TLogChart.ZoomBack: Boolean;
var
  N, I, K: Integer;
begin
  Result := Length(FHist) > 0;
  if not Result then Exit;
  N := High(FHist);
  for I := 0 to High(FHist[N].Ser) do
    for K := 0 to High(FData.Series) do
      if FData.Series[K] = FHist[N].Ser[I] then
      begin
        FData.Series[K].YManual := FHist[N].Man[I];
        FData.Series[K].YLo := FHist[N].Lo[I];
        FData.Series[K].YHi := FHist[N].Hi[I];
      end;
  SetView(FHist[N].X0, FHist[N].X1);
  SetLength(FHist, N);
end;

function TLogChart.CurrentRange(S: TLogSeries; out Lo, Hi: Double): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(FLaySer) do
    if FLaySer[I] = S then
    begin
      Lo := FRanges[I].X;
      Hi := FRanges[I].Y;
      Exit(True);
    end;
  Result := False;
  Lo := NaN;
  Hi := NaN;
end;

function TLogChart.TimeAtX(X: Integer): Double;
begin
  Result := FX0 + (X - FPlotR.Left) / Max(1, FPlotR.Width) * (FX1 - FX0);
end;

function TLogChart.InPlot(X, Y: Integer): Boolean;
begin
  Result := (X >= FPlotR.Left) and (X <= FPlotR.Right) and (Y >= FPlotR.Top) and (Y <= FPlotR.Bottom);
end;

{ the time axis: under the plot, as wide as the plot }
function TLogChart.OnTimeAxis(X, Y: Integer): Boolean;
begin
  Result := (X >= FPlotR.Left) and (X <= FPlotR.Right) and (Y > FPlotR.Bottom);
end;

{ the zoom box being dragged, kept inside the plot (never over the axes) }
function TLogChart.BoxRect: TRect;
begin
  Result := Rect(Max(FPlotR.Left, Min(FDragStart.X, FMouse.X)), Max(FPlotR.Top, Min(FDragStart.Y, FMouse.Y)),
    Min(FPlotR.Right, Max(FDragStart.X, FMouse.X)), Min(FPlotR.Bottom, Max(FDragStart.Y, FMouse.Y)));
end;

function TLogChart.AxisAt(X, Y: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FAxisR) do
    if (X >= FAxisR[I].Left) and (X < FAxisR[I].Right) and (Y >= FAxisR[I].Top) and (Y < FAxisR[I].Bottom) then
      Exit(I);
  Result := -1;
end;

{ Y range of a series (scaled values): manual, all data, or only the visible rows (FitY) }
procedure TLogChart.SeriesRange(S: TLogSeries; out Lo, Hi: Double);
var
  I, I0, I1, Stp: Integer;
  V: Double;
  Pad: Double;
begin
  if S.YManual and (S.YHi > S.YLo) then
  begin
    Lo := S.YLo;              // set with the mouse / in the properties
    Hi := S.YHi;
    Exit;
  end;
  if S.IsBool then
  begin
    Lo := Min(S.Scaled(0), S.Scaled(1));
    Hi := Max(S.Scaled(0), S.Scaled(1));
    Pad := (Hi - Lo) * 0.15;
    if Pad = 0 then Pad := 1;
    Lo := Lo - Pad;
    Hi := Hi + Pad;
    Exit;
  end;
  S.ScaledMinMax(Lo, Hi);
  if FFitY and (FData.Count > 0) then
  begin
    I0 := Max(0, FData.IndexAtOrAfter(FX0) - 1);
    I1 := Min(FData.Count - 1, FData.IndexAtOrAfter(FX1));
    Stp := Max(1, (I1 - I0) div 200000);      // big ranges: every n-th row is enough here
    Lo := NaN;
    Hi := NaN;
    I := I0;
    while I <= I1 do
    begin
      if not IsNan(S.Values[I]) then
      begin
        V := S.Scaled(S.Values[I]);
        if IsNan(Lo) or (V < Lo) then Lo := V;
        if IsNan(Hi) or (V > Hi) then Hi := V;
      end;
      Inc(I, Stp);
    end;
    if IsNan(Lo) then S.ScaledMinMax(Lo, Hi);
  end;
  if IsNan(Lo) then
  begin
    Lo := 0;
    Hi := 1;
  end;
  if Hi - Lo < 1e-12 then
  begin
    Pad := Max(Abs(Lo) * 0.1, 1);
    Lo := Lo - Pad;
    Hi := Hi + Pad;
  end
  else
  begin
    Pad := (Hi - Lo) * 0.06;
    Lo := Lo - Pad;
    Hi := Hi + Pad;
  end;
end;

{ the line of one series as polyline(s): steps, dashes, gaps (EmptyPointF), points }
procedure TLogChart.DrawSeries(B: TBGRABitmap; S: TLogSeries; const R: TRect; Lo, Hi: Double);
var
  I, I0, I1, N, Col, NP: Integer;
  V: Double;
  C: TBGRAPixel;
  XS, YS, PX, PY, LastY, W, Rad: Single;
  Steps, Dots, Prev, HasCol, Direct, Linked: Boolean;
  CMin, CMax, CFirst, CLast, PrevLast: Single;
  PrevCol: Integer;
  Pts: array of TPointF;

  procedure Add(X, Y: Single);
  begin
    if NP >= Length(Pts) then SetLength(Pts, NP * 2 + 64);
    Pts[NP] := PointF(X, Y);
    Inc(NP);
  end;

  procedure Gap;
  begin
    Linked := False;
    if (NP > 0) and not IsEmptyPointF(Pts[NP - 1]) then Add(EmptySingle, EmptySingle);
  end;

  procedure FlushColumn;
  begin
    if not HasCol then Exit;
    if Direct then
    begin
      { solid line, many rows: a short line from the last column, then one vertical
        line min..max (aliased: a vertical line looks the same, and it is much faster) }
      if W <= 1.5 then
      begin
        if Linked then B.DrawLine(PrevCol, Round(PrevLast), Col, Round(CFirst), C, False, dmDrawWithTransparency);
        B.VertLine(Col, Round(CMin), Round(CMax), C, dmDrawWithTransparency);
      end
      else
      begin
        if Linked then B.DrawLineAntialias(PrevCol + 0.5, PrevLast, Col + 0.5, CFirst, C, W);
        B.FillRectAntialias(Col + 0.5 - W / 2, CMin - W / 2, Col + 0.5 + W / 2, CMax + W / 2, C);
      end;
      PrevCol := Col;
      PrevLast := CLast;
      Linked := True;
    end
    else
    begin
      Add(Col + 0.5, CFirst);
      if CMin < CFirst then Add(Col + 0.5, CMin);
      if CMax > CMin then Add(Col + 0.5, CMax);
      Add(Col + 0.5, CLast);
    end;
    HasCol := False;
  end;

begin
  if (FData = nil) or (FData.Count = 0) or (Hi <= Lo) then Exit;
  I0 := Max(0, FData.IndexAtOrAfter(FX0) - 1);
  I1 := Min(FData.Count - 1, FData.IndexAtOrAfter(FX1));
  N := I1 - I0 + 1;
  if N <= 0 then Exit;
  C := SeriesPixel(S);
  W := S.LineWidth;
  if W <= 0 then W := FOpt.LineWidth;
  XS := R.Width / (FX1 - FX0);
  YS := R.Height / (Hi - Lo);
  Steps := (S.DrawMode = 2) or ((S.DrawMode = 0) and S.IsBool);
  Pts := nil;
  NP := 0;
  Direct := False;
  Linked := False;
  if N <= 2 * R.Width then
  begin
    { few rows: the real line }
    case S.PointMode of
      1: Dots := False;
      2: Dots := True;
    else
      Dots := FShowPoints or (N < R.Width div 8);
    end;
    Rad := Max(1, S.PointSize / 2);
    Prev := False;
    LastY := 0;
    for I := I0 to I1 do
    begin
      if IsNan(S.Values[I]) then
      begin
        Gap;
        Prev := False;
        Continue;
      end;
      V := S.Scaled(S.Values[I]);
      PX := R.Left + (FData.Times[I] - FX0) * XS;
      PY := R.Bottom - (V - Lo) * YS;
      if Prev and Steps then Add(PX, LastY);
      Add(PX, PY);
      if Dots then B.FillEllipseAntialias(PX, PY, Rad, Rad, C)
      else if not Prev and ((I = I1) or IsNan(S.Values[Min(I + 1, FData.Count - 1)])) then
        B.FillEllipseAntialias(PX, PY, W + 0.8, W + 0.8, C);     // single sample: keep it visible
      LastY := PY;
      Prev := True;
    end;
  end
  else
  begin
    { many rows: min / max per pixel column }
    Direct := S.LineStyle = 0;
    Linked := False;
    PrevCol := 0;
    PrevLast := 0;
    HasCol := False;
    Col := 0;
    CMin := 0; CMax := 0; CFirst := 0; CLast := 0;
    for I := I0 to I1 do
    begin
      if IsNan(S.Values[I]) then
      begin
        FlushColumn;
        Gap;
        Continue;
      end;
      V := S.Scaled(S.Values[I]);
      PX := R.Left + (FData.Times[I] - FX0) * XS;
      PY := R.Bottom - (V - Lo) * YS;
      if not HasCol or (Trunc(PX) <> Col) then
      begin
        FlushColumn;
        Col := Trunc(PX);
        CMin := PY; CMax := PY; CFirst := PY; CLast := PY;
        HasCol := True;
      end
      else
      begin
        if PY < CMin then CMin := PY;
        if PY > CMax then CMax := PY;
        CLast := PY;
      end;
    end;
    FlushColumn;
  end;
  if NP = 0 then Exit;
  if S.LineStyle = 0 then
  begin
    { solid: segment by segment - much faster than one wide polyline with thousands of joins }
    for I := 1 to NP - 1 do
      if not IsEmptyPointF(Pts[I - 1]) and not IsEmptyPointF(Pts[I]) then
        B.DrawLineAntialias(Pts[I - 1].X, Pts[I - 1].Y, Pts[I].X, Pts[I].Y, C, W);
    Exit;
  end;
  { dash / dot: one polyline per part, so the pattern runs on over the points }
  SetLength(Pts, NP);
  case S.LineStyle of
    1: B.PenStyle := psDash;
    2: B.PenStyle := psDot;
    3: B.PenStyle := psDashDot;
  else
    B.PenStyle := psSolid;
  end;
  B.DrawPolyLineAntialias(Pts, C, W);
  B.PenStyle := psSolid;
end;

function TLogChart.AxisWidth(B: TBGRABitmap; S: TLogSeries; Lo, Hi: Double; H: Integer): Integer;
var
  Ticks: TTicks;
  I: Integer;
begin
  B.FontHeight := FOpt.AxisFont;
  Ticks := MakeTicks(S, Lo, Hi, H, B.FontFullHeight * 3);
  Result := 0;
  for I := 0 to High(Ticks) do Result := Max(Result, B.TextSize(Ticks[I].T).cx);
  Result := Max(14, Result + 11);       // 4 tick + 5 gap + 2
end;

{ Y axis of a lane: numbers left of the plot, grid lines across the lane }
procedure TLogChart.DrawLaneAxis(B: TBGRABitmap; const LR: TRect; Lo, Hi: Double; S: TLogSeries);
var
  Ticks: TTicks;
  I: Integer;
  Y: Single;
begin
  B.FontHeight := FOpt.AxisFont;
  Ticks := MakeTicks(S, Lo, Hi, LR.Height, B.FontFullHeight * 2);
  for I := 0 to High(Ticks) do
  begin
    Y := LR.Bottom - (Ticks[I].V - Lo) / (Hi - Lo) * LR.Height;
    if (Y < LR.Top - 0.5) or (Y > LR.Bottom + 0.5) then Continue;
    if FOpt.GridY then B.DrawLineAntialias(LR.Left, Y, LR.Right, Y, CGrid, 1);
    B.DrawLineAntialias(LR.Left - 4, Y, LR.Left, Y, CAxis, 1);
    B.TextOut(LR.Left - 6, Y - B.FontFullHeight / 2, Ticks[I].T, CText, taRightJustify);
  end;
end;

{ own Y axis of one series (overlay): line, ticks and numbers in the series colour }
procedure TLogChart.DrawSideAxis(B: TBGRABitmap; const AR, R: TRect; Lo, Hi: Double; S: TLogSeries;
  Grid, Hover: Boolean);
var
  C: TBGRAPixel;
  X, Y: Single;
  Ticks: TTicks;
  I: Integer;
begin
  C := SeriesPixel(S);
  if Hover then B.FillRect(AR, BGRA(C.red, C.green, C.blue, 30), dmDrawWithTransparency);
  X := AR.Right - 1;
  B.DrawLineAntialias(X, R.Top, X, R.Bottom, C, 1.5);
  B.FontHeight := FOpt.AxisFont;
  Ticks := MakeTicks(S, Lo, Hi, R.Height, B.FontFullHeight * 3);
  for I := 0 to High(Ticks) do
  begin
    Y := R.Bottom - (Ticks[I].V - Lo) / (Hi - Lo) * R.Height;
    if (Y < R.Top - 0.5) or (Y > R.Bottom + 0.5) then Continue;
    if Grid and FOpt.GridY then B.DrawLineAntialias(R.Left, Y, R.Right, Y, CGrid, 1);
    B.DrawLineAntialias(X - 4, Y, X, Y, C, 1);
    B.TextOut(X - 5, Y - B.FontFullHeight / 2, Ticks[I].T, C, taRightJustify);
  end;
end;

procedure TLogChart.DrawTimeAxis(B: TBGRABitmap; const R: TRect);
var
  SpanMs, Stp, T, X: Double;
  I, MaxTicks, LabelW, N: Integer;
  Fmt: string;
  LastDay, Day: Integer;
begin
  B.FontHeight := FOpt.AxisFont;
  if FOpt.TimeFormat in [1..4] then Fmt := TimeFormats[FOpt.TimeFormat] else Fmt := 'hh:nn:ss.zzz';
  LabelW := B.TextSize(FormatDateTime(Fmt, 0.5, ChartFmt)).cx + 24;
  SpanMs := (FX1 - FX0) * MS_PER_DAY;
  MaxTicks := Max(2, R.Width div Max(30, LabelW));
  Stp := TimeSteps[High(TimeSteps)];
  for I := 0 to High(TimeSteps) do
    if SpanMs / TimeSteps[I] <= MaxTicks then
    begin
      Stp := TimeSteps[I];
      Break;
    end;
  if FOpt.TimeFormat in [1..4] then Fmt := TimeFormats[FOpt.TimeFormat]
  else if Stp < 1000 then Fmt := 'hh:nn:ss.zzz'
  else if Stp < 60000 then Fmt := 'hh:nn:ss'
  else if Stp < 86400000 then Fmt := 'hh:nn'
  else Fmt := 'dd-mm';
  { ticks at multiples of the step (local time, days start at midnight) }
  T := CeilD(FX0 * MS_PER_DAY / Stp) * Stp / MS_PER_DAY;
  LastDay := -1;
  N := 0;
  while (T <= FX1) and (N < 1000) do      // N: never an endless loop
  begin
    Inc(N);
    X := R.Left + (T - FX0) / (FX1 - FX0) * R.Width;
    if FOpt.GridX then B.DrawLineAntialias(X, R.Top, X, R.Bottom, CGrid, 1);
    B.DrawLineAntialias(X, R.Bottom, X, R.Bottom + 4, CAxis, 1);
    B.TextOut(X, R.Bottom + 5, FormatDateTime(Fmt, T, ChartFmt), CText, taCenter);
    Day := Trunc(T + 1e-9);
    if FOpt.ShowDate and (Day <> LastDay) and (Stp < 86400000) then
    begin
      { the date under the first tick and under every new day }
      B.TextOut(X, R.Bottom + 5 + B.FontFullHeight, FormatDateTime('dd-mm-yyyy', T, ChartFmt),
        CTextDim, taCenter);
      LastDay := Day;
    end;
    T := T + Stp / MS_PER_DAY;
  end;
end;

{ rows without connection: red marks under the plot, light red bands in it }
procedure TLogChart.DrawGaps(B: TBGRABitmap; const R: TRect);
var
  I, I0, I1, Col, LastCol: Integer;
  X: Double;
begin
  if not FOpt.ShowGaps or (FData = nil) or (FData.Count = 0) then Exit;
  I0 := Max(0, FData.IndexAtOrAfter(FX0));
  I1 := Min(FData.Count - 1, FData.IndexAtOrAfter(FX1));
  LastCol := MaxInt;
  for I := I0 to I1 do
    if FData.Status[I] = rsNoConnection then
    begin
      X := R.Left + (FData.Times[I] - FX0) / (FX1 - FX0) * R.Width;
      Col := Trunc(X);
      if Col = LastCol then Continue;
      LastCol := Col;
      B.FillRect(Col, R.Top, Col + 2, R.Bottom, CGap, dmDrawWithTransparency);
      B.FillRect(Col, R.Bottom - 3, Col + 2, R.Bottom + 1, BGRA(220, 40, 40), dmSet);
    end;
end;

procedure TLogChart.DrawCursor(B: TBGRABitmap; const R: TRect);
var
  I, K, W, H, BX, BY, LH: Integer;
  X, Y: Single;
  S: TLogSeries;
  V: Double;
  Lines: TStringList;
  LR: TRect;
  St: string;
begin
  FCursorIndex := -1;
  if not FMouseIn or (FDrag <> dmNone) or (FData = nil) or (FData.Count = 0) then Exit;
  if (FMouse.X < R.Left) or (FMouse.X > R.Right) or (FMouse.Y < R.Top) or (FMouse.Y > R.Bottom) then Exit;
  if FOpt.Crosshair then B.DrawLineAntialias(R.Left, FMouse.Y + 0.5, R.Right, FMouse.Y + 0.5, CCursor, 1);
  K := FData.Nearest(TimeAtX(FMouse.X));
  if K < 0 then Exit;
  X := R.Left + (FData.Times[K] - FX0) / (FX1 - FX0) * R.Width;
  if (X < R.Left - 1) or (X > R.Right + 1) then Exit;
  FCursorIndex := K;
  B.DrawLineAntialias(X, R.Top, X, R.Bottom, CCursor, 1);
  B.FontHeight := FOpt.LabelFont;
  Lines := TStringList.Create;
  try
    case FData.Status[K] of
      rsTagError: St := '   TAG ERROR';
      rsNoConnection: St := '   NO CONNECTION';
    else
      St := '';
    end;
    Lines.Add(FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', FData.Times[K], ChartFmt) + St);
    W := B.TextSize(Lines[0]).cx;
    for I := 0 to High(FLaySer) do
    begin
      S := FLaySer[I];
      if IsNan(S.Values[K]) then V := NaN else V := S.Scaled(S.Values[K]);
      Lines.Add(S.Caption + ':  ' + FormatLogValue(S, V));
      W := Max(W, B.TextSize(Lines[I + 1]).cx + 14);
      if not IsNan(V) then
      begin
        LR := FSerR[I];
        Y := LR.Bottom - (V - FRanges[I].X) / (FRanges[I].Y - FRanges[I].X) * LR.Height;
        if (Y >= LR.Top - 2) and (Y <= LR.Bottom + 2) then
        begin
          B.FillEllipseAntialias(X, Y, 3.5, 3.5, SeriesPixel(S));
          B.EllipseAntialias(X, Y, 3.5, 3.5, CPlot, 1);
        end;
      end;
    end;
    if not FOpt.ShowReadout then Exit;
    LH := B.FontFullHeight + 1;
    W := W + 16;
    H := Lines.Count * LH + 10;
    BX := Round(X) + 14;
    if BX + W > R.Right then BX := Round(X) - 14 - W;
    BY := Max(R.Top + 4, Min(FMouse.Y - H div 2, R.Bottom - H - 4));
    B.FillRoundRectAntialias(BX, BY, BX + W, BY + H, 6, 6, Px(FOpt.PlotColor, 238));
    B.RoundRectAntialias(BX, BY, BX + W, BY + H, 6, 6, CAxis, 1);
    B.TextOut(BX + 8, BY + 5, Lines[0], CText);
    for I := 0 to High(FLaySer) do
    begin
      B.FillRect(BX + 8, BY + 5 + (I + 1) * LH + LH div 2 - 4, BX + 16, BY + 5 + (I + 1) * LH + LH div 2 + 4,
        SeriesPixel(FLaySer[I]), dmSet);
      B.TextOut(BX + 22, BY + 5 + (I + 1) * LH, Lines[I + 1], CText);
    end;
  finally
    Lines.Free;
  end;
end;

procedure TLogChart.RenderTo(B: TBGRABitmap; WithCursor: Boolean);
begin
  RenderBase(B);
  if WithCursor then DrawOverlay(B);
end;

{ cursor, value box and zoom box over the chart (layout of the last RenderBase) }
procedure TLogChart.DrawOverlay(B: TBGRABitmap);
var
  LR: TRect;
begin
  if (FPlotR.Width < 20) or (FData = nil) or (FData.Count = 0) then Exit;
  DrawCursor(B, FPlotR);
  if FDrag = dmZoom then
  begin
    LR := BoxRect;
    B.FillRect(LR, BGRA(CBox.red, CBox.green, CBox.blue, 45), dmDrawWithTransparency);
    B.Rectangle(LR, CBox, dmSet);
  end;
end;

procedure TLogChart.RenderBase(B: TBGRABitmap);
var
  R, LR, AR: TRect;
  Ser: TList;
  I, N, LaneH, Y, X, Tot, Bottom, LeftW, NameH: Integer;
  S: TLogSeries;
  Lo, Hi: Double;
  C: TBGRAPixel;
  AxW: array of Integer;
begin
  B.Fill(CBack);
  B.FontName := FOpt.FontName;
  B.FontQuality := fqSystemClearType;
  B.FontHeight := FOpt.AxisFont;
  Bottom := B.FontFullHeight * IfThen(FOpt.ShowDate, 2, 1) + 9;
  B.FontHeight := FOpt.LabelFont;
  if FOpt.LaneNames then NameH := B.FontFullHeight + 2 else NameH := 2;
  Ser := VisibleSeries;
  try
    N := Ser.Count;
    SetLength(FLaySer, N);
    SetLength(FAxisR, N);
    SetLength(FSerR, N);
    SetLength(FRanges, N);
    SetLength(AxW, N);
    for I := 0 to N - 1 do
    begin
      FLaySer[I] := TLogSeries(Ser[I]);
      SeriesRange(FLaySer[I], Lo, Hi);
      FRanges[I] := PointF(Lo, Hi);
    end;
    { plot area: room for the Y axes on the left, each only as wide as its numbers }
    if (N > 0) and (FData <> nil) and (FData.Count > 0) then
    begin
      Tot := 0;
      LeftW := 0;
      for I := 0 to N - 1 do
      begin
        if FLanes then
          AxW[I] := AxisWidth(B, FLaySer[I], FRanges[I].X, FRanges[I].Y, Max(20, (B.Height - Bottom) div N))
        else
          AxW[I] := AxisWidth(B, FLaySer[I], FRanges[I].X, FRanges[I].Y, B.Height - Bottom - 8);
        Inc(Tot, AxW[I]);
        LeftW := Max(LeftW, AxW[I]);
      end;
      if FLanes then R := Rect(Max(30, LeftW + 6), 8, B.Width - 12, B.Height - Bottom)
      else R := Rect(Max(30, Tot + 6), 8, B.Width - 12, B.Height - Bottom);
    end
    else
      R := Rect(40, 8, B.Width - 12, B.Height - Bottom);
    FPlotR := R;
    if (R.Width < 20) or (R.Height < 20) then
    begin
      ForgetLayout;
      Exit;
    end;
    B.FillRect(R, CPlot, dmSet);
    if (FData = nil) or (FData.Count = 0) then
    begin
      FLaySer := nil;
      FAxisR := nil;
      B.FontHeight := FOpt.LabelFont;
      B.TextOut((R.Left + R.Right) / 2, (R.Top + R.Bottom) / 2 - 10,
        'File > Open...  (or drop a CSV file of the PLC Data Logger here)', CTextDim, taCenter);
      B.Rectangle(R, CAxis, dmSet);
      Exit;
    end;
    DrawTimeAxis(B, R);
    DrawGaps(B, R);
    if N = 0 then
    begin
      B.FontHeight := FOpt.LabelFont;
      B.TextOut((R.Left + R.Right) / 2, (R.Top + R.Bottom) / 2 - 10, 'No series selected', CTextDim, taCenter);
    end
    else if FLanes then
    begin
      { every series in its own strip with its own scale }
      LaneH := R.Height div N;
      for I := 0 to N - 1 do
      begin
        S := FLaySer[I];
        Y := R.Top + I * LaneH;
        LR := Rect(R.Left, Y + NameH + FOpt.LaneGap div 2 + 2, R.Right, Y + LaneH - FOpt.LaneGap div 2 - 2);
        if LR.Height < 6 then LR.Bottom := LR.Top + 6;
        FSerR[I] := LR;
        FAxisR[I] := Rect(0, Y, R.Left, Y + LaneH);
        if Odd(I) then B.FillRect(R.Left, Y, R.Right, Y + LaneH, CPlot2, dmSet);
        if I > 0 then B.DrawLineAntialias(R.Left, Y, R.Right, Y, CAxis, 1);
        if I = FHoverAxis then
        begin
          C := SeriesPixel(S);
          B.FillRect(FAxisR[I], BGRA(C.red, C.green, C.blue, 30), dmDrawWithTransparency);
        end;
        DrawLaneAxis(B, LR, FRanges[I].X, FRanges[I].Y, S);
        B.ClipRect := Rect(R.Left, Y + 1, R.Right, Y + LaneH);
        DrawSeries(B, S, LR, FRanges[I].X, FRanges[I].Y);
        B.NoClip;
        if FOpt.LaneNames then
        begin
          B.FontHeight := FOpt.LabelFont;
          B.TextOut(R.Left + 6, Y + 1, S.Caption, SeriesPixel(S));
        end;
      end;
    end
    else
    begin
      { one plot, every series with its own Y axis, all on the left: the first next to the plot }
      X := R.Left;
      for I := 0 to N - 1 do
      begin
        S := FLaySer[I];
        FSerR[I] := R;
        AR := Rect(X - AxW[I], R.Top, X, R.Bottom);
        X := X - AxW[I];
        FAxisR[I] := AR;
        DrawSideAxis(B, AR, R, FRanges[I].X, FRanges[I].Y, S, I = 0, I = FHoverAxis);
      end;
      B.ClipRect := R;
      for I := 0 to N - 1 do DrawSeries(B, FLaySer[I], R, FRanges[I].X, FRanges[I].Y);
      B.NoClip;
    end;
    B.Rectangle(R, CAxis, dmSet);
  finally
    Ser.Free;
  end;
end;

procedure TLogChart.Paint;
var
  B: TBGRABitmap;
begin
  if (FCache = nil) or (FCache.Width <> ClientWidth) or (FCache.Height <> ClientHeight) then
  begin
    FreeAndNil(FCache);
    FCache := TBGRABitmap.Create(Max(1, ClientWidth), Max(1, ClientHeight));
    FDirty := True;
  end;
  if FDirty then
  begin
    FDirty := False;
    try
      RenderBase(FCache);
    except
      on E: Exception do
      begin
        { never an error dialog from Paint (it would come again at every repaint) }
        FCache.Fill(CBack);
        FCache.FontHeight := 14;
        FCache.TextOut(20, 20, 'Drawing error: ' + E.Message + '  (View > Whole file)', BGRA(200, 0, 0));
        FLaySer := nil;
        FAxisR := nil;
      end;
    end;
  end;
  B := FCache.Duplicate as TBGRABitmap;
  try
    try
      DrawOverlay(B);
    except
      { cursor: skip this time }
    end;
    B.Draw(Canvas, 0, 0, True);
  finally
    B.Free;
  end;
  if Assigned(FOnCursor) then FOnCursor(Self);
end;

procedure TLogChart.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  K: Integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if CanFocus then SetFocus;
  FMouse := Point(X, Y);
  FDragStart := Point(X, Y);
  FDragX0 := FX0;
  FDragX1 := FX1;
  { on a Y axis: move (offset) this series up / down }
  K := AxisAt(X, Y);
  if (K >= 0) and (Button = mbLeft) then
  begin
    FDrag := dmAxis;
    FDragAxis := K;
    FAxisLo0 := FRanges[K].X;
    FAxisHi0 := FRanges[K].Y;
    PushView;
    Exit;
  end;
  { left drag = zoom box and right drag = move (LeftDrag = 1, default), or the other way round;
    Shift + left = the other one of the two, middle button = move }
  case Button of
    mbLeft:
      if (ssShift in Shift) xor (FOpt.LeftDrag = 1) then FDrag := dmZoom else FDrag := dmPan;
    mbRight:
      if FOpt.LeftDrag = 1 then FDrag := dmPan else FDrag := dmZoom;
    mbMiddle:
      FDrag := dmPan;
  end;
  { zoom box: only from inside the plot; moving: in the plot or on the time axis }
  if (FDrag = dmZoom) and not InPlot(X, Y) then
  begin
    if OnTimeAxis(X, Y) then FDrag := dmPan else FDrag := dmNone;   // time axis: left or right drag moves
  end
  else if (FDrag = dmPan) and not (InPlot(X, Y) or OnTimeAxis(X, Y)) then
    FDrag := dmNone;
end;

procedure TLogChart.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  D: Double;
  K: Integer;
  S: TLogSeries;
begin
  inherited MouseMove(Shift, X, Y);
  FMouse := Point(X, Y);
  FMouseIn := True;
  if FDrag = dmAxis then
  begin
    if FDragAxis > High(FLaySer) then Exit;
    S := FLaySer[FDragAxis];
    { drag down = the curve goes down with the mouse }
    D := (Y - FDragStart.Y) / Max(1, FSerR[FDragAxis].Height) * (FAxisHi0 - FAxisLo0);
    S.YManual := True;
    S.YLo := FAxisLo0 + D;
    S.YHi := FAxisHi0 + D;
    Invalidate;
    if Assigned(FOnViewChange) then FOnViewChange(Self);
    Exit;
  end;
  if FDrag = dmNone then
  begin
    K := AxisAt(X, Y);
    if K >= 0 then Cursor := crSizeNS
    else if OnTimeAxis(X, Y) then Cursor := crSizeWE      // right drag: move the time
    else Cursor := crDefault;
    if K <> FHoverAxis then
    begin
      FHoverAxis := K;
      Invalidate;                  // axis tint is part of the chart
      Exit;
    end;
  end;
  if FDrag = dmPan then
  begin
    D := (X - FDragStart.X) / Max(1, FPlotR.Width) * (FDragX1 - FDragX0);
    SetView(FDragX0 - D, FDragX1 - D);
  end
  else
    RepaintCursor;                 // cursor / zoom box only
end;

{ zoom box: time from its width, Y from its height
  (overlay: all series, lanes: the series of the lane the box is in) }
procedure TLogChart.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  A, B, VTop, VBot: Double;
  BoxR, LR: TRect;
  I: Integer;
  S: TLogSeries;
  DoX, DoY: Boolean;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if FDrag = dmZoom then
  begin
    FMouse := Point(X, Y);
    BoxR := BoxRect;
    DoX := BoxR.Width > 4;
    DoY := BoxR.Height > 4;
    FDrag := dmNone;
    if DoX or DoY then
    begin
      PushView;
      if DoY then
        for I := 0 to High(FLaySer) do
        begin
          LR := FSerR[I];
          { lanes: only the lane that holds the whole box }
          if FLanes and ((BoxR.Top < FAxisR[I].Top) or (BoxR.Bottom > FAxisR[I].Bottom)) then Continue;
          S := FLaySer[I];
          VTop := FRanges[I].X + (LR.Bottom - BoxR.Top) / Max(1, LR.Height) * (FRanges[I].Y - FRanges[I].X);
          VBot := FRanges[I].X + (LR.Bottom - BoxR.Bottom) / Max(1, LR.Height) * (FRanges[I].Y - FRanges[I].X);
          if VTop > VBot then
          begin
            S.YManual := True;
            S.YLo := VBot;
            S.YHi := VTop;
          end;
        end;
      if DoX then
      begin
        A := TimeAtX(BoxR.Left);
        B := TimeAtX(BoxR.Right);
        SetView(A, B);
      end
      else if Assigned(FOnViewChange) then FOnViewChange(Self);
    end;
  end;
  FDrag := dmNone;
  Invalidate;
end;

procedure TLogChart.MouseLeave;
begin
  inherited MouseLeave;
  FMouseIn := False;
  Cursor := crDefault;
  if FHoverAxis >= 0 then
  begin
    FHoverAxis := -1;
    Invalidate;
  end
  else
    RepaintCursor;
end;

function TLogChart.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
var
  T, F, V, Lo, Hi: Double;
  K, Y: Integer;
  SR: TRect;
  S: TLogSeries;
begin
  Result := True;
  F := 1 - EnsureRange(FOpt.WheelPercent, 5, 60) / 100;
  if WheelDelta < 0 then F := 1 / F;
  K := AxisAt(MousePos.X, MousePos.Y);
  if K >= 0 then
  begin
    { on a Y axis: zoom this series around the value under the mouse }
    S := FLaySer[K];
    SR := FSerR[K];
    Lo := FRanges[K].X;
    Hi := FRanges[K].Y;
    Y := Max(SR.Top, Min(SR.Bottom, MousePos.Y));
    V := Lo + (SR.Bottom - Y) / Max(1, SR.Height) * (Hi - Lo);
    S.YManual := True;
    S.YLo := V - (V - Lo) * F;
    S.YHi := V + (Hi - V) * F;
    Invalidate;
    if Assigned(FOnViewChange) then FOnViewChange(Self);
    Exit;
  end;
  { zoom the time around the time under the mouse }
  T := TimeAtX(MousePos.X);
  SetView(T - (T - FX0) * F, T + (FX1 - T) * F);
end;

procedure TLogChart.DblClick;
var
  K: Integer;
begin
  inherited DblClick;
  FDrag := dmNone;
  K := AxisAt(FMouse.X, FMouse.Y);
  if K >= 0 then
  begin
    FLaySer[K].YManual := False;        // this axis automatic again
    Invalidate;
    if Assigned(FOnViewChange) then FOnViewChange(Self);
    Exit;
  end;
  PushView;
  ResetY;                               // everything: whole file, all axes automatic
  FitAll;
end;

procedure TLogChart.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited KeyDown(Key, Shift);
  case Key of
    VK_HOME:
      begin
        PushView;
        FitAll;
      end;
    VK_BACK: ZoomBack;
    VK_ADD, VK_OEM_PLUS: ZoomBy(0.5);
    VK_SUBTRACT, VK_OEM_MINUS: ZoomBy(2);
    VK_LEFT: PanBy(-0.2);
    VK_RIGHT: PanBy(0.2);
  else
    Exit;
  end;
  Key := 0;
end;

initialization
  ChartFmt := DefaultFormatSettings;
  ChartFmt.DecimalSeparator := '.';
  ChartFmt.ThousandSeparator := ',';
end.
