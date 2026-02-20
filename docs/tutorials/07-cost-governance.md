# 07 Cost and Governance

## Objetivo y contexto
Controlar costo y riesgo operativo del proyecto con reglas verificables por entorno.

Objetivo de esta fase:
1. Definir presupuestos y alertas con criterios explicitos.
2. Integrar chequeo de recursos activos con operacion diaria.
3. Establecer disciplina mensual de revision y evidencia.

## Estado actual y alcance
Estado actual:
- Esta fase no esta cerrada end-to-end en el repositorio.

Alcance de esta guia:
1. Convertir fase 07 en backlog ejecutable con gates cuantificables.
2. Evitar cierre sin presupuesto, alertas y evidencia de revision mensual.

## Fuentes oficiales (Cost/Budgets/Governance)
1. `https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html`
2. `https://docs.aws.amazon.com/aws-cost-management/latest/APIReference/API_Operations_AWS_Budgets.html`
3. `https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-controls.html`
4. `https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/cost-alloc-tags.html`
5. `https://docs.aws.amazon.com/cost-management/latest/userguide/ce-what-is.html`
6. `https://docs.aws.amazon.com/scheduler/latest/UserGuide/what-is-scheduler.html`
7. `https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-what-is.html`
8. Referencia local de estudio: `docs/aws/sagemaker-dg.pdf`.

## Contrato de costo y gobierno (decision-complete)
### 1) Presupuestos requeridos por entorno
1. `titanic-dev-monthly-cost`
2. `titanic-prod-monthly-cost`

### 2) Umbrales minimos de alerta
1. `50%` (warning)
2. `80%` (high)
3. `100%` (critical)

### 3) Destinatarios minimos de alerta
1. Owner tecnico del proyecto.
2. Responsable de costo/finops del equipo.

### 4) Etiquetas obligatorias
1. `project=titanic-sagemaker`
2. `env=<dev|prod>`
3. `owner=<team-or-user>`
4. `managed_by=terraform`
5. `cost_center=<value>`

## Backlog implementable de fase 07 (con checks medibles)
### Entregable 1 - Budgets operativos (planned)
Checks:
1. Existen budgets `dev` y `prod` con umbrales 50/80/100.
2. Cada budget tiene destinatarios configurados.
3. Evidencia de consulta CLI en iteracion.

### Entregable 2 - Cost allocation tags activos (planned)
Checks:
1. Tags de costo activados en Billing.
2. Cost Explorer permite agrupar por `Tag:project` y `Tag:env`.
3. Evidencia de captura/reporte en iteracion.

### Entregable 3 - Control de recursos activos (planned)
Checks:
1. Ejecucion periodica de `scripts/check_tutorial_resources_active.sh --phase all`.
2. Hallazgos clasificados (`active/inactive/unknown`) con accion correctiva.
3. Gate opcional en CI con `--fail-if-active` para ventanas definidas.

### Entregable 4 - Politica de apagado no-prod (planned)
Checks:
1. Horario definido para apagar/suspender recursos no prod.
2. Evidencia de schedule activo (Scheduler/EventBridge).
3. Verificacion de cumplimiento en revision mensual.

## Decisiones tecnicas y alternativas descartadas
1. Presupuestos por entorno con naming fijo para trazabilidad.
2. Alertas escalonadas 50/80/100 para respuesta temprana.
3. Chequeo de recursos activos como control operativo recurrente.
4. Descartado: control de costo reactivo solo al cierre de mes.

## IAM usado (roles/policies/permisos clave)
1. Identidad base: `data-science-user`.
2. Permisos de lectura de Budgets/Cost Explorer para operador DS.
3. Permisos acotados para scheduler y acciones stop/start cuando aplique.
4. Mantener least-privilege y evitar wildcard sin justificacion.

## Comandos ejecutados y resultado esperado
```bash
export AWS_PROFILE=data-science-user
export AWS_REGION=eu-west-1

# Budgets
aws budgets describe-budgets \
  --account-id 939122281183 \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION"

# Recursos activos/orfanos
AWS_PROFILE=data-science-user scripts/check_tutorial_resources_active.sh --phase all

# Gate operativo opcional
AWS_PROFILE=data-science-user scripts/check_tutorial_resources_active.sh --phase all --fail-if-active
```

Resultado esperado:
1. Budgets visibles por entorno.
2. Reporte de recursos activos disponible.
3. Hallazgos con accion correctiva documentada.

## Evidencia requerida (checklist mensual)
1. Snapshot de budgets `dev/prod` con estado y umbrales.
2. Evidencia de alertas emitidas (si aplica) y acciones tomadas.
3. Resultado del checker `--phase all` con fecha.
4. Lista de recursos apagados/limpiados en no-produccion.
5. Registro de desviaciones y plan de correccion para el mes siguiente.

## Criterio de cierre
1. Presupuestos `titanic-dev-monthly-cost` y `titanic-prod-monthly-cost` activos.
2. Alertas 50/80/100 con destinatarios definidos.
3. Checker de recursos activos integrado en operacion recurrente.
4. Politica de apagado no-prod definida y verificada.
5. Evidencia mensual registrada en `docs/iterations/`.

## Riesgos/pendientes
1. Recursos con tags incompletos que no entran al analisis de costo.
2. Endpoints sin schedule de ahorro en no-produccion.
3. Alertas ignoradas por falta de ownership operativo.

## Proximo paso
Registrar cada ciclo mensual de costo en `docs/iterations/` y mantener sincronia con decisiones de fases 04-06.
