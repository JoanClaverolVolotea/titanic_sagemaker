# 06 Observability and Operations

## Objetivo y contexto
Asegurar operacion con logs, metricas, alarmas y runbooks para incidentes.

## Paso a paso (ejecucion)
1. Centralizar logs de:
   - SageMaker Processing/Training/Pipeline,
   - Step Functions/Lambda,
   - endpoints `staging` y `prod`.
2. Definir métricas operativas mínimas:
   - éxito/fallo por etapa,
   - duración de ejecución,
   - latencia y errores de inferencia.
3. Crear alarmas para:
   - fallos de pipeline/training,
   - degradación del endpoint,
   - anomalías de costo.
4. Ejecutar prueba controlada de alerta y verificar notificación.
5. Documentar runbook corto por alerta crítica.

## Decisiones tecnicas y alternativas descartadas
- CloudWatch Logs centralizado por servicio.
- Alarmas para fallos de training/pipeline/endpoint/costo.
- Monitoreo obligatorio de:
  - ejecuciones de SageMaker Pipeline (processing/training/evaluation/register),
  - despliegues `staging` y `prod`,
  - errores de smoke tests en fase de promotion.
- Alternativas descartadas: monitoreo ad-hoc sin umbrales.

## IAM usado (roles/policies/permisos clave)
- Permisos de lectura operativa para DS.
- Permisos de escritura de logs para workloads.
- Operador humano con usuario `data-science-user` y keys logicas `data-science-user-primary` / `data-science-user-rotation`.

## Comandos ejecutados y resultado esperado
- Regla operativa AWS: ejecutar comandos con `data-science-user` como base y perfil `data-science-user`.
- Validacion de alarmas y dashboards
- Prueba de alertas
- Resultado esperado: visibilidad completa del flujo E2E.

## Evidencia
Agregar alarmas activas, capturas de dashboards y runbooks vinculados.

## Criterio de cierre
- Dashboard operativo visible para pipeline y serving.
- Alarmas críticas probadas y notificando.
- Runbooks disponibles para incidentes recurrentes.

## Riesgos/pendientes
- Alarm fatigue por umbrales mal calibrados.
- Falta de ownership por alerta.

## Proximo paso
Aplicar controles de costos en `docs/tutorials/07-cost-governance.md`.
