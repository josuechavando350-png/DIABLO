"""NEXUS Offensive · Capa 0 (la jaula).

Cimiento legal y de seguridad: scope con default-deny, rate-limit que
obedece al programa, y bitácora inmutable con hash encadenado.

Invariante del sistema: ninguna capa futura abre un socket sin llamar
antes a `ScopeGuard.assert_allowed(target)`.
"""

from .audit import AuditEntry, AuditError, AuditLog, VerifyResult, compute_hash
from .models import Contract, Decision, Finding, Report, Severity, Target, Verdict
from .ratelimit import RateLimiter
from .scope import ScopeGuard

__all__ = [
    "AuditEntry",
    "AuditError",
    "AuditLog",
    "VerifyResult",
    "compute_hash",
    "Contract",
    "Decision",
    "Finding",
    "Report",
    "Severity",
    "Target",
    "Verdict",
    "RateLimiter",
    "ScopeGuard",
]
