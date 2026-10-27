"""Tests de la Capa 4 (Copiloto) — solo interfaz, sin API real."""

import json

import pytest

from copilot import (
    ContractContext,
    CopilotNotConfigured,
    InvariantHypothesis,
    LLMCopilot,
    StubCopilot,
    SYSTEM_PROMPT,
)


def test_stub_copilot_proposes_family_invariants():
    ctx = ContractContext(name="MiVault", family_hint="Vault", functions=["deposit", "redeem"])
    hyps = StubCopilot().propose_invariants(ctx)
    assert len(hyps) >= 1
    assert all(isinstance(h, InvariantHypothesis) for h in hyps)
    assert any("activos == shares" in h.invariant for h in hyps)


def test_stub_copilot_unknown_family_is_empty():
    assert StubCopilot().propose_invariants(ContractContext(name="X", family_hint="Nada")) == []


def test_llm_copilot_without_key_is_pending():
    cop = LLMCopilot()  # sin api_key ni send_fn → PENDIENTE DE INPUT
    with pytest.raises(CopilotNotConfigured):
        cop.propose_invariants(ContractContext(name="X", family_hint="AMM"))


def test_llm_copilot_wiring_with_injected_transport():
    # Transporte falso: prueba el armado del prompt y el parseo, sin API real.
    captured = {}

    def fake_send(prompt, api_key, model):
        captured["prompt"] = prompt
        captured["api_key"] = api_key
        return json.dumps(
            [{"family": "AMM", "invariant": "k no decrece", "rationale": "fees", "confidence": 0.9}]
        )

    cop = LLMCopilot(api_key="test-key", send_fn=fake_send)
    ctx = ContractContext(name="ToyAmm", family_hint="AMM", functions=["swap"])
    hyps = cop.propose_invariants(ctx)

    assert SYSTEM_PROMPT in captured["prompt"]
    assert "ToyAmm" in captured["prompt"]
    assert captured["api_key"] == "test-key"
    assert len(hyps) == 1
    assert hyps[0].invariant == "k no decrece"
    assert hyps[0].confidence == 0.9


def test_build_prompt_includes_context():
    cop = LLMCopilot()
    prompt = cop.build_prompt(ContractContext(name="Pool", family_hint="FlashLoan", functions=["flashLoan"]))
    assert "Pool" in prompt and "FlashLoan" in prompt and "flashLoan" in prompt
