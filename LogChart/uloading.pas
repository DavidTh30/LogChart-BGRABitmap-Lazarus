{ ============================================================================
  uloading - small "Loading" window of LogChart (uloading.lfm)
    - spinner animation (BGRABitmap), file name, progress bar
    - how much is done: MB of MB (or rows of rows), %, rows read, time, time left
    - Cancel: the caller stops (rows read so far stay)
  The caller does the work and calls Progress(...) now and then; Progress also
  lets the window repaint (the work runs in the main thread).
  ============================================================================ }
unit uloading;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls, ComCtrls, Math, FileCtrl,
  BGRABitmap, BGRABitmapTypes;

type

  { TLoadingForm }

  TLoadingForm = class(TForm)
    Bar: TProgressBar;
    BtnCancel: TButton;
    LabelFile: TLabel;
    LabelInfo: TLabel;
    LabelTitle: TLabel;
    PaintSpin: TPaintBox;
    procedure BtnCancelClick(Sender: TObject);
    procedure PaintSpinPaint(Sender: TObject);
  private
    FT0: QWord;
    FLastPaint: QWord;
  public
    Cancelled: Boolean;
    { AsBytes: Done / Total are bytes (reading), else rows (saving) }
    procedure Start(const ATitle: string; ACaption: string);
    procedure Progress(const AFile: string; Done, Total: Int64; Rows: Int64; AsBytes: Boolean);
  end;

implementation

{$R *.lfm}

var
  NumFmt: TFormatSettings;

procedure TLoadingForm.Start(const ATitle: string; ACaption: string);
begin
  Caption := ACaption;
  LabelTitle.Caption := ATitle;
  LabelFile.Caption := '';
  LabelInfo.Caption := '';
  Bar.Position := 0;
  Cancelled := False;
  FT0 := GetTickCount64;
  FLastPaint := 0;
end;

procedure TLoadingForm.BtnCancelClick(Sender: TObject);
begin
  Cancelled := True;
  BtnCancel.Enabled := False;
  LabelTitle.Caption := 'Stopping ...';
end;

{ 12 spokes, the bright one turns around (time based) }
procedure TLoadingForm.PaintSpinPaint(Sender: TObject);
var
  B: TBGRABitmap;
  I, Head: Integer;
  A, CX, CY, R1, R2: Single;
  Alpha: Byte;
begin
  { transparent: the window shows through (clDefault as colour gave a black square) }
  B := TBGRABitmap.Create(PaintSpin.Width, PaintSpin.Height, BGRAPixelTransparent);
  try
    CX := B.Width / 2;
    CY := B.Height / 2;
    R1 := B.Width * 0.22;
    R2 := B.Width * 0.44;
    Head := (GetTickCount64 div 70) mod 12;
    for I := 0 to 11 do
    begin
      A := I * Pi / 6;
      Alpha := 40 + ((I - Head + 12) mod 12) * 215 div 11;
      B.DrawLineAntialias(CX + R1 * Sin(A), CY - R1 * Cos(A), CX + R2 * Sin(A), CY - R2 * Cos(A),
        BGRA(40, 120, 220, Alpha), 4.5);
    end;
    B.Draw(PaintSpin.Canvas, 0, 0, False);     // False = blend onto the background
  finally
    B.Free;
  end;
end;

procedure TLoadingForm.Progress(const AFile: string; Done, Total: Int64; Rows: Int64; AsBytes: Boolean);
var
  Sec, Remain: Double;
  S: string;
begin
  if GetTickCount64 - FLastPaint < 40 then Exit;      // ~25 pictures per second
  FLastPaint := GetTickCount64;
  if AFile <> '' then LabelFile.Caption := MinimizeName(AFile, LabelFile.Canvas, LabelFile.Width);
  if Total > 0 then Bar.Position := Min(1000, Done * 1000 div Total);
  Sec := (GetTickCount64 - FT0) / 1000;
  if AsBytes then
    S := Format('%.1f of %.1f MB   %d %%', [Done / 1048576, Total / 1048576, Done * 100 div Max(Int64(1), Total)], NumFmt)
  else
    S := Format('%.0n of %.0n rows   %d %%', [Done * 1.0, Total * 1.0, Done * 100 div Max(Int64(1), Total)], NumFmt);
  S := S + LineEnding + Format('%.0n rows   %.1f s', [Rows * 1.0, Sec], NumFmt);
  if (Done > 0) and (Total > Done) and (Sec > 0.5) then
  begin
    Remain := Sec * (Total - Done) / Done;
    S := S + Format('   about %.0f s left', [Remain], NumFmt);
  end;
  LabelInfo.Caption := S;
  PaintSpin.Invalidate;
  Application.ProcessMessages;
end;

initialization
  NumFmt := DefaultFormatSettings;
  NumFmt.DecimalSeparator := '.';
  NumFmt.ThousandSeparator := ',';
end.
