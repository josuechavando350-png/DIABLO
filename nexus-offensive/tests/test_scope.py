"""Tests de la puerta de la jaula: default-deny, OUT>IN, wildcard, CIDR, sufijo."""

from pathlib import Path

import pytest

from core.audit import AuditLog
from core.models import Decision, Target
from core.scope import ScopeGuard

CONFIG = Path(__file__).resolve().parents[1] / "config" / "scope.ejemplo.yaml"


def guard() -> ScopeGuard:
    return ScopeGuard(
        in_scope=["*.x.com", "api.y.com", "10.0.0.0/24", "2001:db8::/32"],
        out_scope=["secret.x.com", "*.internal.x.com", "10.0.0.5"],
        rps=2.0,
    )


def test_wildcard_nested():
    g = guard()
    assert g.check("a.x.com").allowed
    assert g.check("a.b.x.com").allowed
    assert g.check(Target("deep.nested.a.x.com")).allowed


def test_wildcard_does_not_cover_root():
    g = guard()
    assert g.check("x.com").decision is Decision.DENY


def test_out_beats_in():
    g = guard()
    # secret.x.com encaja en *.x.com (IN) pero está explícito en OUT -> DENY
    assert g.check("secret.x.com").decision is Decision.DENY
    # wildcard OUT anidado
    assert not g.check("db.internal.x.com").allowed


def test_default_deny():
    g = guard()
    assert g.check("unknown.z.com").decision is Decision.DENY
    assert g.check("x.org").decision is Decision.DENY
    # literal in-scope matchea exacto, pero no sus subdominios
    assert g.check("api.y.com").allowed
    assert g.check("other.y.com").decision is Decision.DENY


def test_cidr():
    g = guard()
    assert g.check("10.0.0.9").allowed          # dentro del /24
    assert g.check("2001:db8::1").allowed        # IPv6 dentro del /32
    assert g.check("10.0.1.9").decision is Decision.DENY   # fuera del /24
    assert g.check("10.0.0.5").decision is Decision.DENY   # IP excluida en OUT


def test_suffix_trick():
    g = guard()
    # El clásico engaño: parece subdominio de x.com pero no lo es.
    assert g.check("app.x.com.attacker.net").decision is Decision.DENY
    assert g.check("x.com.attacker.net").decision is Decision.DENY
    # Parecido que solo comparte texto, no el sufijo con punto.
    assert g.check("notx.com").decision is Decision.DENY


def test_assert_allowed_raises_on_deny():
    g = guard()
    with pytest.raises(PermissionError):
        g.assert_allowed("evil.com")


def test_assert_allowed_returns_verdict_on_allow():
    g = guard()
    verdict = g.assert_allowed("a.x.com")
    assert verdict.allowed
    assert verdict.decision is Decision.ALLOW


def test_from_yaml_loads_example():
    g = ScopeGuard.from_yaml(CONFIG)
    assert g.program == "ejemplo-immunefi-program"
    assert g.rps == 2.0
    assert g.check("app.example.com").allowed
    assert g.check("example.com").decision is Decision.DENY          # raíz no cubierta
    assert g.check("admin.example.com").decision is Decision.DENY    # OUT
    assert g.check("x.internal.example.com").decision is Decision.DENY  # OUT wildcard
    assert g.check("10.0.0.9").allowed
    assert g.check("10.0.0.5").decision is Decision.DENY


def test_scope_check_feeds_audit_log():
    audit = AuditLog()
    g = ScopeGuard(in_scope=["*.x.com"], out_scope=[], rps=1.0, audit_log=audit)
    g.check("a.x.com")
    g.check("evil.com")
    assert len(audit) == 2
    assert audit.verify().ok
    assert audit.entries[0].event == "scope.check"
    assert audit.entries[0].data["decision"] == "ALLOW"
    assert audit.entries[1].data["decision"] == "DENY"
