# 01 Data Ingestion

## Objetivo y contexto
Implementar carga y versionado de datos Titanic en S3, con separacion de raw, curated y artefactos.

## Decisiones tecnicas y alternativas descartadas
- Estructura S3 por entorno (`dev`/`prod`).
- Convencion de paths para train/validation.
- Alternativas descartadas: datasets sin versionado.

## IAM usado (roles/policies/permisos clave)
- Permisos S3 acotados por bucket/prefix.
- Acceso de lectura para entrenamiento y escritura para outputs.

## Comandos ejecutados y resultado esperado
- `aws s3 ls`
- `terraform plan` del modulo de datos
- Resultado esperado: bucket/prefix listos y acceso validado.

## Evidencia
Agregar rutas S3 finales y prueba de lectura/escritura por rol.

## Riesgos/pendientes
- Politicas demasiado amplias en S3.
- Falta de cifrado o lifecycle policies.

## Proximo paso
Configurar entrenamiento y validacion en `docs/02-training-validation.md`.
