# NEXUS Offensive — Capa 0: la jaula

Motor de investigación de vulnerabilidades para **bug bounty autorizado**
(nicho Web3 / Immunefi). Uso exclusivo sobre *scope* con **autorización
escrita**. Esto **no** es una guía para acceder a sistemas sin permiso.

Este repo arranca por donde manda el documento maestro: **la Capa 0, la
jaula**. Es el cimiento legal y de seguridad, y es lo primero que se
commitea. Ninguna capa futura (observador, motores de análisis,
fork-validador, copiloto, reporte) existe todavía.

## Por qué la jaula primero

Lo que separa a un "investigador de seguridad respetado" de un "acusado" no
es el exploit: es la contención. La jaula son los guardarraíles que
mantienen cada acción dentro de lo autorizado:

- **`scope.py` · `ScopeGuard`** — decide ALLOW/DENY para cada target.
  - **default-deny:** lo no declarado explícitamente in-scope **no existe**.
  - **OUT gana sobre IN siempre:** si algo cae en `out_scope`, se deniega
    aunque también encaje en un wildcard de `in_scope`.
  - **wildcard honesto:** `*.x.com` cubre `a.x.com` y `a.b.x.com`, pero
    **nunca** la raíz `x.com` ni el truco de sufijo
    `app.x.com.attacker.net`.
  - **CIDR:** rangos IPv4/IPv6 por red.
  - `check(target) -> Verdict` y `assert_allowed(target)` (lanza
    `PermissionError` si no está permitido).
- **`ratelimit.py` · `RateLimiter`** — token-bucket por host que obedece el
  `rps` del programa. Tumbar un servidor convierte un bounty en delito.
  `acquire(host)` bloquea hasta tener permiso.
- **`audit.py` · `AuditLog`** — bitácora inmutable con **hash encadenado**:
  cada entrada incluye el hash de la anterior, así cualquier manipulación
  (editar, reordenar o borrar) rompe la cadena de forma detectable con
  `verify()`.
- **`models.py`** — vocabulario compartido: `Target`, `Contract`,
  `Finding`, `Report`, el enum `Decision` (ALLOW/DENY), `Severity` y
  `Verdict`.

## La regla invariable del sistema

> **Ninguna capa futura abre un socket sin llamar antes a
> `ScopeGuard.assert_allowed(target)`.**

La jaula no es burocracia: es la precondición de todo lo demás.

## Estructura

```
nexus-offensive/
├── core/
│   ├── models.py        # Target · Contract · Finding · Report · Decision · Verdict
│   ├── scope.py         # ScopeGuard: default-deny, OUT>IN, wildcard, CIDR
│   ├── ratelimit.py     # RateLimiter: token-bucket por host
│   └── audit.py         # AuditLog: bitácora inmutable con hash encadenado
├── config/
│   └── scope.ejemplo.yaml   # in_scope / out_scope / rps de muestra
├── tests/               # pytest: wildcard, OUT>IN, default-deny, CIDR, sufijo, tamper
├── requirements.txt
└── pytest.ini
```

## Uso rápido

```python
from core import ScopeGuard, AuditLog

audit = AuditLog(path="audit.log")                 # bitácora encadenada opcional
guard = ScopeGuard.from_yaml("config/scope.ejemplo.yaml", audit_log=audit)

guard.assert_allowed("app.example.com")            # OK
guard.assert_allowed("admin.example.com")          # PermissionError (out_scope)

limiter = guard.rate_limiter()                     # obedece el rps del scope
limiter.acquire("app.example.com")                 # bloquea hasta tener permiso

assert audit.verify().ok                           # la cadena no fue alterada
```

## Instalar y probar

```bash
cd nexus-offensive
pip install -r requirements.txt
pytest -v
```

Todo el código es Python 3.11+ y corre con dependencias mínimas (PyYAML +
pytest; el resto es librería estándar).
