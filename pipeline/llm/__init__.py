"""
pipeline/llm/__init__.py
-------------------------
Public entry-point for the LLM backend abstraction layer.

Usage:
    from pipeline.llm import get_llm_backend
    backend = get_llm_backend(settings)
"""
from pipeline.llm.factory import get_llm_backend  # noqa: F401

__all__ = ["get_llm_backend"]
