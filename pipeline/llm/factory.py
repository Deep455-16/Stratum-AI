"""
pipeline/llm/factory.py
------------------------
Hardware-aware LLM backend selector for Stratum AI.

Reads LLM_BACKEND from settings (or env directly) and returns the
appropriate LLMBackend instance.

Modes
-----
auto        Detect Snapdragon/QNN at runtime.
            → If QNNExecutionProvider is available: SnapdragonBackend
            → Otherwise: LlamaBackend  (silent fallback, logged at startup)

llama       Always use llama-cpp-python (Intel/CPU path).

snapdragon  Always attempt SnapdragonBackend.
            → If QNN unavailable or model missing: raises RuntimeError
              with clear, actionable error message.
            → Does NOT silently fall back.

The factory calls backend.load() before returning, so the caller
(server.py startup) receives an already-initialised backend.
"""
from __future__ import annotations

import time
from typing import Any

from pipeline.llm.base import LLMBackend
from pipeline.llm.hardware_detect import detect_hardware, get_summary_line


def get_llm_backend(settings: Any) -> LLMBackend:
    """
    Instantiate, load, and return the appropriate LLMBackend.

    Parameters
    ----------
    settings : module or object with attributes:
        LLM_BACKEND            – "auto" | "llama" | "snapdragon"
        LLM_MODEL_PATH         – path to GGUF model (llama path)
        SNAPDRAGON_MODEL_PATH  – path to ONNX model dir (snapdragon path)
        QNN_BACKEND_TYPE       – "npu" | "gpu" | "cpu"
        N_CTX, N_GPU_LAYERS    – llama-cpp context/GPU settings
        MAX_NEW_TOKENS, LLM_TEMPERATURE, LLM_TOP_P, LLM_REPEAT_PENALTY

    Returns
    -------
    LLMBackend  (already loaded, ready to call .stream())
    """
    mode = getattr(settings, "LLM_BACKEND", "auto").lower().strip()
    hw = detect_hardware()

    # ── Print hardware summary at startup ────────────────────────────────────
    print(f"\n{'='*60}")
    print("  STRATUM AI — LLM Backend Selection")
    print(f"{'='*60}")
    print(f"  {get_summary_line()}")
    print(f"  Requested backend: {mode}")

    backend: LLMBackend

    if mode == "snapdragon":
        # Explicit Snapdragon mode — fail loudly if unavailable
        backend = _build_snapdragon(settings)
        backend.load()

    elif mode == "llama":
        # Explicit llama mode
        backend = _build_llama(settings)
        backend.load()

    else:
        # AUTO: try Snapdragon first, fall back to llama
        if hw["qnn_available"]:
            print("  [auto] QNNExecutionProvider detected → trying Snapdragon backend …")
            try:
                backend = _build_snapdragon(settings)
                backend.load()
                print("  [auto] Snapdragon backend loaded successfully.")
            except Exception as exc:
                print(
                    f"  [auto] Snapdragon backend failed ({exc})\n"
                    "  [auto] Falling back to llama backend …"
                )
                backend = _build_llama(settings)
                backend.load()
        else:
            print(
                "  [auto] QNNExecutionProvider not available -> using llama backend."
            )
            backend = _build_llama(settings)
            backend.load()

    # ── Print final selection ─────────────────────────────────────────────────
    print(f"\n  [OK] Active LLM backend : {backend.backend_name}")
    print(f"  [OK] Model              : {backend.model_name}")
    print(f"  [OK] Runtime            : {backend.runtime_name}")
    print(f"  [OK] Device             : {backend.device_name}")
    print(f"{'='*60}\n")

    return backend


# ── Private helpers ───────────────────────────────────────────────────────────

def _build_llama(settings: Any) -> "LLMBackend":
    from pipeline.llm.llama_backend import LlamaBackend
    return LlamaBackend(
        model_path=str(settings.LLM_MODEL_PATH),
        n_ctx=getattr(settings, "N_CTX", 8192),
        n_gpu_layers=getattr(settings, "N_GPU_LAYERS", -1),
        verbose=False,
    )


def _build_snapdragon(settings: Any) -> "LLMBackend":
    from pipeline.llm.snapdragon_backend import SnapdragonBackend
    return SnapdragonBackend(
        model_path=str(getattr(settings, "SNAPDRAGON_MODEL_PATH", "models/Qwen3-4B-onnx")),
        qnn_backend_type=str(getattr(settings, "QNN_BACKEND_TYPE", "npu")),
        max_tokens=getattr(settings, "MAX_NEW_TOKENS", 512),
    )
