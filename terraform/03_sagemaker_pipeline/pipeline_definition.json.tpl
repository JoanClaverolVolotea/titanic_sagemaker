{
  "Version": "2020-12-01",
  "Metadata": {},
  "Parameters": [
    {
      "Name": "CodeBundleUri",
      "Type": "String",
      "DefaultValue": "${code_bundle_uri}"
    },
    {
      "Name": "InputTrainUri",
      "Type": "String",
      "DefaultValue": "s3://${data_bucket_name}/curated/train.csv"
    },
    {
      "Name": "InputValidationUri",
      "Type": "String",
      "DefaultValue": "s3://${data_bucket_name}/curated/validation.csv"
    },
    {
      "Name": "AccuracyThreshold",
      "Type": "Float",
      "DefaultValue": ${quality_threshold_accuracy}
    }
  ],
  "PipelineExperimentConfig": {
    "ExperimentName": {
      "Get": "Execution.PipelineName"
    },
    "TrialName": {
      "Get": "Execution.PipelineExecutionId"
    }
  },
  "Steps": [
    {
      "Name": "DataPreProcessing",
      "Type": "Processing",
      "Arguments": {
        "ProcessingResources": {
          "ClusterConfig": {
            "InstanceType": "ml.m5.large",
            "InstanceCount": 1,
            "VolumeSizeInGB": 30
          }
        },
        "AppSpecification": {
          "ImageUri": "${processing_image_uri}",
          "ContainerArguments": [
            "--input-train-uri",
            {
              "Get": "Parameters.InputTrainUri"
            },
            "--input-validation-uri",
            {
              "Get": "Parameters.InputValidationUri"
            },
            "--code-bundle-uri",
            {
              "Get": "Parameters.CodeBundleUri"
            }
          ],
          "ContainerEntrypoint": [
            "python3",
            "/opt/ml/processing/input/code/preprocess.py"
          ]
        },
        "RoleArn": "${pipeline_role_arn}",
        "ProcessingInputs": [
          {
            "InputName": "code",
            "AppManaged": false,
            "S3Input": {
              "S3Uri": "s3://${data_bucket_name}/pipeline/code/scripts/preprocess.py",
              "LocalPath": "/opt/ml/processing/input/code",
              "S3DataType": "S3Prefix",
              "S3InputMode": "File",
              "S3DataDistributionType": "FullyReplicated",
              "S3CompressionType": "None"
            }
          }
        ],
        "ProcessingOutputConfig": {
          "Outputs": [
            {
              "OutputName": "train",
              "AppManaged": false,
              "S3Output": {
                "S3Uri": "s3://${data_bucket_name}/pipeline/runtime/${pipeline_name}/preprocess/train",
                "LocalPath": "/opt/ml/processing/output/train",
                "S3UploadMode": "EndOfJob"
              }
            },
            {
              "OutputName": "validation",
              "AppManaged": false,
              "S3Output": {
                "S3Uri": "s3://${data_bucket_name}/pipeline/runtime/${pipeline_name}/preprocess/validation",
                "LocalPath": "/opt/ml/processing/output/validation",
                "S3UploadMode": "EndOfJob"
              }
            }
          ]
        }
      },
      "CacheConfig": {
        "Enabled": true,
        "ExpireAfter": "30d"
      }
    },
    {
      "Name": "TrainModel",
      "Type": "Training",
      "Arguments": {
        "AlgorithmSpecification": {
          "TrainingInputMode": "File",
          "TrainingImage": "${training_image_uri}"
        },
        "OutputDataConfig": {
          "S3OutputPath": "s3://${data_bucket_name}/pipeline/runtime/${pipeline_name}/training"
        },
        "StoppingCondition": {
          "MaxRuntimeInSeconds": 86400
        },
        "ResourceConfig": {
          "VolumeSizeInGB": 30,
          "InstanceCount": 1,
          "InstanceType": "ml.m5.large"
        },
        "RoleArn": "${pipeline_role_arn}",
        "InputDataConfig": [
          {
            "DataSource": {
              "S3DataSource": {
                "S3DataType": "S3Prefix",
                "S3Uri": {
                  "Get": "Steps.DataPreProcessing.ProcessingOutputConfig.Outputs['train'].S3Output.S3Uri"
                },
                "S3DataDistributionType": "FullyReplicated"
              }
            },
            "ContentType": "text/csv",
            "ChannelName": "train"
          },
          {
            "DataSource": {
              "S3DataSource": {
                "S3DataType": "S3Prefix",
                "S3Uri": {
                  "Get": "Steps.DataPreProcessing.ProcessingOutputConfig.Outputs['validation'].S3Output.S3Uri"
                },
                "S3DataDistributionType": "FullyReplicated"
              }
            },
            "ContentType": "text/csv",
            "ChannelName": "validation"
          }
        ],
        "HyperParameters": {
          "objective": "binary:logistic",
          "num_round": "200",
          "max_depth": "5",
          "eta": "0.2",
          "subsample": "0.8",
          "eval_metric": "logloss"
        },
        "DebugHookConfig": {
          "S3OutputPath": "s3://${data_bucket_name}/pipeline/runtime/${pipeline_name}/training",
          "CollectionConfigurations": []
        },
        "ProfilerConfig": {
          "S3OutputPath": "s3://${data_bucket_name}/pipeline/runtime/${pipeline_name}/training",
          "DisableProfiler": false
        }
      },
      "CacheConfig": {
        "Enabled": true,
        "ExpireAfter": "30d"
      }
    },
    {
      "Name": "ModelEvaluation",
      "Type": "Processing",
      "Arguments": {
        "ProcessingResources": {
          "ClusterConfig": {
            "InstanceType": "ml.m5.large",
            "InstanceCount": 1,
            "VolumeSizeInGB": 30
          }
        },
        "AppSpecification": {
          "ImageUri": "${evaluation_image_uri}",
          "ContainerArguments": [
            "--accuracy-threshold",
            {
              "Std:Join": {
                "On": "",
                "Values": [
                  {
                    "Get": "Parameters.AccuracyThreshold"
                  }
                ]
              }
            }
          ],
          "ContainerEntrypoint": [
            "python3",
            "/opt/ml/processing/input/code/evaluate.py"
          ]
        },
        "RoleArn": "${pipeline_role_arn}",
        "ProcessingInputs": [
          {
            "InputName": "input-1",
            "AppManaged": false,
            "S3Input": {
              "S3Uri": {
                "Get": "Steps.TrainModel.ModelArtifacts.S3ModelArtifacts"
              },
              "LocalPath": "/opt/ml/processing/model",
              "S3DataType": "S3Prefix",
              "S3InputMode": "File",
              "S3DataDistributionType": "FullyReplicated",
              "S3CompressionType": "None"
            }
          },
          {
            "InputName": "input-2",
            "AppManaged": false,
            "S3Input": {
              "S3Uri": {
                "Get": "Steps.DataPreProcessing.ProcessingOutputConfig.Outputs['validation'].S3Output.S3Uri"
              },
              "LocalPath": "/opt/ml/processing/validation",
              "S3DataType": "S3Prefix",
              "S3InputMode": "File",
              "S3DataDistributionType": "FullyReplicated",
              "S3CompressionType": "None"
            }
          },
          {
            "InputName": "code",
            "AppManaged": false,
            "S3Input": {
              "S3Uri": "s3://${data_bucket_name}/pipeline/code/scripts/evaluate.py",
              "LocalPath": "/opt/ml/processing/input/code",
              "S3DataType": "S3Prefix",
              "S3InputMode": "File",
              "S3DataDistributionType": "FullyReplicated",
              "S3CompressionType": "None"
            }
          }
        ],
        "ProcessingOutputConfig": {
          "Outputs": [
            {
              "OutputName": "evaluation",
              "AppManaged": false,
              "S3Output": {
                "S3Uri": "s3://${data_bucket_name}/pipeline/runtime/${pipeline_name}/evaluation",
                "LocalPath": "/opt/ml/processing/evaluation",
                "S3UploadMode": "EndOfJob"
              }
            }
          ]
        }
      },
      "CacheConfig": {
        "Enabled": true,
        "ExpireAfter": "30d"
      },
      "PropertyFiles": [
        {
          "PropertyFileName": "EvaluationReport",
          "OutputName": "evaluation",
          "FilePath": "evaluation.json"
        }
      ]
    },
    {
      "Name": "QualityGateAccuracy",
      "Type": "Condition",
      "Arguments": {
        "Conditions": [
          {
            "Type": "GreaterThanOrEqualTo",
            "LeftValue": {
              "Std:JsonGet": {
                "PropertyFile": {
                  "Get": "Steps.ModelEvaluation.PropertyFiles.EvaluationReport"
                },
                "Path": "metrics.accuracy"
              }
            },
            "RightValue": {
              "Get": "Parameters.AccuracyThreshold"
            }
          }
        ],
        "IfSteps": [
          {
            "Name": "RegisterModel-RegisterModel",
            "Type": "RegisterModel",
            "Arguments": {
              "ModelPackageGroupName": "${model_package_group_name}",
              "ModelMetrics": {
                "ModelQuality": {
                  "Statistics": {
                    "ContentType": "application/json",
                    "S3Uri": {
                      "Std:Join": {
                        "On": "/",
                        "Values": [
                          {
                            "Get": "Steps.ModelEvaluation.ProcessingOutputConfig.Outputs['evaluation'].S3Output.S3Uri"
                          },
                          "evaluation.json"
                        ]
                      }
                    }
                  }
                },
                "Bias": {},
                "Explainability": {}
              },
              "InferenceSpecification": {
                "Containers": [
                  {
                    "Image": "${training_image_uri}",
                    "ModelDataUrl": {
                      "Get": "Steps.TrainModel.ModelArtifacts.S3ModelArtifacts"
                    }
                  }
                ],
                "SupportedContentTypes": [
                  "text/csv"
                ],
                "SupportedResponseMIMETypes": [
                  "text/csv"
                ],
                "SupportedRealtimeInferenceInstanceTypes": [
                  "ml.m5.large"
                ],
                "SupportedTransformInstanceTypes": [
                  "ml.m5.large"
                ]
              },
              "ModelApprovalStatus": "${model_approval_status}",
              "SkipModelValidation": "None"
            }
          }
        ],
        "ElseSteps": []
      }
    }
  ]
}
