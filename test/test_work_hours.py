"""Tests for the work_hours interval math.

All times are naive local wall-clock; no timezone conversion happens anywhere,
so these tests are deterministic regardless of the runner's TZ.
"""
import os
import sys
import unittest
from datetime import datetime

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "bin"))

import work_hours as wh  # noqa: E402


def dt(s):
    """Parse 'YYYY-MM-DD HH:MM' into a naive datetime."""
    return datetime.strptime(s, "%Y-%m-%d %H:%M")


HEADER = "start_date\tstart_time\tend_date\tend_time\ttitle"


def tsv(*rows):
    return "\n".join([HEADER, *rows]) + "\n"


class ExtractOooIntervals(unittest.TestCase):
    def test_skips_all_day_events(self):
        # All-day "Home" rows have empty time columns and must be ignored.
        text = tsv("2026-05-26\t\t2026-05-27\t\tHome")
        self.assertEqual(wh.extract_ooo_intervals(text), [])

    def test_skips_non_ooo_timed_events(self):
        text = tsv("2026-05-26\t11:00\t2026-05-26\t11:30\tJeff / Josh")
        self.assertEqual(wh.extract_ooo_intervals(text), [])

    def test_matches_ooo_title(self):
        text = tsv("2026-05-27\t16:30\t2026-05-27\t17:30\tOut of office")
        self.assertEqual(
            wh.extract_ooo_intervals(text),
            [(dt("2026-05-27 16:30"), dt("2026-05-27 17:30"))],
        )

    def test_title_match_is_case_insensitive_and_trims(self):
        text = tsv("2026-05-27\t16:30\t2026-05-27\t17:30\t  OUT OF OFFICE ")
        self.assertEqual(
            wh.extract_ooo_intervals(text),
            [(dt("2026-05-27 16:30"), dt("2026-05-27 17:30"))],
        )

    def test_handles_midnight_crossing_event(self):
        text = tsv("2026-05-29\t22:15\t2026-05-30\t00:00\tOut of office")
        self.assertEqual(
            wh.extract_ooo_intervals(text),
            [(dt("2026-05-29 22:15"), dt("2026-05-30 00:00"))],
        )


class MergeIntervals(unittest.TestCase):
    def test_merges_overlapping(self):
        # OOO laid over a meeting at the same time -> one block, not double.
        intervals = [
            (dt("2026-05-29 13:00"), dt("2026-05-29 13:15")),
            (dt("2026-05-29 13:00"), dt("2026-05-29 13:15")),
        ]
        self.assertEqual(
            wh.merge_intervals(intervals),
            [(dt("2026-05-29 13:00"), dt("2026-05-29 13:15"))],
        )

    def test_merges_adjacent(self):
        intervals = [
            (dt("2026-05-29 22:15"), dt("2026-05-30 00:00")),
            (dt("2026-05-30 00:00"), dt("2026-05-30 11:30")),
        ]
        self.assertEqual(
            wh.merge_intervals(intervals),
            [(dt("2026-05-29 22:15"), dt("2026-05-30 11:30"))],
        )

    def test_keeps_disjoint_separate(self):
        intervals = [
            (dt("2026-05-29 10:45"), dt("2026-05-29 11:00")),
            (dt("2026-05-29 14:45"), dt("2026-05-29 15:00")),
        ]
        self.assertEqual(wh.merge_intervals(intervals), intervals)

    def test_sorts_unordered_input(self):
        intervals = [
            (dt("2026-05-29 14:45"), dt("2026-05-29 15:00")),
            (dt("2026-05-29 10:45"), dt("2026-05-29 11:00")),
        ]
        self.assertEqual(
            wh.merge_intervals(intervals),
            [
                (dt("2026-05-29 10:45"), dt("2026-05-29 11:00")),
                (dt("2026-05-29 14:45"), dt("2026-05-29 15:00")),
            ],
        )


class ClampIntervals(unittest.TestCase):
    def test_trims_interval_overrunning_window_end(self):
        # 13:00->24:00 OOO but window ends 14:00 -> only one hour counts.
        intervals = [(dt("2026-05-30 13:00"), dt("2026-05-31 00:00"))]
        clamped = wh.clamp_intervals(
            intervals, dt("2026-05-23 14:00"), dt("2026-05-30 14:00")
        )
        self.assertEqual(clamped, [(dt("2026-05-30 13:00"), dt("2026-05-30 14:00"))])

    def test_drops_interval_entirely_outside_window(self):
        intervals = [(dt("2026-05-20 08:00"), dt("2026-05-20 09:00"))]
        clamped = wh.clamp_intervals(
            intervals, dt("2026-05-23 14:00"), dt("2026-05-30 14:00")
        )
        self.assertEqual(clamped, [])

    def test_trims_interval_starting_before_window(self):
        intervals = [(dt("2026-05-23 12:00"), dt("2026-05-23 16:00"))]
        clamped = wh.clamp_intervals(
            intervals, dt("2026-05-23 14:00"), dt("2026-05-30 14:00")
        )
        self.assertEqual(clamped, [(dt("2026-05-23 14:00"), dt("2026-05-23 16:00"))])


class Compute(unittest.TestCase):
    def test_total_work_is_window_minus_ooo(self):
        # 48h window, 10h of OOO -> 38h work.
        text = tsv(
            "2026-05-28\t\t2026-05-29\t\tHome",  # all-day, ignored
            "2026-05-28\t00:00\t2026-05-28\t08:00\tOut of office",  # 8h
            "2026-05-28\t12:00\t2026-05-28\t14:00\tBusiness Sync",  # not OOO
            "2026-05-29\t06:00\t2026-05-29\t08:00\tOut of office",  # 2h
        )
        result = wh.compute(text, dt("2026-05-28 00:00"), dt("2026-05-30 00:00"))
        self.assertEqual(result.window_seconds, 48 * 3600)
        self.assertEqual(result.total_ooo_seconds, 10 * 3600)
        self.assertEqual(result.total_work_seconds, 38 * 3600)

    def test_daily_breakdown_buckets_by_calendar_day(self):
        text = tsv(
            "2026-05-28\t00:00\t2026-05-28\t08:00\tOut of office",  # 8h on 5/28
            "2026-05-29\t06:00\t2026-05-29\t08:00\tOut of office",  # 2h on 5/29
        )
        result = wh.compute(text, dt("2026-05-28 00:00"), dt("2026-05-30 00:00"))
        days = {d.date: d for d in result.days}
        self.assertEqual(days[dt("2026-05-28 00:00").date()].ooo_seconds, 8 * 3600)
        self.assertEqual(days[dt("2026-05-28 00:00").date()].work_seconds, 16 * 3600)
        self.assertEqual(days[dt("2026-05-29 00:00").date()].ooo_seconds, 2 * 3600)
        self.assertEqual(days[dt("2026-05-29 00:00").date()].work_seconds, 22 * 3600)

    def test_midnight_crossing_ooo_splits_across_days(self):
        # 22:15->next-day 11:30 sleep block straddles midnight.
        text = tsv("2026-05-29\t22:15\t2026-05-30\t11:30\tOut of office")
        result = wh.compute(text, dt("2026-05-29 00:00"), dt("2026-05-31 00:00"))
        days = {d.date: d for d in result.days}
        # 5/29: 22:15->24:00 = 1h45m = 6300s
        self.assertEqual(days[dt("2026-05-29 00:00").date()].ooo_seconds, 6300)
        # 5/30: 00:00->11:30 = 11h30m = 41400s
        self.assertEqual(days[dt("2026-05-30 00:00").date()].ooo_seconds, 41400)

    def test_partial_first_and_last_day_window(self):
        # Window from 5/28 14:00 to 5/30 10:00, no OOO at all.
        text = tsv()
        result = wh.compute(text, dt("2026-05-28 14:00"), dt("2026-05-30 10:00"))
        days = {d.date: d for d in result.days}
        # First day: 14:00->24:00 = 10h, all work
        self.assertEqual(days[dt("2026-05-28 00:00").date()].work_seconds, 10 * 3600)
        # Last day: 00:00->10:00 = 10h, all work
        self.assertEqual(days[dt("2026-05-30 00:00").date()].work_seconds, 10 * 3600)
        # Total = 44h
        self.assertEqual(result.total_work_seconds, 44 * 3600)


class FormatReport(unittest.TestCase):
    def build(self):
        text = tsv(
            "2026-05-28\t00:00\t2026-05-28\t08:00\tOut of office",  # 8h ooo, 16h work
            "2026-05-29\t06:00\t2026-05-29\t08:00\tOut of office",  # 2h ooo, 22h work
        )
        return wh.compute(text, dt("2026-05-28 00:00"), dt("2026-05-30 00:00"))

    def test_has_a_row_per_day_with_date_weekday_and_hours(self):
        report = wh.format_report(self.build())
        self.assertIn("2026-05-28", report)
        self.assertIn("Thu", report)  # 2026-05-28 is a Thursday
        self.assertIn("16.0", report)  # worked hours that day
        self.assertIn("8.0", report)  # ooo hours that day
        self.assertIn("2026-05-29", report)
        self.assertIn("Fri", report)

    def test_footer_has_total_and_average(self):
        report = wh.format_report(self.build())
        self.assertIn("Total worked: 38.0h", report)
        self.assertIn("over 2.0 days", report)
        self.assertIn("avg 19.0h/day", report)


if __name__ == "__main__":
    unittest.main()
