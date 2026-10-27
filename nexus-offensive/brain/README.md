# brain/ — Integración end-to-end

Encadena **Observador (Capa 1) → motor/fork-validador (Capa 2/3) → Reporte
(Capa 5)**, con la **jaula (Capa 0)** en el centro y bitácora inmutable.

Flujo: el observador detecta un contrato in-scope (jaula ALLOW) → el
fork-validador ejecuta un PoC en el EVM → si la invariante se rompe, se genera
un `Finding` y un borrador de reporte.

## Piezas
- `pipeline.py`:
  - `ValidationResult` — resultado de validar (rompe SÍ/NO + invariante + PoC).
  - `FunctionValidator` — validador determinista (callable), para tests.
  - `ForgeValidator` — validador **real**: corre un PoC de Foundry; que el test
    PoC pase = la invariante se reprodujo rota en el EVM.
  - `Pipeline` — orquesta todo y escribe los reportes.
- `demo.py` — demo end-to-end real: observa un deploy in-scope, valida con el
  PoC `VaultV4` del motor, genera el reporte; bloquea un deploy out-of-scope.

## Correr
```bash
cd nexus-offensive
python3 -m pytest tests/test_brain.py -q      # incluye un e2e con forge real
python3 brain/demo.py                          # demo de principio a fin (local)
```

El `test_pipeline_with_real_forge_validator` ejecuta el fork-validador real
(Foundry). 100% local, sin red ni direcciones de producción.
