#!/usr/bin/env python3
"""
Page the EU CosIng ingredient inventory out of the EC search API and
write it in the layout ext_cosing_ingredient expects.

    python3 -I data/cosing_ingredients.py data/in/COSING_INGREDIENTS.csv

CosIng has no bulk ingredient export. The search API behind the CosIng
web app has every ingredient, but returns at most 200 per page and
nothing past the 10,000th result. See docs/design-decisions.md.

Standard library only, so it runs anywhere download.sh does.
"""
import csv
import datetime as dt
import json
import math
import os
import sys
import time
import urllib.error
import urllib.request
import uuid

CONFIG_URL = ("https://ec.europa.eu/growth/tools-databases/cosing/"
              "assets/env-json-config.json")
PAGE_SIZE = 200          # the API silently caps anything larger at 200
RESULT_CEILING = 10_000  # page 51 of 200 comes back empty
DATE_FIELD = "esDA_IngestDate"

# (CSV column, API field, byte limit in ext_cosing_ingredient)
COLUMNS = [
    ("cosing_ref_no", "substanceId",         100),
    ("inci_name",     "inciName",            1000),
    ("inn_name",      "innName",             1000),
    ("ph_eur_name",   "phEurName",           1000),
    ("cas_no",        "casNo",               500),
    ("ec_no",         "ecNo",                500),
    ("chem_desc",     "chemicalDescription", 4000),
    ("restriction",   "cosmeticRestriction", 4000),
    ("functions",     "functionName",        2000),
    ("update_date",   None,                  50),   # no source: see design-decisions.md
    ("status",        "status",              50),
]


def log(msg):
    print(msg, file=sys.stderr, flush=True)


def load_endpoint():
    # Read the key from the app's own config rather than hardcoding it,
    # so a rotated key does not break the download.
    with urllib.request.urlopen(CONFIG_URL, timeout=30) as r:
        cfg = json.load(r)
    return cfg["euSearchApiUrl"], cfg["euSearchApiKey"]


def search(endpoint, query, page_number=1, page_size=PAGE_SIZE):
    url, key = endpoint
    full = (f"{url}?apiKey={key}&text=*"
            f"&pageSize={page_size}&pageNumber={page_number}")
    # The API wants the query as a multipart form field, not a JSON body.
    boundary = uuid.uuid4().hex
    body = (f"--{boundary}\r\n"
            'Content-Disposition: form-data; name="query"\r\n'
            "Content-Type: application/json\r\n\r\n"
            f"{json.dumps(query)}\r\n--{boundary}--\r\n").encode()
    req = urllib.request.Request(
        full, data=body, method="POST",
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=90) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            # A 4xx means the query itself is wrong; retrying cannot fix it.
            if e.code < 500 or attempt == 3:
                raise
        except (urllib.error.URLError, TimeoutError):
            if attempt == 3:
                raise
        time.sleep(2 ** (attempt + 1))


def ingredient_query(lo=None, hi=None):
    must = [{"term": {"itemType": "ingredient"}}]
    if lo is not None:
        must.append({"range": {DATE_FIELD: {"gte": fmt(lo), "lt": fmt(hi)}}})
    return {"bool": {"must": must}}


def fmt(ts):
    # Same shape as the stored values, e.g. 2023-05-22T12:59:58.841+0000
    return ts.strftime("%Y-%m-%dT%H:%M:%S.") + f"{ts.microsecond // 1000:03d}+0000"


def windows(endpoint, lo, hi):
    """Yield [lo, hi) ingest-date windows that each fit under the ceiling.

    Halving rather than fixed buckets means nothing needs retuning when
    the EU re-ingests the data on a different day.
    """
    n = search(endpoint, ingredient_query(lo, hi), page_size=1)["totalResults"]
    if n == 0:
        return
    if n <= RESULT_CEILING:
        yield lo, hi, n
        return
    if hi - lo <= dt.timedelta(milliseconds=1):
        raise SystemExit(f"{n} records share ingest time {fmt(lo)}; "
                         "cannot split under the 10,000 ceiling")
    mid = lo + (hi - lo) / 2
    yield from windows(endpoint, lo, mid)
    yield from windows(endpoint, mid, hi)


def field(meta, api_field):
    if api_field is None:
        return ""
    values = meta.get(api_field) or []
    if api_field == "cosmeticRestriction":
        # One annex reference per line ("III/98\r\nV/3"); keep them as
        # separate entries rather than gluing them with a space.
        values = [line for v in values for line in v.splitlines()]
    # Collapse every whitespace run, newlines included: the external
    # table reads one record per line.
    cleaned = [" ".join(str(v).split()) for v in values]
    return "|".join(v for v in cleaned if v)


def main(out_path):
    endpoint = load_endpoint()
    expected = search(endpoint, ingredient_query(), page_size=1)["totalResults"]
    log(f"--> CosIng reports {expected} index documents")

    rows = {}
    fetched = 0
    start = dt.datetime(2000, 1, 1)
    end = dt.datetime.now(dt.timezone.utc).replace(tzinfo=None) + dt.timedelta(days=1)
    for lo, hi, n in windows(endpoint, start, end):
        log(f"    window {fmt(lo)} .. {fmt(hi)}: {n}")
        for page in range(1, math.ceil(n / PAGE_SIZE) + 1):
            results = search(endpoint, ingredient_query(lo, hi), page)["results"]
            for r in results:
                meta = r["metadata"]
                ref = field(meta, "substanceId")
                if not ref.isdigit():
                    raise SystemExit(f"unexpected substanceId {ref!r} for "
                                     f"{field(meta, 'inciName')!r}")
                fetched += 1
                row = [field(meta, api) for _, api, _ in COLUMNS]
                # The index holds some ingredients more than once (indexed
                # twice, seconds apart). Merge copies only when they agree:
                # choosing between two versions of a regulatory record is
                # a business rule, not something to settle here.
                if ref in rows and rows[ref] != row:
                    raise SystemExit(f"substanceId {ref} has copies that "
                                     f"differ; not writing {out_path}")
                rows[ref] = row
            time.sleep(0.2)

    # Compare raw documents, not unique IDs: a shortfall here means paging
    # missed records (no ingest date, or moved windows mid-run). Never
    # write a partial file that looks complete.
    if fetched != expected:
        raise SystemExit(f"fetched {fetched} documents, expected {expected}; "
                         f"not writing {out_path}")
    log(f"    {fetched} index documents -> {len(rows)} ingredients "
        f"({fetched - len(rows)} duplicate copies)")

    for ref, row in rows.items():
        for (col, _, limit), value in zip(COLUMNS, row):
            if len(value.encode("utf-8")) > limit:
                log(f"    WARNING {ref} {col}: {len(value.encode('utf-8'))} "
                    f"bytes > {limit}; Oracle will reject this row")

    part = out_path + ".part"
    with open(part, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(col for col, _, _ in COLUMNS)
        for ref in sorted(rows, key=int):
            w.writerow(rows[ref])
    os.replace(part, out_path)
    log(f"    wrote {len(rows)} rows to {out_path}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: cosing_ingredients.py <out.csv>")
    main(sys.argv[1])
