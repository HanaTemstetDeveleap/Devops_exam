// =============================================================================
// Job DSL Script - Creates 4 Jenkins Pipeline Jobs Automatically
// =============================================================================
// This script creates:
// - CI-Service1: Builds and pushes Service 1 Docker image
// - CI-Service2: Builds and pushes Service 2 Docker image
// - CD-Service1: Deploys Service 1 to ECS
// - CD-Service2: Deploys Service 2 to ECS
// =============================================================================

// Git repository URL - REPLACE WITH YOUR ACTUAL REPO
def gitRepo = 'https://github.com/YOUR_USERNAME/YOUR_REPO.git'
def gitBranch = '*/main'
def gitCredentialsId = 'git-credentials'  // Will be created manually or can be skipped if repo is public

// =============================================================================
// CI Job for Service 1 (REST API)
// =============================================================================
pipelineJob('CI-Service1') {
    description('CI Pipeline - Builds and pushes Service 1 (REST API) Docker image to ECR')

    properties {
        disableConcurrentBuilds()
    }

    triggers {
        // Poll Git every 5 minutes for changes
        scm('H/5 * * * *')
    }

    definition {
        cpsScm {
            scm {
                git {
                    remote {
                        url(gitRepo)
                        // Uncomment if using private repo:
                        // credentials(gitCredentialsId)
                    }
                    branches(gitBranch)
                    extensions {
                        // Only trigger if Service 1 files changed
                        pathRestriction {
                            includedRegions('microservices/service1-api/.*')
                            excludedRegions('')
                        }
                    }
                }
            }
            scriptPath('jenkins/pipelines/Jenkinsfile-CI-Service1')
            lightweight(true)
        }
    }
}

// =============================================================================
// CI Job for Service 2 (SQS Consumer)
// =============================================================================
pipelineJob('CI-Service2') {
    description('CI Pipeline - Builds and pushes Service 2 (SQS Consumer) Docker image to ECR')

    properties {
        disableConcurrentBuilds()
    }

    triggers {
        // Poll Git every 5 minutes for changes
        scm('H/5 * * * *')
    }

    definition {
        cpsScm {
            scm {
                git {
                    remote {
                        url(gitRepo)
                        // Uncomment if using private repo:
                        // credentials(gitCredentialsId)
                    }
                    branches(gitBranch)
                    extensions {
                        // Only trigger if Service 2 files changed
                        pathRestriction {
                            includedRegions('microservices/service2-consumer/.*')
                            excludedRegions('')
                        }
                    }
                }
            }
            scriptPath('jenkins/pipelines/Jenkinsfile-CI-Service2')
            lightweight(true)
        }
    }
}

// =============================================================================
// CD Job for Service 1 (REST API)
// =============================================================================
pipelineJob('CD-Service1') {
    description('CD Pipeline - Deploys Service 1 (REST API) to ECS')

    properties {
        disableConcurrentBuilds()
    }

    parameters {
        stringParam('IMAGE_VERSION', 'latest', 'Docker image version to deploy (build number or "latest")')
    }

    definition {
        cpsScm {
            scm {
                git {
                    remote {
                        url(gitRepo)
                        // Uncomment if using private repo:
                        // credentials(gitCredentialsId)
                    }
                    branches(gitBranch)
                }
            }
            scriptPath('jenkins/pipelines/Jenkinsfile-CD-Service1')
            lightweight(true)
        }
    }
}

// =============================================================================
// CD Job for Service 2 (SQS Consumer)
// =============================================================================
pipelineJob('CD-Service2') {
    description('CD Pipeline - Deploys Service 2 (SQS Consumer) to ECS')

    properties {
        disableConcurrentBuilds()
    }

    parameters {
        stringParam('IMAGE_VERSION', 'latest', 'Docker image version to deploy (build number or "latest")')
    }

    definition {
        cpsScm {
            scm {
                git {
                    remote {
                        url(gitRepo)
                        // Uncomment if using private repo:
                        // credentials(gitCredentialsId)
                    }
                    branches(gitBranch)
                }
            }
            scriptPath('jenkins/pipelines/Jenkinsfile-CD-Service2')
            lightweight(true)
        }
    }
}

println("✅ Job DSL script completed!")
println("Created 4 jobs:")
println("  - CI-Service1")
println("  - CI-Service2")
println("  - CD-Service1")
println("  - CD-Service2")
