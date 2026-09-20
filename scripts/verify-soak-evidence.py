#!/usr/bin/env python3
"""Validate the process samples collected by run-eight-hour-soak.sh."""

import argparse
import csv
import json
import math
import statistics
from pathlib import Path


def verify(path: Path, minimum_duration: int = 8 * 60 * 60) -> dict:
    with path.open(newline="", encoding="utf-8") as stream:
        reader = csv.DictReader(stream)
        required = {"epoch", "pid", "cpu", "rss_kb", "identity", "db_open", "responsive"}
        if not required.issubset(reader.fieldnames or []):
            raise ValueError("process sample columns are incomplete")
        samples = list(reader)

    if len(samples) < 3:
        raise ValueError("too few process samples")
    times = [int(sample["epoch"]) for sample in samples]
    if times[-1] - times[0] < minimum_duration:
        raise ValueError("soak duration is shorter than eight hours")
    if any(later <= earlier or later - earlier > 90 for earlier, later in zip(times, times[1:])):
        raise ValueError("process samples are missing or out of order")
    if len({sample["pid"] for sample in samples}) != 1:
        raise ValueError("sampled process changed")
    if any(
        sample[field] != "1"
        for sample in samples
        for field in ("identity", "db_open", "responsive")
    ):
        raise ValueError("process identity, database ownership, or responsiveness failed")

    cpus = [float(sample["cpu"]) for sample in samples]
    rss_values = [int(sample["rss_kb"]) for sample in samples]
    if any(not math.isfinite(cpu) or cpu < 0 for cpu in cpus) or any(rss <= 0 for rss in rss_values):
        raise ValueError("invalid CPU or RSS sample")

    median_cpu = statistics.median(cpus)
    median_rss = statistics.median(rss_values)
    first_rss = statistics.median(
        rss for time, rss in zip(times, rss_values) if time <= times[0] + 600
    )
    last_rss = statistics.median(
        rss for time, rss in zip(times, rss_values) if time >= times[-1] - 600
    )
    rss_growth = (last_rss - first_rss) / first_rss
    if median_cpu >= 1 or median_rss >= 75 * 1024 or rss_growth >= 0.10:
        raise ValueError(
            f"soak budget exceeded: CPU={median_cpu:.3f}%, "
            f"RSS={median_rss:.0f} KiB, growth={rss_growth:.3%}"
        )
    return {
        "duration_seconds": times[-1] - times[0],
        "sample_count": len(samples),
        "median_cpu_percent": median_cpu,
        "median_rss_kib": median_rss,
        "rss_growth_fraction": rss_growth,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("samples", type=Path)
    args = parser.parse_args()
    try:
        print(json.dumps(verify(args.samples), sort_keys=True))
    except (OSError, ValueError, TypeError) as error:
        parser.exit(1, f"soak gate: {error}\n")


if __name__ == "__main__":
    main()
