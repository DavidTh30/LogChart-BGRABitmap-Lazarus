# LogChart

A Lazarus program (normal forms, `.lfm`) that shows the **CSV files of the PLC Data Logger** as a chart. The chart is drawn with **BGRABitmap** (antialiased).

- **Main window:** menu + chart + status bar. All commands are in the menu (no tool bar).
- **Series window:** a separate window with the series list and statistics. **View > Series window** (F9) shows / hides it.

| Feature | How |
|---|---|
| Open | **File > Open...** (select several days at once), **Add files...** (e.g. the next day), **Open folder** (all days of a month folder `mm-yyyy`), drag & drop onto the window, or `LogChart.exe file.csv` |
| Loading window | for files over 2 MB: spinner, file name, progress bar, **MB of MB, %, rows, time, time left**, **Cancel** (the rows read so far stay). The main window waits meanwhile. Example: 134.9 MB / 3,000,000 rows in about 4.5 s |
| Snapshot to CSV | **File > Snapshot to CSV...** (Shift+Ctrl+S): the **visible time range** of the **shown series** as a new CSV in the logger format (opens again in LogChart). Header = display name [unit], values with gain / offset as in the chart (7 digits), status column kept. Big snapshots show the same progress window. 1,000,000 rows in about 4.5 s |
| Order | days are put together by the date in the name (`dd-mm-yyyy.csv`) and the time of each row |
| Columns | joined by name. When the logger's tag list changed (new header line in the file), a column missing in one part simply has no value there |
| Value formats | every display format of the logger: numbers, `16#..` (HEX), `2#..` (BIN), `TRUE/FALSE`, `ON/OFF`, `T#1h_2m_3s` (TIME → ms), `hh:mm:ss.zzz` (TOD → ms). Text such as dates is shown as `(text)` and not drawn |
| Gaps | empty cells and **NO CONNECTION** rows break the line; NO CONNECTION also gives red marks on the time axis |
| Lanes | every series in its own strip with its **own scale** (default) |
| One plot, own Y axes | untick *Lanes*: all series in one plot, but **every series keeps its own, independent Y axis**, all on the **left**, side by side, each only as **wide as its numbers** (the first series next to the plot). Axes in the series colours, no names on the chart (the colours of the series list and the cursor box tell them). The grid follows the first series |
| Y axis with the mouse | on any Y axis (lanes too; the axis turns light in the series colour): **drag** up / down = offset, **wheel** = zoom only this axis around the mouse, **double-click** = this axis automatic again. **Auto Y** (Ctrl+R) = all axes automatic. The setting of an axis stays when you switch Lanes on / off |
| BOOL | columns with only 0 / 1 are drawn as steps with the labels 0 / 1 |
| Y fit to view | Y scale from the visible part only (instead of the whole file) |
| Cursor | move the mouse: time of the nearest row plus all values (`---` = no value) |
| Series properties | Series window, tab **Properties** (used at once, kept per column name in `LogChart.ini`): column, type, number of values, range in the file; **display name**, show, **colour**, **line width** (0 = chart default), **line style** (solid / dash / dot / dash-dot), **draw as** (auto: BOOL = steps / lines / steps), **points** (auto / off / always + size), **gain / offset / unit** (shown value = file value × gain + offset, also in the axes, value box and statistics), **Y axis** automatic or min / max, *Default settings* |
| Statistics | tab **Statistics**: min / max (with time), average, std. deviation, span, first / last value (with time), number of values, of the selected series in the **visible** range |
| Start view | after opening, the chart shows the **last 1000 rows** (the newest; Chart properties > Data & export, 0 = whole file). **Whole file**: Ctrl+Home or double-click |
| Zoom box | **left drag** (default; *View > Left drag = zoom box*, Ctrl+B switches it with right drag): a frame; the time zooms to its width, the Y axes to its height (one plot: all series; lanes: the lane the frame is in). **Zoom back** Ctrl+Z / Backspace (50 steps, time and Y axes) |
| Chart properties | **View > Chart properties...** (F12): colours (Light / Dark theme), font, size of the axis numbers (default 8 px) and of names / value box, grid lines, time format, date line, default line width (1), lanes (names, gap), left drag (zoom box / move), wheel step, value box, crosshair, NO CONNECTION marks, live interval, rows after loading (1000), PNG / copy size. *Apply* shows it at once, *Cancel* goes back. Kept in `LogChart.ini [Chart]` |
| Live | **F6** or the *Live* box: reads the new rows of the file every second (only the new bytes). If the view shows the end, it follows the end |
| Picture | **Export PNG...** (Ctrl+E), **Copy chart** (Ctrl+Shift+C) to paste into Word / Excel / Paint |
| Settings | `LogChart.ini` next to the exe (last folder, Lanes, Y fit, Points). The first time it opens in `..\Logs` (the logger's folder) |

## Mouse and keys

| Action | Result |
|---|---|
| mouse wheel | zoom the time axis around the mouse |
| left drag in the plot | zoom box (time + Y to the frame). The box starts only in the plot and stays inside it (never over the axes) |
| right drag / Shift + left / middle | move along the time axis in the plot. **On the time axis: left or right drag** moves the time (cursor ↔ there; no zoom box on the axes) |
| Ctrl+Z / Backspace | zoom back |
| double-click on the plot | whole file, all Y axes automatic |
| on a Y axis: drag / wheel / double-click | offset / zoom of that series / automatic again |
| chart focused: `Home` `+` `-` `←` `→` | whole file, zoom, move |
| `Ctrl+Home`, `Ctrl++`, `Ctrl+-` | whole file, zoom (from anywhere) |
| series window | **check box** = show / hide (series and its axis); double-click = only this series; **All / None**. It is a window of its own (View > Series window, F9). It stays above the main window, closing it only hides it, and the menu shortcuts work in it too. Position, size and visible are kept in `LogChart.ini` |
| `F5` / `F6` | reload / live |

## Speed

- **Reading:** data rows are parsed straight from the read buffer (date, time and numbers without string copies). Only headers, quoted cells and special formats take the slow path.
  - 1,000,000 rows (47.5 MB, 10 ms logging for 2.8 h): **1.45 s** (before this optimization: 8.2 s)
- **Drawing:** when there are more rows than pixels, every pixel column draws only min..max (one vertical line + a short line to the next column), so a million rows draw as fast as a thousand. Solid lines are drawn segment by segment (a wide polyline with thousands of joins was 20× slower); dash / dot styles use one polyline so the pattern runs on.
  - live log, 8,700 rows, 7 series that swing 0..5000 in every pixel column: 46 ms (lanes) / 110 ms (one plot); 1,000,000 rows: 125 ms
- **Cursor:** the chart is kept in a cache, moving the mouse only draws the cursor and value box on top. When zoomed in far, the real lines are drawn, plus dots when there are only a few rows.
- **Memory:** values as `Single` (4 bytes), time as `Double`: 1 million rows × 5 columns ≈ 30 MB.

## Files

| File | What |
|---|---|
| `LogChart.lpi / .lpr` | project (packages: `LCL`, `BGRABitmapPack`), optimization `-O2`, no debug info |
| `umain.pas / .lfm` | main window: menus, chart, status bar, live timer; fills and handles the series window |
| `useries.pas / .lfm` | series window: check list, All / None, tabs Properties (editors) and Statistics; forwards the menu shortcuts |
| `tests/rendertest.lpi` | draws a CSV into a PNG and prints the time (`rendertest file.csv out.png lanes|overlay`) |
| `tests/zoomtest.lpi` | zooms the time axis from 60 s down to 4 ms in all modes and prints every drawing error (`zoomtest file.csv`): 176 drawings, 0 errors |
| `uchart.pas` | `TLogChart` (`TCustomControl`): `TChartOptions`, time axis, lanes / one plot with one Y axis per series, Y axis drag / zoom, zoom box + history, min-max drawing, cursor, `RenderTo` for PNG. The chart is drawn into a cache; moving the mouse only draws the cursor on top |
| `uchartprops.pas / .lfm` | Chart properties window |
| `uloading.pas / .lfm` | Loading / saving window (spinner drawn with BGRABitmap, progress, Cancel) |
| `ucsvdata.pas` | `TLogData`: CSV reader (fast path, headers, formats, several files, `LoadMore` for live) |
| `tests/testcsv.lpr` | 28 console tests: time stamps exact to the ms all day, all value formats, quoted names, 2 files in any order, NO CONNECTION, header change, unfinished last line + live append; optional big file timing |

## Tests that were run

| Test | Result |
|---|---|
| `tests/testcsv` | 28 / 28 OK |
| 1,000,000 rows (sine, BOOL ON/OFF, HEX word, counter, NO CONNECTION gap, header change in the middle) | read in 1.45 s; chart, zoom with the wheel down to the gap, cursor readout, statistics OK |
| Live against the CSV the DataLogger writes at the moment | new rows every second, the view follows the end |
| Export PNG | 112 KB picture, the same chart without cursor |
| One plot, 7 series (live log) | 7 independent Y axes, all left, compact (BOOL axes narrow); unticking Tag7 removes its line and axis; wheel + drag on the Tag7 and Tag6 axes separate the two curves; double-click puts Tag7 back to automatic; in Lanes the wheel on the Heartbeat axis zooms only that lane |

## Fixed

- **Hang when zoomed in to about 20 rows or fewer** (time step 1 s or smaller): `Math.Ceil` returns a 32-bit Integer, and time-in-ms / step (about 4·10⁹) overflowed. The time axis then started weeks too early and drew millions of labels. Now a 64-bit-safe `CeilD` is used (time axis and Y ticks), every tick loop has a limit, and a drawing error is shown in the chart instead of error dialogs that come back at every repaint.

- **Time stamps were up to ~8 ms wrong** (late in the day): `(...)*1000.0 / 86400000.0` was computed in Single precision (FPC types these constants as Single). Now Int64 ms / a typed Double constant: exact to < 0.001 ms (test in `testcsv`).

## Build

```bash
C:\lazarus\lazbuild.exe DataLogger\LogChart\LogChart.lpi
```

```bash
fpc -Mobjfpc -Sh -O2 -FuDataLogger\LogChart DataLogger\LogChart\tests\testcsv.lpr
```
