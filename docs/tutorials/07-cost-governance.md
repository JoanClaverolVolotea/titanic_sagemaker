# 07 Cost and Governance

## Objetivo y contexto
Definir controles de costo y gobierno que solo dependan de patrones visibles en la
documentacion local del SageMaker SDK V3 y en los scripts del repositorio.

Esta fase ya no prescribe budgets, schedulers o APIs de billing externas al alcance del SDK
vendoreado. Se centra en los costos que el proyecto realmente controla desde su flujo
SageMaker: training jobs, processing jobs, model registry y endpoints.

## Resultado minimo esperado
1. Los recursos runtime de SageMaker se mantienen pequenos por defecto.
2. `staging` se elimina cuando ya no aporta evidencia.
3. El proyecto puede listar recursos activos con el script local.
4. La limpieza de recursos y artefactos queda documentada.

## Fuentes locales alineadas con SDK V3
1. `vendor/sagemaker-python-sdk/docs/quickstart.rst`
2. `vendor/sagemaker-python-sdk/docs/inference/index.rst`
3. `vendor/sagemaker-python-sdk/docs/training/index.rst`
4. `vendor/sagemaker-python-sdk/docs/ml_ops/index.rst`
5. `vendor/sagemaker-python-sdk/docs/sagemaker_core/index.rst`
6. `vendor/sagemaker-python-sdk/migration.md`

## Archivos locales usados en esta fase
- `scripts/check_tutorial_resources_active.sh`
- `scripts/reset_tutorial_state.sh`

## Bootstrap auto-contenido

Variables minimas para ejecutar esta fase desde cero:

```bash
eval "$(python3 scripts/resolve_project_env.py --emit-exports)"
```

## Contrato minimo de costo

### Defaults pequenos del roadmap
| Recurso | Default del tutorial | Motivo |
|---|---|---|
| Processing | `ml.m5.large`, `instance_count=1` | Mantener costo y complejidad bajos |
| Training | `ml.m5.large`, `instance_count=1` | Baseline suficiente para Titanic |
| Hosting | `ml.m5.large`, `initial_instance_count=1` | Smoke y serving basico |
| Approval | `PendingManualApproval` | Evitar deploys innecesarios |

### Reglas del proyecto
1. No mantener endpoints de experimentacion fuera de `staging` y `prod`.
2. No crear endpoints antes de que exista `ModelPackageArn`.
3. Borrar `staging` al terminar validaciones si no se necesita 24/7.
4. Mantener el registro de recursos activos en cada iteracion.

## Entregable 1 -- Revision de recursos activos

```bash
AWS_PROFILE=data-science-user scripts/check_tutorial_resources_active.sh --phase all
```

Para una revision centrada en serving:

```bash
AWS_PROFILE=data-science-user scripts/check_tutorial_resources_active.sh --phase 04
```

## Entregable 2 -- Cleanup de endpoints no esenciales

Patron alineado con el quickstart local: eliminar endpoints cuando terminan su utilidad.

```python
# Si conservas el objeto endpoint del deploy, puedes usar el patron del quickstart:
# staging_endpoint.delete()
```

Si necesitas rehacer una fase completa:

```bash
scripts/reset_tutorial_state.sh --target after-tutorial-2
scripts/reset_tutorial_state.sh --target after-tutorial-2 --apply --confirm RESET
```

## Entregable 3 -- Higiene de artefactos runtime

Prefijos que deben revisarse periodicamente:
- `s3://$DATA_BUCKET/training/xgboost/output/`
- `s3://$DATA_BUCKET/evaluation/xgboost/`
- `s3://$DATA_BUCKET/pipeline/runtime/$PIPELINE_NAME/`

Checklist operativo minimo:
1. Confirmar que el ultimo training job necesario ya termino.
2. Confirmar que el ultimo pipeline execution necesario ya termino.
3. Eliminar `staging` si no sigue en validacion activa.
4. Registrar en `docs/iterations/` que recursos quedaron vivos y por que.

## Entregable 4 -- Gobierno de despliegue

Reglas de gobierno derivadas del flujo V3:
- Solo desplegar desde `ModelPackageArn`.
- Mantener `PendingManualApproval` hasta que exista evidencia de calidad.
- El smoke test es obligatorio antes de tocar `prod`.
- El rollback se hace redeployando un package aprobado anterior, no reutilizando artefactos
  sueltos del training job.

## Alcance explicitamente excluido de este tutorial
Quedan fuera de alcance aqui porque no estan cubiertos por la documentacion local del SDK y
el repo no aporta una implementacion canonica asociada:
- budgets de billing,
- cost explorer,
- schedulers fuera del flujo SageMaker,
- automatismos de apagado con otros servicios AWS.

Si esas capacidades se agregan despues, deben documentarse como una capa adicional, no como
parte del estandar minimo V3 de este roadmap.

## Decisiones tecnicas y alternativas descartadas
- Se gobierna el costo a partir de recursos reales de SageMaker, no desde herramientas
  externas al tutorial.
- Se favorece cleanup explicito de endpoints sobre mantener capacidad encendida por defecto.
- Se descarta promover a prod un modelo no registrado.
- Se descarta usar endpoints manuales efimeros como sustituto permanente del registry.

## IAM usado (roles/policies/permisos clave)
- Perfil operativo: `data-science-user`.
- `DataScienceObservabilityReadOnly` para `scripts/check_tutorial_resources_active.sh`.
- `DataSciences3DataAccess` para revisar y limpiar prefijos runtime del bucket del tutorial.
- `DataScienceSageMakerTrainingJobLifecycle` para training jobs.
- `DataScienceSageMakerCleanupNonProd` para endpoints, endpoint configs, models, pipelines y
  Model Registry en no-prod.
- `DataScienceServiceQuotasReadOnly` si incluyes validaciones de quotas en el checklist.

## Evidencia requerida
1. Salida de `scripts/check_tutorial_resources_active.sh`.
2. Inventario de endpoints activos.
3. Nota de cleanup aplicado o justificacion de por que un recurso sigue vivo.

## Criterio de cierre
- El proyecto puede explicar que recursos SageMaker generan costo.
- Existe un patron claro para apagar `staging` y revisar artefactos runtime.
- El despliegue a `prod` se mantiene gobernado por registry + smoke test.

## Riesgos/pendientes
- Si `staging` se deja activo sin necesidad, el costo sube sin nueva evidencia.
- Si no se revisan los prefijos runtime, se acumulan artefactos innecesarios.
- Las capacidades de billing fuera de SageMaker siguen pendientes de documentacion separada.

## Proximo paso
Registrar cada limpieza, promocion y excepcion de costo en `docs/iterations/`.
