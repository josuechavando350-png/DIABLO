# watch/ — Capa 1: Observador

Vigila una cadena buscando **deploys/upgrades de contratos in-scope** y, por
cada uno, pasa por la **jaula** (`ScopeGuard.assert_allowed`) antes de disparar
el motor de invariantes. Cada observación queda en la bitácora inmutable
(Capa 0). Default-deny: lo no declarado in-scope se ignora.

## Piezas
- `events.py` — `ChainEvent` (deploy/upgrade/tx).
- `sources.py` — `ChainSource` (ABC); `MockChainSource` (tests/local, sin red);
  `JsonRpcChainSource` (RPC real, con `transport` inyectable para probar el
  parseo sin red).
- `observer.py` — `Observer`: filtra por la jaula, audita, y solo entrega los
  in-scope al handler (siempre tras `assert_allowed`).

## Correr
```bash
cd nexus-offensive && python3 -m pytest tests/test_watch.py -q
```

## PENDIENTE DE INPUT DEL USUARIO
- **RPC real + su autorización.** `JsonRpcChainSource` necesita un `rpc_url` de
  archivo real y autorizado. Sin él, usa el transporte por defecto y lanza
  `RpcError` con el aviso de PENDIENTE. Los tests usan `MockChainSource` o un
  `transport` falso (100% local).
