{ ============================================================================
  ucsvdata - reads the CSV files of the PLC Data Logger
    Date,Time,Status,<name (address)>,...      header (written again when the tag list changed)
    2026-10-25,10:40:27.698,OK,836,7.93,1      one row per cycle
  - several files (days) are put together in time order
  - the columns of all headers are joined by name; a column missing in a part = no value
  - values in every display format of the logger: numbers, 16#.. (HEX), 2#.. (BIN),
    TRUE/FALSE, ON/OFF, T#1h_2m_3s (TIME), hh:mm:ss.zzz (TOD); text (dates) = no value
  - rows with NO CONNECTION / empty cells = gaps in the chart
  - LoadMore reads only what was added to a file since the last time (live view)
  ============================================================================ }
unit ucsvdata;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, DateUtils;

type
  TRowStatus = (rsOk, rsTagError, rsNoConnection, rsOther);

  TLoadProgress = procedure(Sender: TObject; Done, Total: Int64) of object;

  { one column of the CSV }
  TLogSeries = class
  public
    Name: string;
    Values: array of Single;     // NaN = no value
    MinV, MaxV: Double;          // of all numbers (NaN when there is none)
    NumCount: Int64;             // cells with a number
    IsBool: Boolean;             // only 0 / 1
    Visible: Boolean;
    Color: Cardinal;             // $00BBGGRR (set by the program)
    YLo, YHi: Double;            // own Y range, set with the mouse on its axis
    YManual: Boolean;            // False = automatic Y range
    { display properties (Series window > Properties) }
    Title: string;               // display name ('' = column name)
    LineWidth: Single;           // 0 = default width of the chart
    LineStyle: Integer;          // 0 solid, 1 dash, 2 dot, 3 dash-dot
    DrawMode: Integer;           // 0 auto (BOOL = steps), 1 lines, 2 steps
    PointMode: Integer;          // 0 auto (when zoomed in far), 1 off, 2 always
    PointSize: Single;           // diameter in pixels
    Gain, Offset: Double;        // shown value = value in the file * Gain + Offset
    UnitText: string;            // e.g. kV, shown after the values
    PropsLoaded: Boolean;        // saved properties already applied
    constructor Create;
    function Numeric: Boolean;
    function Caption: string;
    function Scaled(V: Double): Double;
    procedure ScaledMinMax(out Lo, Hi: Double);
    procedure ResetProps;        // display properties back to the defaults
  end;

  { one loaded file }
  TLogFile = class
  public
    FileName: string;
    Pos: Int64;                  // bytes read so far
    Rest: string;                // last line without line end yet
    Map: array of Integer;       // column (from 3) -> series index
  end;

  { TLogData }

  TLogData = class
  private
    FCap: Integer;
    FLastDate: string;
    FLastDay: Double;
    FLastDateRaw: array[0..9] of Char;
    FOnProgress: TLoadProgress;
    procedure Grow(N: Integer);
    function SeriesByName(const AName: string): Integer;
    procedure ParseLine(F: TLogFile; const L: string);
    procedure ParseRaw(F: TLogFile; P: PChar; Len: Integer);
    procedure PutValue(K: Integer; V: Double);
    procedure AddRow(T: Double; St: TRowStatus; F: TLogFile; const Cells: array of string; N: Integer);
  public
    Times: array of Double;      // TDateTime of each row
    Status: array of TRowStatus;
    Count: Integer;
    Series: array of TLogSeries;
    Files: array of TLogFile;
    CurrentFile: string;         // file being read (for a progress display)
    { rows of several files out of order: sort by time (LoadMore does it; after a cancel: call it) }
    procedure SortByTime;
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    { add files (sorted by date in the name / first row) }
    procedure LoadFiles(const Names: array of string);
    { read what was added to the files since the last read; True = new rows }
    function LoadMore: Boolean;
    { first row with Times[i] >= T (Count when none) }
    function IndexAtOrAfter(T: Double): Integer;
    { row nearest to T (-1 when empty) }
    function Nearest(T: Double): Integer;
    function FirstTime: Double;
    function LastTime: Double;
    property OnProgress: TLoadProgress read FOnProgress write FOnProgress;
  end;

{ one CSV cell of the logger -> number (NaN = not a number) }
function ParseLogValue(const S: string): Double;
{ split one CSV line ("..." quoted cells with "" inside); returns the number of cells }
function SplitCsv(const L: string; var Cells: array of string): Integer;
{ date of a file name dd-mm-yyyy.csv (0 when the name has no date) }
function DateOfFileName(const FileName: string): TDateTime;
function FileSize64(const FileName: string): Int64;

implementation

const
  MAX_CELLS = 512;
  { typed Double: an untyped 86400000.0 / 1000.0 is a Single in FPC, and ms of the day
    (up to 86 400 000) do not fit into a Single: times were up to ~8 ms wrong }
  MS_PER_DAY: Double = 86400000;

constructor TLogSeries.Create;
begin
  inherited Create;
  ResetProps;
end;

procedure TLogSeries.ResetProps;
begin
  Title := '';
  LineWidth := 0;
  LineStyle := 0;
  DrawMode := 0;
  PointMode := 0;
  PointSize := 5;
  Gain := 1;
  Offset := 0;
  UnitText := '';
  YManual := False;
end;

function TLogSeries.Numeric: Boolean;
begin
  Result := NumCount > 0;
end;

function TLogSeries.Caption: string;
begin
  if Title <> '' then Result := Title else Result := Name;
end;

function TLogSeries.Scaled(V: Double): Double;
begin
  Result := V * Gain + Offset;
end;

procedure TLogSeries.ScaledMinMax(out Lo, Hi: Double);
begin
  Lo := Scaled(MinV);
  Hi := Scaled(MaxV);
  if Lo > Hi then
  begin
    Hi := Scaled(MinV);           // negative gain
    Lo := Scaled(MaxV);
  end;
end;

{ ------------------------------------------------------------------------ }

function SplitCsv(const L: string; var Cells: array of string): Integer;
var
  I, N, Len: Integer;
  S: string;
begin
  Result := 0;
  Len := Length(L);
  I := 1;
  while (I <= Len + 1) and (Result <= High(Cells)) do
  begin
    if (I <= Len) and (L[I] = '"') then
    begin
      { quoted cell }
      S := '';
      Inc(I);
      while I <= Len do
      begin
        if L[I] = '"' then
        begin
          if (I < Len) and (L[I + 1] = '"') then
          begin
            S := S + '"';
            Inc(I, 2);
            Continue;
          end;
          Inc(I);
          Break;
        end;
        S := S + L[I];
        Inc(I);
      end;
      while (I <= Len) and (L[I] <> ',') do Inc(I);
    end
    else
    begin
      N := I;
      while (I <= Len) and (L[I] <> ',') do Inc(I);
      S := Copy(L, N, I - N);
    end;
    Cells[Result] := S;
    Inc(Result);
    Inc(I);                       // skip the comma
    if I > Len + 1 then Break;
  end;
end;

{ T#1d_2h_3m_4s_500ms -> ms }
function ParseIecTime(const S: string; out Ms: Double): Boolean;
var
  I, J: Integer;
  Neg: Boolean;
  Num: Double;
  U: string;
begin
  Result := False;
  Ms := 0;
  I := 3;                         // after T#
  Neg := (I <= Length(S)) and (S[I] = '-');
  if Neg then Inc(I);
  if I > Length(S) then Exit;
  while I <= Length(S) do
  begin
    if S[I] = '_' then
    begin
      Inc(I);
      Continue;
    end;
    J := I;
    while (I <= Length(S)) and (S[I] in ['0'..'9', '.']) do Inc(I);
    if I = J then Exit;
    Val(Copy(S, J, I - J), Num, J);
    if J <> 0 then Exit;
    J := I;
    while (I <= Length(S)) and (UpCase(S[I]) in ['A'..'Z']) do Inc(I);
    U := LowerCase(Copy(S, J, I - J));
    if U = 'd' then Ms := Ms + Num * 86400000
    else if U = 'h' then Ms := Ms + Num * 3600000
    else if U = 'm' then Ms := Ms + Num * 60000
    else if U = 's' then Ms := Ms + Num * 1000
    else if U = 'ms' then Ms := Ms + Num
    else Exit;
  end;
  if Neg then Ms := -Ms;
  Result := True;
end;

function ParseLogValue(const S: string): Double;
var
  T: string;
  I, Code: Integer;
  Q: QWord;
  H, M, Sec: Integer;
  V: Double;
begin
  Result := NaN;
  if S = '' then Exit;
  { plain number: the usual case first }
  Val(S, V, Code);
  if Code = 0 then Exit(V);
  T := UpperCase(Trim(S));
  if (Copy(T, 1, 3) = '16#') or (Copy(T, 1, 2) = '2#') then
  begin
    Q := 0;
    if T[1] = '1' then
    begin
      for I := 4 to Length(T) do
        case T[I] of
          '0'..'9': Q := Q * 16 + QWord(Ord(T[I]) - 48);
          'A'..'F': Q := Q * 16 + QWord(Ord(T[I]) - 55);
          '_': ;
        else
          Exit;
        end;
    end
    else
      for I := 3 to Length(T) do
        case T[I] of
          '0', '1': Q := Q * 2 + QWord(Ord(T[I]) - 48);
          '_': ;
        else
          Exit;
        end;
    Exit(Q);
  end;
  if (T = 'TRUE') or (T = 'ON') then Exit(1);
  if (T = 'FALSE') or (T = 'OFF') then Exit(0);
  if Copy(T, 1, 2) = 'T#' then
  begin
    if ParseIecTime(T, V) then Result := V;
    Exit;
  end;
  { hh:mm:ss(.zzz) (TOD / TIME as HH:MM:SS.ZZZ) -> ms }
  if (Length(T) >= 8) and (T[3] = ':') and (T[6] = ':') and
    TryStrToInt(Copy(T, 1, 2), H) and TryStrToInt(Copy(T, 4, 2), M) and
    TryStrToInt(Copy(T, 7, 2), Sec) then
  begin
    V := Int64((H * 60 + M) * 60 + Sec) * 1000;
    if (Length(T) > 9) and (T[9] = '.') then
    begin
      Val(Copy(T, 10, 3), I, Code);
      if Code = 0 then V := V + I;
    end;
    Exit(V);
  end;
  { anything else (dates as text, ...) is not drawn }
end;

function DateOfFileName(const FileName: string): TDateTime;
var
  N: string;
  D, M, Y: Integer;
begin
  Result := 0;
  N := ChangeFileExt(ExtractFileName(FileName), '');
  if (Length(N) = 10) and (N[3] = '-') and (N[6] = '-') and TryStrToInt(Copy(N, 1, 2), D) and
    TryStrToInt(Copy(N, 4, 2), M) and TryStrToInt(Copy(N, 7, 4), Y) then
    TryEncodeDate(Y, M, D, Result);
end;

{ ============================== TLogData ================================ }

constructor TLogData.Create;
begin
  inherited Create;
end;

destructor TLogData.Destroy;
begin
  Clear;
  inherited Destroy;
end;

procedure TLogData.Clear;
var
  I: Integer;
begin
  for I := 0 to High(Series) do Series[I].Free;
  for I := 0 to High(Files) do Files[I].Free;
  Series := nil;
  Files := nil;
  Times := nil;
  Status := nil;
  Count := 0;
  FCap := 0;
  FLastDate := '';
  FillChar(FLastDateRaw, SizeOf(FLastDateRaw), 0);
end;

procedure TLogData.Grow(N: Integer);
var
  I, J, Old: Integer;
begin
  if N <= FCap then Exit;
  Old := FCap;
  FCap := Max(N, Max(1024, FCap * 2));
  SetLength(Times, FCap);
  SetLength(Status, FCap);
  for I := 0 to High(Series) do
  begin
    SetLength(Series[I].Values, FCap);
    for J := Old to FCap - 1 do Series[I].Values[J] := NaN;
  end;
end;

function TLogData.SeriesByName(const AName: string): Integer;
var
  S: TLogSeries;
  J: Integer;
begin
  for Result := 0 to High(Series) do
    if Series[Result].Name = AName then Exit;
  S := TLogSeries.Create;
  S.Name := AName;
  S.MinV := NaN;
  S.MaxV := NaN;
  S.IsBool := True;
  S.Visible := True;
  SetLength(S.Values, FCap);
  for J := 0 to FCap - 1 do S.Values[J] := NaN;    // no value in the rows before
  Result := Length(Series);
  SetLength(Series, Result + 1);
  Series[Result] := S;
end;

procedure TLogData.AddRow(T: Double; St: TRowStatus; F: TLogFile; const Cells: array of string; N: Integer);
var
  C, K: Integer;
  V: Double;
  S: TLogSeries;
begin
  if Count >= FCap then Grow(Count + 1);
  Times[Count] := T;
  Status[Count] := St;
  for C := 3 to N - 1 do
  begin
    if C - 3 > High(F.Map) then Break;
    K := F.Map[C - 3];
    if K < 0 then Continue;
    V := ParseLogValue(Cells[C]);
    if not IsNan(V) then PutValue(K, V);
  end;
  Inc(Count);
end;

procedure TLogData.ParseLine(F: TLogFile; const L: string);
var
  Cells: array[0..MAX_CELLS - 1] of string;
  N, I, Y, Mo, D, H, Mi, Se, Ms, Code: Integer;
  T: Double;
  St: TRowStatus;
begin
  if L = '' then Exit;
  N := SplitCsv(L, Cells);
  if N < 3 then Exit;
  if (Cells[0] = 'Date') and (Cells[1] = 'Time') then
  begin
    { header: columns of this part of the file }
    SetLength(F.Map, N - 3);
    for I := 3 to N - 1 do F.Map[I - 3] := SeriesByName(Cells[I]);
    Exit;
  end;
  { yyyy-mm-dd, hh:nn:ss.zzz (fixed positions: fast) }
  if (Length(Cells[0]) <> 10) or (Length(Cells[1]) < 8) then Exit;
  if Cells[0] <> FLastDate then
  begin
    Val(Copy(Cells[0], 1, 4), Y, Code);
    if Code <> 0 then Exit;
    Val(Copy(Cells[0], 6, 2), Mo, Code);
    if Code <> 0 then Exit;
    Val(Copy(Cells[0], 9, 2), D, Code);
    if (Code <> 0) or not TryEncodeDate(Y, Mo, D, TDateTime(FLastDay)) then Exit;
    FLastDate := Cells[0];
    Move(Cells[0][1], FLastDateRaw[0], 10);
  end;
  Val(Copy(Cells[1], 1, 2), H, Code);
  if Code <> 0 then Exit;
  Val(Copy(Cells[1], 4, 2), Mi, Code);
  if Code <> 0 then Exit;
  Val(Copy(Cells[1], 7, 2), Se, Code);
  if Code <> 0 then Exit;
  Ms := 0;
  if Length(Cells[1]) >= 12 then Val(Copy(Cells[1], 10, 3), Ms, Code);
  T := FLastDay + (Int64((H * 60 + Mi) * 60 + Se) * 1000 + Ms) / MS_PER_DAY;
  if Cells[2] = 'OK' then St := rsOk
  else if Cells[2] = 'TAG ERROR' then St := rsTagError
  else if Cells[2] = 'NO CONNECTION' then St := rsNoConnection
  else St := rsOther;
  if Length(F.Map) = 0 then
  begin
    { rows without a header (should not happen): Value1, Value2, ... }
    SetLength(F.Map, N - 3);
    for I := 3 to N - 1 do F.Map[I - 3] := SeriesByName('Value' + IntToStr(I - 2));
  end;
  AddRow(T, St, F, Cells, N);
end;

function FileSize64(const FileName: string): Int64;
var
  SR: TSearchRec;
begin
  Result := 0;
  if FindFirst(FileName, faAnyFile, SR) = 0 then
  begin
    Result := SR.Size;
    FindClose(SR);
  end;
end;

procedure TLogData.PutValue(K: Integer; V: Double);
var
  S: TLogSeries;
begin
  S := Series[K];
  S.Values[Count] := V;
  Inc(S.NumCount);
  if IsNan(S.MinV) or (V < S.MinV) then S.MinV := V;
  if IsNan(S.MaxV) or (V > S.MaxV) then S.MaxV := V;
  if (V <> 0) and (V <> 1) then S.IsBool := False;
end;

{ plain decimal number from P[0..Len-1] (sign, digits, '.', exponent); False = something else }
function FastNumber(P: PChar; Len: Integer; out V: Double): Boolean;
const
  Pow10: array[0..22] of Double = (1, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, 1e10, 1e11,
    1e12, 1e13, 1e14, 1e15, 1e16, 1e17, 1e18, 1e19, 1e20, 1e21, 1e22);
var
  I, Digits, FracDigits, E, ESign: Integer;
  M: Int64;
  Neg, Any: Boolean;
begin
  Result := False;
  I := 0;
  Neg := False;
  if (I < Len) and (P[I] in ['-', '+']) then
  begin
    Neg := P[I] = '-';
    Inc(I);
  end;
  M := 0;
  Digits := 0;
  FracDigits := 0;
  Any := False;
  while (I < Len) and (P[I] in ['0'..'9']) do
  begin
    if Digits < 18 then
    begin
      M := M * 10 + (Ord(P[I]) - 48);
      if M > 0 then Inc(Digits);
    end
    else
      Dec(FracDigits);           // more digits than Int64: scale instead
    Any := True;
    Inc(I);
  end;
  if (I < Len) and (P[I] = '.') then
  begin
    Inc(I);
    while (I < Len) and (P[I] in ['0'..'9']) do
    begin
      if Digits < 18 then
      begin
        M := M * 10 + (Ord(P[I]) - 48);
        if M > 0 then Inc(Digits);
        Inc(FracDigits);
      end;
      Any := True;
      Inc(I);
    end;
  end;
  if not Any then Exit;
  E := 0;
  if (I < Len) and (P[I] in ['e', 'E']) then
  begin
    Inc(I);
    ESign := 1;
    if (I < Len) and (P[I] in ['-', '+']) then
    begin
      if P[I] = '-' then ESign := -1;
      Inc(I);
    end;
    if (I >= Len) or not (P[I] in ['0'..'9']) then Exit;
    while (I < Len) and (P[I] in ['0'..'9']) do
    begin
      E := E * 10 + (Ord(P[I]) - 48);
      Inc(I);
    end;
    E := E * ESign;
  end;
  if I <> Len then Exit;          // e.g. 16#..., T#..., 12:30:00
  E := E - FracDigits;
  V := M;
  if E > 0 then
  begin
    if E <= 22 then V := V * Pow10[E] else V := V * Power(10, E);
  end
  else if E < 0 then
  begin
    if -E <= 22 then V := V / Pow10[-E] else V := V / Power(10, -E);
  end;
  if Neg then V := -V;
  Result := True;
end;

{ one line straight from the read buffer (no strings for the usual data rows) }
procedure TLogData.ParseRaw(F: TLogFile; P: PChar; Len: Integer);
var
  I, C, Start, K, Y, Mo, D, H, Mi, Se, Ms: Integer;
  V: Double;
  St: TRowStatus;
  S: string;

  function Dig(Pos, N: Integer; out R: Integer): Boolean;
  var
    J: Integer;
  begin
    R := 0;
    for J := Pos to Pos + N - 1 do
    begin
      if not (P[J] in ['0'..'9']) then Exit(False);
      R := R * 10 + Ord(P[J]) - 48;
    end;
    Result := True;
  end;

begin
  if Len <= 0 then Exit;
  { header, quoted cells, or anything unusual: the normal way }
  if (Len < 24) or not (P[0] in ['0'..'9']) or (P[4] <> '-') or (P[10] <> ',') or (P[13] <> ':') or
    (Length(F.Map) = 0) or (IndexByte(P^, Len, Ord('"')) >= 0) then
  begin
    SetString(S, P, Len);
    ParseLine(F, S);
    Exit;
  end;
  { date yyyy-mm-dd (the same for many rows: compare only) }
  if CompareByte(P^, FLastDateRaw[0], 10) <> 0 then
  begin
    if not (Dig(0, 4, Y) and Dig(5, 2, Mo) and Dig(8, 2, D)) then Exit;
    if not TryEncodeDate(Y, Mo, D, TDateTime(FLastDay)) then Exit;
    Move(P^, FLastDateRaw[0], 10);
    SetString(FLastDate, P, 10);
  end;
  { time hh:nn:ss.zzz }
  if not (Dig(11, 2, H) and Dig(14, 2, Mi) and Dig(17, 2, Se)) then Exit;
  I := 19;
  Ms := 0;
  if P[I] = '.' then
  begin
    if not Dig(20, 3, Ms) then Exit;
    I := 23;
  end;
  if (I >= Len) or (P[I] <> ',') then Exit;
  Inc(I);
  { status }
  case P[I] of
    'O': St := rsOk;
    'T': St := rsTagError;
    'N': St := rsNoConnection;
  else
    St := rsOther;
  end;
  while (I < Len) and (P[I] <> ',') do Inc(I);
  if Count >= FCap then Grow(Count + 1);
  Times[Count] := FLastDay + (Int64((H * 60 + Mi) * 60 + Se) * 1000 + Ms) / MS_PER_DAY;
  Status[Count] := St;
  { cells }
  C := 0;
  while I < Len do
  begin
    Inc(I);                       // skip the comma
    Start := I;
    while (I < Len) and (P[I] <> ',') do Inc(I);
    if (I > Start) and (C <= High(F.Map)) then
    begin
      K := F.Map[C];
      if K >= 0 then
        if FastNumber(@P[Start], I - Start, V) then
          PutValue(K, V)
        else
        begin
          SetString(S, @P[Start], I - Start);
          V := ParseLogValue(S);
          if not IsNan(V) then PutValue(K, V);
        end;
    end;
    Inc(C);
  end;
  Inc(Count);
end;

function TLogData.LoadMore: Boolean;
const
  CHUNK = 1 shl 20;
var
  K, P, Q, Got: Integer;
  F: TLogFile;
  FS: TFileStream;
  Buf, Line: string;
  Total, Done, Size: Int64;
  Before: Integer;
begin
  Before := Count;
  Total := 0;
  for K := 0 to High(Files) do
    if FileExists(Files[K].FileName) then
      Total := Total + Max(Int64(0), FileSize64(Files[K].FileName) - Files[K].Pos);
  Done := 0;
  for K := 0 to High(Files) do
  begin
    F := Files[K];
    if not FileExists(F.FileName) then Continue;
    CurrentFile := F.FileName;
    { share deny none: the logger may have the file open for writing }
    FS := TFileStream.Create(F.FileName, fmOpenRead or fmShareDenyNone);
    try
      Size := FS.Size;
      if Size < F.Pos then
      begin
        F.Pos := 0;             // file was replaced: read it again from the start
        F.Rest := '';
      end;
      FS.Position := F.Pos;
      SetLength(Buf, CHUNK);
      while FS.Position < Size do
      begin
        Got := FS.Read(Buf[1], Min(CHUNK, Size - FS.Position));
        if Got <= 0 then Break;
        Inc(F.Pos, Got);
        Inc(Done, Got);
        { lines of this chunk; the unfinished last line waits in F.Rest }
        P := 1;
        Q := 1;
        while Q <= Got do
        begin
          if (Buf[Q] = #10) or (Buf[Q] = #13) then
          begin
            if F.Rest <> '' then
            begin
              Line := F.Rest + Copy(Buf, P, Q - P);
              F.Rest := '';
              ParseRaw(F, PChar(Line), Length(Line));
            end
            else if Q > P then
              ParseRaw(F, @Buf[P], Q - P);
            P := Q + 1;
          end;
          Inc(Q);
        end;
        if P <= Got then F.Rest := F.Rest + Copy(Buf, P, Got - P + 1);
        if Assigned(FOnProgress) then FOnProgress(Self, Done, Total);
      end;
    finally
      FS.Free;
    end;
  end;
  SortByTime;
  Result := Count > Before;
end;

{ rows of several files out of order (e.g. opened in any order): sort by time }
procedure TLogData.SortByTime;
var
  I, J, K, N: Integer;
  Sorted: Boolean;
  Idx, Tmp: array of Integer;
  W, Run: Integer;
  T2: array of Double;
  S2: array of TRowStatus;
  V2: array of Single;
begin
  Sorted := True;
  for I := 1 to Count - 1 do
    if Times[I] < Times[I - 1] then
    begin
      Sorted := False;
      Break;
    end;
  if Sorted then Exit;
  { stable merge sort of the row indexes }
  N := Count;
  SetLength(Idx, N);
  SetLength(Tmp, N);
  for I := 0 to N - 1 do Idx[I] := I;
  W := 1;
  while W < N do
  begin
    Run := 0;
    while Run < N do
    begin
      I := Run;
      J := Min(Run + W, N);
      K := Run;
      while (I < Min(Run + W, N)) and (J < Min(Run + 2 * W, N)) do
      begin
        if Times[Idx[J]] < Times[Idx[I]] then
        begin
          Tmp[K] := Idx[J];
          Inc(J);
        end
        else
        begin
          Tmp[K] := Idx[I];
          Inc(I);
        end;
        Inc(K);
      end;
      while I < Min(Run + W, N) do
      begin
        Tmp[K] := Idx[I];
        Inc(I);
        Inc(K);
      end;
      while J < Min(Run + 2 * W, N) do
      begin
        Tmp[K] := Idx[J];
        Inc(J);
        Inc(K);
      end;
      Inc(Run, 2 * W);
    end;
    Idx := Copy(Tmp);
    W := W * 2;
  end;
  SetLength(T2, FCap);
  SetLength(S2, FCap);
  for I := 0 to N - 1 do
  begin
    T2[I] := Times[Idx[I]];
    S2[I] := Status[Idx[I]];
  end;
  Times := T2;
  Status := S2;
  for K := 0 to High(Series) do
  begin
    SetLength(V2, FCap);
    for I := N to FCap - 1 do V2[I] := NaN;
    for I := 0 to N - 1 do V2[I] := Series[K].Values[Idx[I]];
    Series[K].Values := V2;
    V2 := nil;
  end;
end;

procedure TLogData.LoadFiles(const Names: array of string);
var
  L: TStringList;
  I, K: Integer;
  F: TLogFile;
  Known: Boolean;
begin
  { by the date in the name (dd-mm-yyyy.csv), so the days come in order }
  L := TStringList.Create;
  try
    for I := 0 to High(Names) do
      L.AddObject(FormatFloat('00000000', DateOfFileName(Names[I])) + '|' + Names[I], nil);
    L.Sort;
    for I := 0 to L.Count - 1 do
    begin
      Known := False;
      for K := 0 to High(Files) do
        if SameText(Files[K].FileName, Copy(L[I], Pos('|', L[I]) + 1, MaxInt)) then Known := True;
      if Known then Continue;
      F := TLogFile.Create;
      F.FileName := Copy(L[I], Pos('|', L[I]) + 1, MaxInt);
      SetLength(Files, Length(Files) + 1);
      Files[High(Files)] := F;
    end;
  finally
    L.Free;
  end;
  LoadMore;
end;

function TLogData.IndexAtOrAfter(T: Double): Integer;
var
  Lo, Hi, M: Integer;
begin
  Lo := 0;
  Hi := Count;
  while Lo < Hi do
  begin
    M := (Lo + Hi) div 2;
    if Times[M] < T then Lo := M + 1 else Hi := M;
  end;
  Result := Lo;
end;

function TLogData.Nearest(T: Double): Integer;
begin
  if Count = 0 then Exit(-1);
  Result := IndexAtOrAfter(T);
  if Result >= Count then Exit(Count - 1);
  if (Result > 0) and (T - Times[Result - 1] < Times[Result] - T) then Dec(Result);
end;

function TLogData.FirstTime: Double;
begin
  if Count > 0 then Result := Times[0] else Result := Now;
end;

function TLogData.LastTime: Double;
begin
  if Count > 0 then Result := Times[Count - 1] else Result := Now;
end;

end.
