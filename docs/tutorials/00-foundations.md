# 00 Foundations

## Objetivo y contexto
Definir base del proyecto: cuenta AWS, backend de Terraform state, convenciones de naming/tagging, estrategia de ambientes (`dev` y `prod`) y reglas de colaboracion.

## Paso a paso (ejecucion)
1. Confirmar identidad operativa con el perfil unico `data-science-user`.
2. Validar acceso AWS por perfil:
   - `aws sts get-caller-identity --profile data-science-user`
3. Definir convenciones globales:
   - naming de recursos,
   - tags obligatorios,
   - separacion `dev`/`prod`.
4. Validar base Terraform del modulo actual:
   - `terraform fmt -check`
   - `terraform validate`
   - `terraform plan`
5. Aprobar arquitectura objetivo:
   - ModelBuild CI (`Processing -> Training -> Evaluation -> Register`),
   - ModelDeploy CD (`staging -> manual approval -> prod`).

## Decisiones tecnicas y alternativas descartadas
- IaC estandar: Terraform.
- CI/CD estandar: GitHub Actions.
- Ambientes: `dev` y `prod`.
- Arquitectura objetivo: ModelBuild CI (preprocess/train/evaluate/register) + ModelDeploy CD (staging/manual approval/prod).
- Alternativas descartadas: despliegues manuales sin pipeline.

## IAM usado (roles/policies/permisos clave)
- Usuario operador DS con permisos minimos para ejecutar pipelines y leer observabilidad.
- Usuario IAM oficial: `data-science-user`.
- Access keys logicas del usuario: `data-science-user-primary` (activa) y `data-science-user-rotation` (reserva).
- Perfil AWS CLI oficial: `data-science-user`.
- Roles de ejecucion por servicio (SageMaker, Lambda, Step Functions, ECS).
- `iam:PassRole` restringido a roles esperados.

## Comandos ejecutados y resultado esperado
- Regla operativa AWS: ejecutar comandos con `data-science-user` como base y perfil `data-science-user`.
- `terraform fmt -check`
- `terraform validate`
- `terraform plan`
- Resultado esperado: plan limpio y recursos con tags obligatorios.

## Entregable minimo de esta fase
- Checklist de arquitectura aprobado con estos bloques:
  - SageMaker Pipeline con pasos de `Processing -> Training -> Evaluation -> Register`.
  - Model Registry obligatorio antes de cualquier deployment.
  - Pipeline de despliegue con endpoint `staging`, gate manual y despliegue a `prod`.

## Criterio de cierre
- Identidad y perfil AWS validados.
- Convenciones y tags documentados.
- `terraform plan` revisado sin sorpresas.
- Arquitectura objetivo aprobada y trazada a fases `01..07`.

## Evidencia
Agregar aqui salidas de plan, decisiones de backend state y convenciones aprobadas.

## Riesgos/pendientes
- Definir limites iniciales de costos.
- Validar permisos exactos para cada modulo.

## Proximo paso
Avanzar a ingestion y gobierno de datos en `docs/tutorials/01-data-ingestion.md`.
