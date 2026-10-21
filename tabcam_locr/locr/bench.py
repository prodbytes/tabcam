"""Measures the reading on pages already in the bucket, writing nothing:
a temporary Lambda function from the image (handler locr.bench.handler,
the ocr function's role), with the settings to compare in its
environment (LOCR_MKLDNN, LOCR_CPU_THREADS, and its memory).

    {"keys": ["<identity>/events/<event>/<page>.pdf", ...]}
    -> {"load": s, "pages": [{"key", "seconds", "timings", "text"}], ...}
"""
import os
import time
import traceback

from . import keys
from .handler import services


def handler(event, context=None):
    from . import engines, pipeline
    out = {"mkldnn": os.environ.get("LOCR_MKLDNN") == "1",
           "threads": os.environ.get("LOCR_CPU_THREADS"),
           "cpus": os.cpu_count(), "pages": []}
    t = time.monotonic()
    try:
        engines._paddle()
        engines._rapid()
    except Exception as e:
        out["error"] = f"{type(e).__name__}: {e}"
        out["trace"] = traceback.format_exc()[-2000:]
        return out
    out["load"] = round(time.monotonic() - t, 2)
    for key in event.get("keys", []):
        page = keys.parse_page(key)
        if page is None:
            continue
        data = services.s3.get_object(Bucket=services.bucket, Key=page.key)["Body"].read()
        read = pipeline.transcribe_pdf if page.is_pdf else pipeline.transcribe
        t = time.monotonic()
        try:
            r = read(data, engines.default(), read_page=engines.read_page,
                     read_crop=engines.read_crop)
            out["pages"].append({"key": key, "seconds": round(time.monotonic() - t, 2),
                                 "timings": r.timings, "text": r.text})
        except Exception as e:
            out["pages"].append({"key": key, "error": f"{type(e).__name__}: {e}",
                                 "trace": traceback.format_exc()[-2000:]})
    return out
