"""Smoke tests de los modelos de dominio."""

from core.models import Contract, Decision, Finding, Report, Severity, Target, Verdict


def test_decision_values():
    assert Decision.ALLOW.value == "ALLOW"
    assert Decision.DENY.value == "DENY"


def test_target_normalized():
    assert Target(" A.X.Com. ").normalized() == "a.x.com"


def test_verdict_truthiness():
    t = Target("a.x.com")
    allow = Verdict(Decision.ALLOW, t, "in scope")
    deny = Verdict(Decision.DENY, t, "default-deny")
    assert allow.allowed and bool(allow)
    assert not deny.allowed and not bool(deny)


def test_contract_as_target():
    c = Contract(address="0xabc", chain="ethereum", name="Vault", verified=True)
    t = c.as_target()
    assert t.kind == "contract"
    assert t.value == "0xabc"
    assert t.chain == "ethereum"
    assert t.label == "Vault"


def test_report_accumulates_findings():
    r = Report(program="immunefi-x", author="josue")
    r.add(
        Finding(
            id="F-1",
            title="Reentrancy drains vault",
            severity=Severity.CRITICAL,
            target=Target("0xabc", kind="contract"),
            invariant="sum(balances) == totalSupply",
        )
    )
    assert len(r) == 1
    assert r.findings[0].severity is Severity.CRITICAL
