# copilot/ — Capa 4: Copiloto de criterio (solo interfaz)

Estructura para que un LLM **proponga hipótesis de invariantes** sobre un
contrato. El copiloto solo sugiere; el humano valida (con el fork-validador).
**No se conecta ninguna API aquí.**

## Piezas
- `interface.py`:
  - `ContractContext` — lo que se le da al copiloto (nombre, familia, funciones,
    fragmento de código).
  - `InvariantHypothesis` — una invariante propuesta (familia, propiedad,
    rationale, confianza).
  - `InvariantCopilot` (ABC).
  - `StubCopilot` — offline, determinista: sugiere invariantes canónicas del
    catálogo (Capa 2). Permite usar el pipeline **sin ninguna API**.
  - `LLMCopilot` — respaldado por un LLM. Arma el prompt y parsea la respuesta
    (ambos probados), pero **no abre ningún socket**: el transporte `send_fn` y
    la API key se inyectan.

## Correr
```bash
cd nexus-offensive && python3 -m pytest tests/test_copilot.py -q
```

## PENDIENTE DE INPUT DEL USUARIO
- **API key del LLM + transporte de red.** `LLMCopilot` sin `api_key`/`send_fn`
  lanza `CopilotNotConfigured`. Para conectarlo (lo que falta):
  1. Proveer la API key (p.ej. por variable de entorno).
  2. Inyectar un `send_fn(prompt, api_key, model)` que llame al endpoint de
     mensajes del proveedor con `SYSTEM_PROMPT` + `build_prompt(context)` y
     devuelva el texto. Nada de esto se hace aquí para no usar credenciales reales.
