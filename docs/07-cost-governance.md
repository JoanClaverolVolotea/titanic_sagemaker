# 07 Cost and Governance

## Objetivo y contexto
Controlar costo y riesgo operativo desde el disenio hasta la operacion diaria.

## Decisiones tecnicas y alternativas descartadas
- Budgets y alertas por entorno.
- Scheduler para apagar recursos no prod cuando aplique.
- Tagging obligatorio para trazabilidad financiera.

## IAM usado (roles/policies/permisos clave)
- Permisos de lectura de costos y presupuesto para operador DS.
- Permisos acotados para scheduler y acciones de stop/start.

## Comandos ejecutados y resultado esperado
- Configuracion de budgets/alerts
- Validacion de schedules de apagado
- Resultado esperado: costo dentro de umbrales definidos.

## Evidencia
Agregar umbrales, alertas configuradas y prueba de acciones programadas.

## Riesgos/pendientes
- Recursos huerfanos sin tags.
- Costos inesperados por endpoints activos 24/7.

## Proximo paso
Registrar iteraciones en `docs/iterations/`.
