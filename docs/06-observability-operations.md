# 06 Observability and Operations

## Objetivo y contexto
Asegurar operacion con logs, metricas, alarmas y runbooks para incidentes.

## Decisiones tecnicas y alternativas descartadas
- CloudWatch Logs centralizado por servicio.
- Alarmas para fallos de training/pipeline/endpoint/costo.
- Alternativas descartadas: monitoreo ad-hoc sin umbrales.

## IAM usado (roles/policies/permisos clave)
- Permisos de lectura operativa para DS.
- Permisos de escritura de logs para workloads.

## Comandos ejecutados y resultado esperado
- Validacion de alarmas y dashboards
- Prueba de alertas
- Resultado esperado: visibilidad completa del flujo E2E.

## Evidencia
Agregar alarmas activas, capturas de dashboards y runbooks vinculados.

## Riesgos/pendientes
- Alarm fatigue por umbrales mal calibrados.
- Falta de ownership por alerta.

## Proximo paso
Aplicar controles de costos en `docs/07-cost-governance.md`.
