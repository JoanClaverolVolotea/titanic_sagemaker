# 07 Cost and Governance

## Objetivo y contexto
Controlar costo y riesgo operativo desde el disenio hasta la operacion diaria.

## Paso a paso (ejecucion)
1. Configurar presupuesto mensual por entorno (`dev` y `prod`).
2. Crear alertas de costo por umbrales (ejemplo 50%, 80%, 100%).
3. Definir horario de apagado/suspensión para recursos no productivos.
4. Revisar recursos huérfanos en cada iteración (endpoints, jobs, artefactos).
5. Validar tagging obligatorio en recursos nuevos.
6. Registrar acciones correctivas de costo en `docs/iterations/`.

## Decisiones tecnicas y alternativas descartadas
- Budgets y alertas por entorno.
- Scheduler para apagar recursos no prod cuando aplique.
- Tagging obligatorio para trazabilidad financiera.
- Controlar costo de endpoints `staging`/`prod` y ejecuciones programadas del pipeline.

## IAM usado (roles/policies/permisos clave)
- Permisos de lectura de costos y presupuesto para operador DS.
- Permisos acotados para scheduler y acciones de stop/start.
- Operador humano con usuario `data-science-user` y keys logicas `data-science-user-primary` / `data-science-user-rotation`.

## Comandos ejecutados y resultado esperado
- Regla operativa AWS: ejecutar comandos con `data-science-user` como base y perfil `data-science-user`.
- Configuracion de budgets/alerts
- Validacion de schedules de apagado
- Resultado esperado: costo dentro de umbrales definidos.

## Evidencia
Agregar umbrales, alertas configuradas y prueba de acciones programadas.

## Criterio de cierre
- Presupuestos y alertas activos por entorno.
- Programación de ahorro validada para no-producción.
- No hay recursos críticos sin tags obligatorios.

## Riesgos/pendientes
- Recursos huerfanos sin tags.
- Costos inesperados por endpoints activos 24/7.

## Proximo paso
Registrar iteraciones en `docs/iterations/`.
