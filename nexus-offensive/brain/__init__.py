"""brain/ — integración end-to-end del motor NEXUS Offensive.

Encadena: Observador (Capa 1) → motor/fork-validador (Capa 2/3) → Reporte
(Capa 5), con la jaula (Capa 0) en el centro y bitácora inmutable.
"""

from .pipeline import ForgeValidator, FunctionValidator, Pipeline, ValidationResult

__all__ = ["ForgeValidator", "FunctionValidator", "Pipeline", "ValidationResult"]
