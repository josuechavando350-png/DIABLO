"""Tests de la Capa 1 (Observador)."""

import pytest

from core import AuditLog, ScopeGuard
from watch import ChainEvent, JsonRpcChainSource, MockChainSource, Observer, PENDING_RPC_URL, RpcError


def _guard():
    return ScopeGuard(in_scope=["0xin01"], out_scope=["0xout99"], rps=1.0)


def test_observer_only_fires_on_in_scope():
    guard = _guard()
    audit = AuditLog()
    fired = []
    src = MockChainSource([
        ChainEvent("deploy", "0xin01", 1, "local"),
        ChainEvent("deploy", "0xunknown", 2, "local"),  # default-deny
        ChainEvent("deploy", "0xout99", 3, "local"),  # out_scope
    ])
    obs = Observer(guard, src, lambda ev: fired.append(ev.address), audit_log=audit)
    obs.run_once()

    assert fired == ["0xin01"]
    assert len(obs.seen_in_scope) == 1
    assert len(obs.skipped_out_of_scope) == 2
    # Cada observación quedó en la bitácora (3 eventos) y la cadena es íntegra.
    assert len(audit) == 3
    assert audit.verify().ok


def test_observer_enforces_jaula_before_handler():
    # Si el handler se ejecuta, es porque assert_allowed no lanzó: solo in-scope.
    guard = _guard()
    calls = []

    def handler(ev):
        # En este punto la jaula ya autorizó el target.
        guard.assert_allowed(ev.address)  # no debe lanzar
        calls.append(ev.address)
        return "validated"

    src = MockChainSource([ChainEvent("deploy", "0xin01", 1)])
    obs = Observer(guard, src, handler)
    results = obs.run_once()
    assert calls == ["0xin01"]
    assert results[0][1] == "validated"


def test_jsonrpc_source_parses_without_network():
    # Transporte falso: simula respuestas JSON-RPC sin abrir ningún socket.
    responses = {
        ("eth_blockNumber", ()): "0x2",
        ("eth_getBlockByNumber", ("0x1", True)): {
            "transactions": [{"hash": "0xtx1", "to": None}]
        },
        ("eth_getTransactionReceipt", ("0xtx1",)): {"contractAddress": "0xDEPLOYED"},
        ("eth_getBlockByNumber", ("0x2", True)): {
            "transactions": [{"hash": "0xtx2", "to": "0xsomecontract"}]  # no es deploy
        },
    }

    def fake_transport(url, payload):
        key = (payload["method"], tuple(payload["params"]))
        return {"result": responses[key]}

    src = JsonRpcChainSource("http://fake", chain="test", transport=fake_transport, start_block=1)
    events = src.poll()
    assert len(events) == 1
    assert events[0].kind == "deploy"
    assert events[0].address == "0xDEPLOYED"
    assert events[0].block == 1


def test_jsonrpc_source_pending_without_url():
    # Sin RPC real y con el transporte real por defecto → PENDIENTE DE INPUT.
    src = JsonRpcChainSource(PENDING_RPC_URL)
    with pytest.raises(RpcError):
        src.poll()
