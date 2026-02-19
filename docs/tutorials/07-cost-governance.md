# 07 Cost and Governance

## Objetivo y contexto
Controlar costo y riesgo operativo desde el disenio hasta la operacion diaria.

## Paso a paso (ejecucion)
1. Activar en Billing los Cost Allocation Tags:
   - `project`, `env`, `owner`, `managed_by`, `cost_center`.
2. Estandarizar en Terraform futuro:
   - `provider.aws.default_tags` con las 5 llaves obligatorias,
   - tags explicitos por recurso/modulo cuando aplique.
3. Configurar presupuesto mensual por entorno con naming estandar:
   - `titanic-dev-monthly-cost`,
   - `titanic-prod-monthly-cost`.
4. Crear alertas de costo por umbrales (ejemplo 50%, 80%, 100%).
5. Usar Cost Explorer agrupando por `Tag:project` y `Tag:env` para identificar desviaciones.
6. Definir horario de apagado/suspensión para recursos no productivos.
7. Revisar recursos huérfanos en cada iteración (endpoints, jobs, artefactos) con:
   - `AWS_PROFILE=data-science-user scripts/check_tutorial_resources_active.sh --phase all`.
8. Registrar acciones correctivas de costo en `docs/iterations/`.

## Decisiones tecnicas y alternativas descartadas
- Budgets y alertas por entorno.
- Naming estandar de budgets por ambiente (`titanic-<env>-monthly-cost`).
- Scheduler para apagar recursos no prod cuando aplique.
- Tagging obligatorio para trazabilidad financiera.
- Cost allocation tags activados en Billing para obtener trazabilidad en Cost Explorer.
- Controlar costo de endpoints `staging`/`prod` y ejecuciones programadas del pipeline.

## IAM usado (roles/policies/permisos clave)
- Permisos de lectura de costos y presupuesto para operador DS.
- Permisos acotados para scheduler y acciones de stop/start.
- Operador humano con usuario `data-science-user` y keys logicas `data-science-user-primary` / `data-science-user-rotation`.

## Comandos ejecutados y resultado esperado
- Regla operativa AWS: ejecutar comandos con `data-science-user` como base y perfil `data-science-user`.
- Verificar budgets por cuenta:
  - `aws budgets describe-budgets --account-id 939122281183 --profile data-science-user --region eu-west-1`
- Auditar recursos potencialmente activos/orfanos:
  - `AWS_PROFILE=data-science-user scripts/check_tutorial_resources_active.sh --phase all`
- Validacion de schedules de apagado.
- Resultado esperado: costo dentro de umbrales definidos.

## Evidencia
Agregar:
- Captura de Cost Allocation Tags activos en Billing.
- Umbrales y alertas configuradas por budget (`dev`/`prod`).
- Resultado del checker `--phase all` para control de recursos activos.
- Prueba de acciones programadas de ahorro.

## Criterio de cierre
- Presupuestos y alertas activos por entorno.
- Cost Explorer usable por `Tag:project` y `Tag:env`.
- Programación de ahorro validada para no-producción.
- No hay recursos críticos sin tags obligatorios.

## Riesgos/pendientes
- Recursos huerfanos sin tags.
- Costos inesperados por endpoints activos 24/7.

## Proximo paso
Registrar iteraciones en `docs/iterations/`.
