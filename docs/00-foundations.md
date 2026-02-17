# 00 Foundations

## Objetivo y contexto
Definir base del proyecto: cuenta AWS, backend de Terraform state, convenciones de naming/tagging, estrategia de ambientes (`dev` y `prod`) y reglas de colaboracion.

## Decisiones tecnicas y alternativas descartadas
- IaC estandar: Terraform.
- CI/CD estandar: GitHub Actions.
- Ambientes: `dev` y `prod`.
- Alternativas descartadas: despliegues manuales sin pipeline.

## IAM usado (roles/policies/permisos clave)
- Usuario operador DS con permisos minimos para ejecutar pipelines y leer observabilidad.
- Roles de ejecucion por servicio (SageMaker, Lambda, Step Functions, ECS).
- `iam:PassRole` restringido a roles esperados.

## Comandos ejecutados y resultado esperado
- `terraform fmt -check`
- `terraform validate`
- `terraform plan`
- Resultado esperado: plan limpio y recursos con tags obligatorios.

## Evidencia
Agregar aqui salidas de plan, decisiones de backend state y convenciones aprobadas.

## Riesgos/pendientes
- Definir limites iniciales de costos.
- Validar permisos exactos para cada modulo.

## Proximo paso
Avanzar a ingestion y gobierno de datos en `docs/01-data-ingestion.md`.
