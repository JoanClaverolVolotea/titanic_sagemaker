# 06 Observability and Operations

## Objetivo y contexto
Definir observabilidad operativa para el ciclo completo:
1. ejecuciones de SageMaker Pipeline,
2. endpoints de serving (`staging` y `prod`),
3. monitoreo de drift/calidad de modelo,
4. alertamiento y runbooks de respuesta.

## Estado actual y alcance
Estado actual:
- Esta fase aun no esta implementada de punta a punta en el repositorio.

Alcance de esta guia:
1. Convertir fase 06 en backlog ejecutable con criterios medibles.
2. Evitar cierre de fase sin alarmas, rutas de observacion y runbooks probados.

## Fuentes oficiales (SageMaker/CloudWatch/EventBridge)
1. `https://docs.aws.amazon.com/sagemaker/latest/dg/logging-cloudwatch.html`
2. `https://docs.aws.amazon.com/sagemaker/latest/dg/monitoring-cloudwatch.html`
3. `https://docs.aws.amazon.com/sagemaker/latest/dg/model-monitor.html`
4. `https://docs.aws.amazon.com/sagemaker/latest/dg/model-monitor-schedules.html`
5. `https://docs.aws.amazon.com/sagemaker/latest/dg/model-monitor-data-capture.html`
6. `https://docs.aws.amazon.com/sagemaker/latest/dg/monitor-model-quality.html`
7. `https://docs.aws.amazon.com/sagemaker/latest/dg/automating-sagemaker-with-eventbridge.html`
8. `https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-rule-dlq.html`
9. `https://docs.aws.amazon.com/AmazonCloudWatch/latest/APIReference/API_PutMetricAlarm.html`
10. `https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/AlarmThatSendsEmail.html`

## Backlog implementable de fase 06 (con checks medibles)
### Entregable 1 - Alarmas de ejecucion de pipeline (planned)
Objetivo:
1. Detectar fallos de pipeline y jobs asociados.

Checks minimos:
1. Alarma en estado `OK` para fallos de pipeline.
2. Alarma en estado `OK` para fallos de training/evaluation.
3. Prueba controlada de notificacion documentada.

### Entregable 2 - Alarmas de endpoint (planned)
Objetivo:
1. Monitorear salud de `staging` y `prod`.

Checks minimos:
1. Alarma por errores de invocacion (`5xx`) en endpoint.
2. Alarma por latencia alta (P95/P99 segun umbral acordado).
3. Evidencia de prueba de alarma en `staging`.

### Entregable 3 - Model Monitor baseline y schedule (planned)
Objetivo:
1. Preparar monitoreo de calidad/drift posterior a despliegue.

Checks minimos:
1. Data capture habilitado en endpoint objetivo.
2. Baseline de referencia versionado.
3. Schedule de Model Monitor creado y visible.

### Entregable 4 - EventBridge de cambios de estado (planned)
Objetivo:
1. Recibir eventos operativos sin polling manual.

Checks minimos:
1. Regla EventBridge para cambio de estado de pipeline.
2. Regla EventBridge para cambio de estado de model package.
3. Regla EventBridge para estado de endpoint.
4. Ruta de entrega (target) con manejo de fallos/DLQ.

## Decisiones tecnicas y alternativas descartadas
1. CloudWatch como backend principal de observabilidad.
2. EventBridge para eventos de estado (pipeline/model package/endpoint).
3. Model Monitor como control de deriva/calidad en produccion.
4. Descartado: monitoreo ad-hoc sin alarmas ni criterios cuantificables.

## IAM usado (roles/policies/permisos clave)
1. Identidad base: `data-science-user`.
2. Permisos de lectura operativa para DS sobre SageMaker/CloudWatch/EventBridge.
3. Permisos de escritura para workloads solo donde corresponda (logs/metrics).
4. Roles separados por servicio y `PassRole` restringido.

## Comandos ejecutados y resultado esperado
Comandos de verificacion operativa (cuando se implemente):

```bash
export AWS_PROFILE=data-science-user
export AWS_REGION=eu-west-1

# Alarmas
aws cloudwatch describe-alarms --profile "$AWS_PROFILE" --region "$AWS_REGION"

# Eventos SageMaker en EventBridge
aws events list-rules --profile "$AWS_PROFILE" --region "$AWS_REGION"

# Logs de endpoints y jobs
aws logs describe-log-groups --profile "$AWS_PROFILE" --region "$AWS_REGION"
```

Resultado esperado:
1. Alarmas existentes y en estado `OK`.
2. Reglas EventBridge activas para eventos clave.
3. Logs disponibles para pipeline y serving.

## Runbook por sintoma (obligatorio)
| Sintoma | Causa raiz probable | Accion inmediata | Evidencia a guardar |
|---|---|---|---|
| endpoint `staging/prod` no responde | endpoint en `Failed` o config invalido | `DescribeEndpoint`, revisar `FailureReason`, rollback a config previo | ARN endpoint, estado, timestamp, config usado |
| regresion tras promocion | modelo promovido no cumple comportamiento esperado | congelar promocion, rollback `UpdateEndpoint`, abrir incidente | `ModelPackageArn`, resultados smoke previos/posteriores |
| pipeline drift/fallo recurrente | cambio no controlado en datos/codigo/IAM | revisar steps fallidos, logs CloudWatch, bloquear promociones | `PipelineExecutionArn`, step status, diff de parametros |

## Evidencia requerida
1. Inventario de alarmas por categoria (pipeline, endpoint, costo).
2. Evidencia de al menos una prueba de alerta.
3. Inventario de reglas EventBridge y targets.
4. Evidencia de baseline/schedule de Model Monitor.
5. Runbook probado para un incidente simulado.

## Criterio de cierre
1. Alarmas criticas definidas y validadas.
2. Eventos de estado clave conectados por EventBridge.
3. Baseline y schedule de Model Monitor activos.
4. Runbooks operativos disponibles y probados.

## Riesgos/pendientes
1. Fatiga de alertas por umbrales sin calibracion.
2. Coste adicional de captura/monitor sin politica de retencion.
3. Falta de ownership por alerta si no se asigna on-call/responsable.

## Proximo paso
Aterrizar `docs/tutorials/07-cost-governance.md` con budgets, umbrales y controles mensuales obligatorios.
