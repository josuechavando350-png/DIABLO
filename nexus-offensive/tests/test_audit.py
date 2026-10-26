"""Tests de la bitácora: la cadena de hashes detecta cualquier manipulación."""

import dataclasses

from core.audit import AuditEntry, AuditLog, GENESIS_PREV


def test_chain_valid():
    log = AuditLog()
    log.append("scope.check", {"target": "a.x.com", "decision": "ALLOW"})
    log.append("http.get", {"url": "https://a.x.com"})
    log.append("scope.check", {"target": "evil.com", "decision": "DENY"})
    assert log.verify().ok
    assert len(log) == 3
    assert log.entries[0].prev_hash == GENESIS_PREV


def test_detects_data_tamper():
    log = AuditLog()
    log.append("a", {"v": 1})
    log.append("b", {"v": 2})
    log.append("c", {"v": 3})
    # Alguien reescribe el contenido de una entrada pero conserva su hash viejo.
    log._entries[1] = dataclasses.replace(log._entries[1], data={"v": 999})
    result = log.verify()
    assert not result.ok
    assert result.broken_index == 1


def test_detects_link_tamper():
    log = AuditLog()
    log.append("a", {"v": 1})
    log.append("b", {"v": 2})
    # Se rompe el eslabón con la entrada previa.
    log._entries[1] = dataclasses.replace(log._entries[1], prev_hash=GENESIS_PREV)
    assert not log.verify().ok


def test_detects_deletion():
    log = AuditLog()
    log.append("a", {"v": 1})
    log.append("b", {"v": 2})
    log.append("c", {"v": 3})
    # Borrar una entrada del medio desordena los índices y rompe el enlace.
    del log._entries[1]
    assert not log.verify().ok


def test_assert_intact_raises_on_tamper():
    import pytest
    from core.audit import AuditError

    log = AuditLog()
    log.append("a", {"v": 1})
    log._entries[0] = dataclasses.replace(log._entries[0], data={"v": 2})
    with pytest.raises(AuditError):
        log.assert_intact()


def test_persist_and_reload(tmp_path):
    p = tmp_path / "audit.log"
    log = AuditLog(path=str(p))
    log.append("a", {"v": 1})
    log.append("b", {"v": 2})

    reloaded = AuditLog.load(str(p))
    assert len(reloaded) == 2
    assert reloaded.verify().ok
    assert reloaded.entries[0].data == {"v": 1}
