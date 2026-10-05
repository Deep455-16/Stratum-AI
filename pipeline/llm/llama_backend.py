"""
pipeline/llm/llama_backend.py
------------------------------
llama-cpp-python backend for Stratum AI (Intel / CPU path).

This is the existing Qwen2.5-3B GGUF inference code, refactored from
server.py into the LLMBackend abstraction.  Behaviour is identical —
no functional changes to the Intel path.

Requirements:
    pip install llama-cpp-python   (see install.bat / requirements-intel.txt)
"""
from __future__ import annotations

import time
from pathlib import Path
from typing import Any, Dict, Iterator, List

from pipeline.llm.base import LLMBackend, StreamEvent


class LlamaBackend(LLMBackend):
    """
    Local inference via llama-cpp-python + Qwen2.5-3B-Instruct GGUF.

    This backend runs entirely on CPU (or CUDA if N_GPU_LAYERS > 0).
    It is the primary backend on Intel / non-Snapdragon machines.
    """

    def __init__(
        self,
        model_path: str,
        n_ctx: int = 8192,
        n_gpu_layers: int = -1,
        verbose: bool = False,
    ) -> None:
        self._model_path = model_path
        self._n_ctx = n_ctx
        self._n_gpu_layers = n_gpu_layers
        self._verbose = verbose
        self._llm = None
        self._load_time_ms: int | None = None

    # ── Identity ─────────────────────────────────────────────────────────────

    @property
    def backend_name(self) -> str:
        return "llama"

    @property
    def model_name(self) -> str:
        return Path(self._model_path).name

    @property
    def runtime_name(self) -> str:
        return "llama.cpp"

    @property
    def device_name(self) -> str:
        return "CPU"

    # ── Lifecycle ─────────────────────────────────────────────────────────────

    def load(self) -> None:
        """Load the GGUF model. Raises RuntimeError if file is missing."""
        if not Path(self._model_path).exists():
            raise RuntimeError(
                f"[LlamaBackend] Model file not found: {self._model_path}\n"
                "Run `python download_models.py` to download it."
            )
        try:
            from llama_cpp import Llama  # type: ignore
        except ImportError as exc:
            raise RuntimeError(
                "[LlamaBackend] llama-cpp-python is not installed.\n"
                "Install it with:  pip install llama-cpp-python\n"
                "(See install.bat or requirements-intel.txt for details.)"
            ) from exc

        t0 = time.time()
        self._llm = Llama(
            model_path=self._model_path,
            n_ctx=self._n_ctx,
            n_gpu_layers=self._n_gpu_layers,
            verbose=self._verbose,
        )
        self._load_time_ms = int((time.time() - t0) * 1000)
        print(
            f"[LlamaBackend] Loaded {self.model_name} in {self._load_time_ms} ms "
            f"(n_ctx={self._n_ctx}, n_gpu_layers={self._n_gpu_layers})"
        )

    def unload(self) -> None:
        self._llm = None

    # ── Streaming inference ───────────────────────────────────────────────────

    def stream(
        self,
        messages: List[Dict[str, str]],
        max_tokens: int = 512,
        temperature: float = 0.1,
        top_p: float = 0.8,
        repeat_penalty: float = 1.1,
    ) -> Iterator[StreamEvent]:
        """
        Yield stream events from llama_cpp's create_chat_completion(stream=True).

        This replicates the exact logic that was in server.py _run_llm(),
        but is now encapsulated here so server.py only calls backend.stream().
        """
        if self._llm is None:
            yield ("error", "[LlamaBackend] Model not loaded. Call load() first.")
            return

        try:
            t_start = time.time()
            first_token = True

            stream = self._llm.create_chat_completion(
                messages=messages,
                max_tokens=max_tokens,
                temperature=temperature,
                top_p=top_p,
                repeat_penalty=repeat_penalty,
                stream=True,
            )

            for chunk in stream:
                delta = chunk["choices"][0]["delta"]
                if "content" in delta:
                    text = delta["content"]
                    if first_token:
                        ttft_ms = int((time.time() - t_start) * 1000)
                        yield ("ttft", ttft_ms)
                        first_token = False
                    yield ("token", text)

            yield ("done", None)

        except Exception as exc:
            yield ("error", str(exc))

    # ── Health ────────────────────────────────────────────────────────────────

    def health(self) -> Dict[str, Any]:
        return {
            "backend": self.backend_name,
            "model": self.model_name,
            "runtime": self.runtime_name,
            "device": self.device_name,
            "status": "ready" if self._llm is not None else "not_loaded",
            "load_time_ms": self._load_time_ms,
            "npu_available": False,
            "qnn_available": False,
        }
