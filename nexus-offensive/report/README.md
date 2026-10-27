# report/ — Capa 5: Reporte

Toma un `Finding` (Capa 0) + contexto (impacto, pasos de reproducción, PoC,
invariante violada) y produce un **borrador de reporte en Markdown** listo para
que el humano lo revise, valide y firme.

## Piezas
- `generator.py` — `ReportDraft` (datos del reporte) y `render_markdown(draft)`:
  secciones Resumen, Severidad (+justificación), Impacto, Invariante violada,
  Pasos para reproducir, PoC, Recomendación, Referencias.

## Uso
```python
from core.models import Finding, Severity, Target
from report import ReportDraft, render_markdown

draft = ReportDraft(finding=Finding(...), summary="...", impact="...",
                    reproduction_steps=[...], poc_code="...", recommendation="...")
print(render_markdown(draft))
```

## Correr
```bash
cd nexus-offensive && python3 -m pytest tests/test_report.py -q
```
