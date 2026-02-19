# 04 Serving ECS and SageMaker

## Objetivo y contexto
Publicar inferencia de forma controlada con endpoint de SageMaker y, si aplica, capa de servicio en ECS/Fargate.

## Paso a paso (ejecucion)
1. Seleccionar `ModelPackage` de fase 03 en Model Registry.
   - Si esta en `PendingManualApproval`, ejecutar aprobacion antes de promover a despliegue.
2. Desplegar endpoint `staging` con ese modelo.
3. Ejecutar smoke tests contra `staging` (salud, respuesta, latencia base).
4. Revisar resultados de smoke tests:
   - si falla: rollback/hold,
   - si pasa: continuar.
5. Ejecutar gate de aprobación manual.
6. Desplegar endpoint `prod`.
7. (Opcional) Exponer endpoint vía capa ECS/Fargate para consumo API.
8. Aplicar convencion de limpieza:
   - nombres de endpoints/configs con prefijo `titanic-`,
   - tags `project=titanic-sagemaker` y `tutorial_phase=04`.

## Decisiones tecnicas y alternativas descartadas
- Endpoint update solo con modelo validado/registrado.
- Consumir exclusivamente `ModelPackageArn` producido en fase 03 (sin bypass de registry).
- Estrategia de despliegue:
  - desplegar primero a endpoint `staging`,
  - correr smoke tests,
  - promover a endpoint `prod` solo con gate manual.
- ECS opcional para API o integracion adicional.
- Naming/tagging consistente para habilitar cleanup por script (`--target all`).
- Alternativas descartadas: update directo sin gate.

## IAM usado (roles/policies/permisos clave)
- SageMaker endpoint roles.
- ECS task execution/task role con permisos minimos.
- Operador humano con usuario `data-science-user` y keys logicas `data-science-user-primary` / `data-science-user-rotation`.

## Comandos ejecutados y resultado esperado
- Regla operativa AWS: ejecutar comandos con `data-science-user` como base y perfil `data-science-user`.
- `terraform plan` del modulo de serving
- Deploy de endpoint `staging` con modelo registrado
- Smoke tests de inferencia sobre `staging`
- Deploy a `prod` solo tras aprobacion manual
- Resultado esperado: `staging` y `prod` estables, respuesta valida y rollout controlado.

## Evidencia
Agregar:
- Endpoint names/ARN de `staging` y `prod`.
- Resultados de smoke tests en `staging`.
- Evidencia de aprobacion manual para despliegue a `prod`.
- Latencia base y tasa de error inicial.

## Criterio de cierre
- Existe endpoint `staging` con smoke tests exitosos.
- Gate manual ejecutado y documentado.
- Endpoint `prod` desplegado con modelo trazable al registry.

## Riesgos/pendientes
- Sobreaprovisionamiento de instancias.
- Falta de rollback rapido de endpoint.

## Proximo paso
Conectar CI/CD en `docs/tutorials/05-cicd-github-actions.md`.
