"""Interval math for computing worked hours from an "out of office" calendar.

The model: every hour in the window counts as WORK unless it is covered by an
"Out of office" calendar event. So worked time = window length - merged OOO time.

Everything here operates on naive local wall-clock datetimes. No timezone
conversion happens, which keeps results intuitive (a wall-clock hour is an hour)
and the tests deterministic regardless of the runner's timezone.
"""
import sys
from dataclasses import dataclass, field
from datetime import datetime, timedelta

DEFAULT_OOO_TITLE = "Out of office"
TSV_TIME_FORMAT = "%Y-%m-%d %H:%M"

Interval = tuple  # (datetime start, datetime end)


def extract_ooo_intervals(tsv_text, ooo_title=DEFAULT_OOO_TITLE):
    """Pull OOO intervals out of gcalcli TSV output.

    Columns: start_date, start_time, end_date, end_time, title. All-day events
    (empty time columns) and events whose title is not the OOO title are skipped.
    """
    wanted = ooo_title.strip().lower()
    intervals = []
    for line in tsv_text.splitlines():
        fields = line.split("\t")
        if len(fields) < 5:
            continue
        start_date, start_time, end_date, end_time, title = fields[:5]
        if start_date == "start_date":  # header row
            continue
        if not start_time or not end_time:  # all-day event
            continue
        if title.strip().lower() != wanted:
            continue
        start = datetime.strptime(f"{start_date} {start_time}", TSV_TIME_FORMAT)
        end = datetime.strptime(f"{end_date} {end_time}", TSV_TIME_FORMAT)
        intervals.append((start, end))
    return intervals


def clamp_intervals(intervals, window_start, window_end):
    """Trim each interval to [window_start, window_end]; drop empties."""
    clamped = []
    for start, end in intervals:
        lo = max(start, window_start)
        hi = min(end, window_end)
        if lo < hi:
            clamped.append((lo, hi))
    return clamped


def merge_intervals(intervals):
    """Merge overlapping or touching intervals into a minimal disjoint set."""
    merged = []
    for start, end in sorted(intervals):
        if merged and start <= merged[-1][1]:
            prev_start, prev_end = merged[-1]
            merged[-1] = (prev_start, max(prev_end, end))
        else:
            merged.append((start, end))
    return merged


def overlap_seconds(intervals, lo, hi):
    """Total seconds the (already merged) intervals cover within [lo, hi]."""
    total = 0.0
    for start, end in intervals:
        a = max(start, lo)
        b = min(end, hi)
        if a < b:
            total += (b - a).total_seconds()
    return total


@dataclass
class DayBucket:
    date: object  # datetime.date
    work_seconds: float
    ooo_seconds: float


@dataclass
class WorkHoursResult:
    window_start: datetime
    window_end: datetime
    total_ooo_seconds: float
    days: list = field(default_factory=list)

    @property
    def window_seconds(self):
        return (self.window_end - self.window_start).total_seconds()

    @property
    def total_work_seconds(self):
        return self.window_seconds - self.total_ooo_seconds


def compute(tsv_text, window_start, window_end, ooo_title=DEFAULT_OOO_TITLE):
    """Compute worked/OOO totals plus a per-calendar-day breakdown."""
    merged = merge_intervals(
        clamp_intervals(
            extract_ooo_intervals(tsv_text, ooo_title), window_start, window_end
        )
    )
    total_ooo = overlap_seconds(merged, window_start, window_end)

    days = []
    day = window_start.date()
    last = window_end.date()
    while day <= last:
        midnight = datetime(day.year, day.month, day.day)
        day_start = max(window_start, midnight)
        day_end = min(window_end, midnight + timedelta(days=1))
        if day_start < day_end:
            ooo = overlap_seconds(merged, day_start, day_end)
            span = (day_end - day_start).total_seconds()
            days.append(DayBucket(date=day, work_seconds=span - ooo, ooo_seconds=ooo))
        day += timedelta(days=1)

    return WorkHoursResult(
        window_start=window_start,
        window_end=window_end,
        total_ooo_seconds=total_ooo,
        days=days,
    )


def hours(seconds):
    return seconds / 3600.0


def format_report(result):
    """Render a per-day table with a worked/OOO total footer."""
    width = 35
    lines = [
        f"{'Date':<11} {'Day':<4} {'Worked':>7} {'OOO':>7}",
        "-" * width,
    ]
    for d in result.days:
        lines.append(
            f"{d.date.isoformat():<11} {d.date.strftime('%a'):<4} "
            f"{hours(d.work_seconds):>6.1f}h {hours(d.ooo_seconds):>6.1f}h"
        )
    lines.append("-" * width)

    total_work = hours(result.total_work_seconds)
    span_days = result.window_seconds / 86400.0
    avg = total_work / span_days if span_days else 0.0
    lines.append(
        f"Total worked: {total_work:.1f}h over {span_days:.1f} days "
        f"(avg {avg:.1f}h/day)"
    )
    return "\n".join(lines)


CLI_TIME_FORMAT = "%Y-%m-%d %H:%M:%S"


def main(argv=None, stdin=None):
    """CLI glue: argv = [window_start, window_end] as 'YYYY-MM-DD HH:MM:SS'.

    The TSV from gcalcli is read on stdin. The bash wrapper resolves friendly
    period words (day/week/month) into these concrete bounds.
    """
    argv = list(sys.argv[1:] if argv is None else argv)
    stdin = sys.stdin if stdin is None else stdin
    if len(argv) != 2:
        sys.stderr.write("usage: work_hours.py <start> <end>  (TSV on stdin)\n")
        return 2
    window_start = datetime.strptime(argv[0], CLI_TIME_FORMAT)
    window_end = datetime.strptime(argv[1], CLI_TIME_FORMAT)
    print(format_report(compute(stdin.read(), window_start, window_end)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
