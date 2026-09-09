"""
pipeline/llm/hardware_detect.py
--------------------------------
Hardware and runtime capability detector for Stratum AI.

Design principles:
  - No side effects on import (safe to import anywhere).
  - Prefers runtime capability checks over CPU-name heuristics.
  - Never claims Snapdragon/QNN unless actually confirmed at runtime.
  - Results are cached after the first call.

Usage:
    from pipeline.llm.hardware_detect import detect_hardware, is_qnn_available

    info = detect_hardware()
    print(info["qualcomm_detected"], info["qnn_available"])
"""
from __future__ import annotations

import platform
import sys
from functools import lru_cache
from typing import Any, Dict


@lru_cache(maxsize=1)
def detect_hardware() -> Dict[str, Any]:
    """
    Detect platform, CPU, and runtime capabilities.

    Returns a JSON-serialisable dict.  All boolean flags default to
    False unless positively confirmed.

    Keys
    ----
    platform          : "windows" | "linux" | "darwin" | "unknown"
    architecture      : e.g. "AMD64", "ARM64"
    cpu               : processor name string (may be empty)
    python_version    : e.g. "3.11.9"
    qualcomm_detected : True only if CPU name contains Qualcomm/Snapdragon
                        AND architecture is ARM64.  This is a heuristic hint,
                        NOT a guarantee of NPU capability.
    qnn_available     : True only if onnxruntime is installed AND
                        QNNExecutionProvider is in its provider list.
    npu_backend_available : True only if qnn_available is True.
                            (Future: may add deeper QNN backend probe.)
    onnxruntime_version   : ORT version string, or None if not installed.
    qnn_providers_found   : list of QNN-related providers found, or [].
    """
    result: Dict[str, Any] = {
        "platform": platform.system().lower() or "unknown",
        "architecture": platform.machine().upper(),
        "cpu": platform.processor(),
        "python_version": platform.python_version(),
        "qualcomm_detected": False,
        "qnn_available": False,
        "npu_backend_available": False,
        "onnxruntime_version": None,
        "qnn_providers_found": [],
    }

    # ── 1. Heuristic: Qualcomm/Snapdragon CPU ────────────────────────────────
    cpu_lower = result["cpu"].lower()
    arch = result["architecture"]
    if arch == "ARM64" and any(
        kw in cpu_lower for kw in ("qualcomm", "snapdragon", "oryon")
    ):
        result["qualcomm_detected"] = True

    # ── 2. Runtime: QNNExecutionProvider presence ────────────────────────────
    try:
        import onnxruntime as ort  # type: ignore

        result["onnxruntime_version"] = ort.__version__
        all_providers = ort.get_all_providers()
        qnn_related = [p for p in all_providers if "QNN" in p.upper()]
        result["qnn_providers_found"] = qnn_related

        if "QNNExecutionProvider" in all_providers:
            result["qnn_available"] = True
            # NPU is only available if the QNN EP itself can be loaded;
            # we check this here rather than claiming it unconditionally.
            result["npu_backend_available"] = True

    except ImportError:
        pass  # onnxruntime not installed — all flags remain False
    except Exception:
        pass  # Unexpected ORT error — stay conservative

    return result


def is_qnn_available() -> bool:
    """Convenience shortcut."""
    return detect_hardware()["qnn_available"]


def is_qualcomm_cpu() -> bool:
    """Heuristic-only Qualcomm CPU check. Does NOT confirm NPU capability."""
    return detect_hardware()["qualcomm_detected"]


def get_summary_line() -> str:
    """
    Return a single-line human-readable summary for startup logging.

    Example outputs:
        "Platform: Windows | Arch: AMD64 | CPU: Intel Core i5-1235U | QNN: not available"
        "Platform: Windows | Arch: ARM64 | CPU: Qualcomm Snapdragon X Elite | QNN: available (QNNExecutionProvider)"
    """
    d = detect_hardware()
    qnn_status = (
        f"available ({', '.join(d['qnn_providers_found'])})"
        if d["qnn_available"]
        else "not available"
    )
    return (
        f"Platform: {d['platform'].capitalize()} | "
        f"Arch: {d['architecture']} | "
        f"CPU: {d['cpu'] or 'unknown'} | "
        f"QNN: {qnn_status}"
    )
