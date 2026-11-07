#!/usr/bin/env groovy
/*
 * CircleGuard · Jenkins multibranch pipeline (HU-03 + HU-06)
 *
 * Flujo:
 *   checkout -> build/test (Shared Library) -> Sonar -> integración -> paquete
 *   -> imágenes -> registro -> dev -> E2E dev -> stage -> E2E stage
 *   -> aprobación manual -> prod -> tag semver
 *
 * Ramas:
 *   dev  : ejecuta CI y despliega dev y stage; no toca prod.
 *   main : ejecuta CI, despliega dev y stage, pide aprobación y despliega prod,
 *          y etiqueta la release.
 *
 * El CI reutilizable vive en la Shared Library `jenkins/vars` (HU-03) y se carga
 * de forma implícita desde `infra/bootstrap/jenkins/casc/jenkins.yaml`.
 *
 * Requisitos (HU-04):
 *   - Agente con JDK 21, Git, Bash y el Gradle wrapper versionado.
 *   - Docker + Compose si BUILD_IMAGES=true (o un agente con Docker).
 *   - Node 22 + navegadores de Playwright si se ejecuta E2E en el agente.
 *   - Credenciales: circleguard-registry, github-token, discord-webhook,
 *     circleguard-deploy (solo si DEPLOY_MODE=ssh) y nexus-credentials (HU-03).
 *   - Jenkinsfile y scripts en la raíz del repositorio.
 */

pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '20', artifactNumToKeepStr: '10'))
    timeout(time: 60, unit: 'MINUTES')
  }

  parameters {
    // HU-03: CI selectivo por servicio.
    choice(name: 'SERVICES_MODE', choices: ['changed', 'all'], description: 'changed = solo servicios modificados; all = los 8 servicios')
    string(name: 'NEXUS_URL', defaultValue: '', description: 'URL base de Nexus. Vacío omite la publicación de JAR.')
    string(name: 'NEXUS_REPOSITORY', defaultValue: 'circleguard-artifacts', description: 'Repositorio raw de Nexus')
    booleanParam(name: 'RUN_SONAR', defaultValue: true, description: 'Ejecutar SonarQube con quality gate bloqueante')

    // HU-06: entrega continua y promoción.
    string(name: 'VERSION', defaultValue: '', description: 'Semver (1.0.0). Vacío = calcular con Conventional Commits.')
    string(name: 'IMAGE_REGISTRY', defaultValue: 'localhost:5000', description: 'Registro OCI (por ejemplo <nexus-ip>:8082).')
    string(name: 'IMAGE_NAMESPACE', defaultValue: 'circleguard', description: 'Namespace de las imágenes.')
    choice(name: 'DEPLOY_MODE', choices: ['local', 'ssh'], description: 'local = Docker Compose en este agente; ssh = host de ambiente.')
    string(name: 'DEPLOY_HOST_DEV', defaultValue: '', description: 'usuario@host del ambiente dev (solo DEPLOY_MODE=ssh).')
    string(name: 'DEPLOY_HOST_STAGE', defaultValue: '', description: 'usuario@host del ambiente stage (solo DEPLOY_MODE=ssh).')
    string(name: 'DEPLOY_HOST_PROD', defaultValue: '', description: 'usuario@host del ambiente prod (solo DEPLOY_MODE=ssh).')
    string(name: 'DEPLOY_PATH', defaultValue: '/opt/circleguard/circleguard', description: 'Ruta del repositorio en el host de ambiente.')
    string(name: 'E2E_URL_DEV', defaultValue: 'http://localhost:3000', description: 'URL del cliente web de dev para Playwright.')
    string(name: 'E2E_URL_STAGE', defaultValue: 'http://localhost:3000', description: 'URL del cliente web de stage para Playwright.')
    booleanParam(name: 'BUILD_IMAGES', defaultValue: true, description: 'Construir las 9 imágenes en este pipeline.')
    booleanParam(name: 'PUBLISH_IMAGES', defaultValue: true, description: 'Publicar las imágenes en el registro.')
    booleanParam(name: 'SKIP_E2E', defaultValue: false, description: 'Omitir E2E (solo para diagnóstico; no sirve como evidencia).')
    booleanParam(name: 'FORCE_PROD', defaultValue: false, description: 'Permitir aprobación/prod desde una rama que no sea main.')
  }

  environment {
    ALL_SERVICES = 'circleguard-auth-service,circleguard-identity-service,circleguard-promotion-service,circleguard-notification-service,circleguard-form-service,circleguard-file-service,circleguard-gateway-service,circleguard-dashboard-service'
    IMAGE_REGISTRY = "${params.IMAGE_REGISTRY}"
    IMAGE_NAMESPACE = "${params.IMAGE_NAMESPACE}"
    DEPLOY_MODE = "${params.DEPLOY_MODE}"
    DEPLOY_PATH = "${params.DEPLOY_PATH}"
    DEPLOY_HOST_DEV = "${params.DEPLOY_HOST_DEV}"
    DEPLOY_HOST_STAGE = "${params.DEPLOY_HOST_STAGE}"
    DEPLOY_HOST_PROD = "${params.DEPLOY_HOST_PROD}"
  }

  triggers {
    // HU-03: webhook de GitHub cuando Jenkins es alcanzable.
    githubPush()
    // HU-01 no expone Jenkins a Internet: pollSCM evita depender de un webhook.
    pollSCM('H/5 * * * *')
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
        script {
          sh 'git fetch --tags --force origin +refs/heads/dev:refs/remotes/origin/dev || true'
          def all = env.ALL_SERVICES.split(',') as List
          def selected = cgDetectChanges(services: all, mode: params.SERVICES_MODE, baseRef: 'origin/dev')
          env.SELECTED_SERVICES = selected.join(',')
          echo "Servicios a procesar: ${env.SELECTED_SERVICES ?: 'ninguno'}"
        }
      }
    }

    stage('Prepare') {
      steps {
        script {
          // Semantic versions depend on tags; make sure the checkout has them.
          sh 'git fetch --tags --force'
          def version = params.VERSION?.trim()
          if (!version) {
            version = sh(script: './deploy/next-version.sh', returnStdout: true).trim()
            // dev/stage need a unique image per commit until main creates the stable tag.
            if (env.BRANCH_NAME && env.BRANCH_NAME != 'main') {
              def sha = env.GIT_COMMIT ? env.GIT_COMMIT.take(7) : 'dev'
              version = "${version}-${sha}"
            }
          }
          if (!(version ==~ /^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?$/)) {
            error "Versión inválida: ${version}. Use semver, por ejemplo 1.0.0."
          }
          env.VERSION = version
          echo "CircleGuard version: ${version}"
          sh './deploy/current-version.sh dev || true'
        }
      }
    }

    stage('Build') {
      when { expression { env.SELECTED_SERVICES } }
      steps {
        script { cgGradle('classes', env.SELECTED_SERVICES.split(',') as List, 'testClasses') }
      }
    }

    stage('Unit tests and coverage') {
      when { expression { env.SELECTED_SERVICES } }
      steps {
        script { cgUnitTests(env.SELECTED_SERVICES.split(',') as List) }
      }
    }

    stage('SonarQube quality gate') {
      when {
        allOf {
          expression { env.SELECTED_SERVICES }
          expression { params.RUN_SONAR }
        }
      }
      steps {
        script { cgSonar(services: env.SELECTED_SERVICES.split(',') as List, installation: 'sonarqube') }
      }
    }

    stage('Integration tests') {
      when { expression { env.SELECTED_SERVICES } }
      steps {
        script { cgIntegrationTests(env.SELECTED_SERVICES.split(',') as List) }
      }
    }

    stage('Package') {
      when { expression { env.SELECTED_SERVICES } }
      steps {
        script { cgPackage(env.SELECTED_SERVICES.split(',') as List) }
      }
    }

    stage('Package images') {
      when { expression { params.BUILD_IMAGES } }
      steps {
        sh "./deploy/build-images.sh '${env.VERSION}'"
      }
    }

    stage('Publish images') {
      when { expression { params.PUBLISH_IMAGES } }
      steps {
        withCredentials([usernamePassword(
          credentialsId: 'circleguard-registry',
          usernameVariable: 'REGISTRY_USER',
          passwordVariable: 'REGISTRY_PASSWORD'
        )]) {
          sh "./deploy/publish-images.sh '${env.VERSION}'"
        }
      }
    }

    stage('Publish artifacts') {
      when {
        allOf {
          expression { env.SELECTED_SERVICES }
          anyOf { branch 'dev'; branch 'main' }
        }
      }
      steps {
        script {
          cgPublish(
            services: env.SELECTED_SERVICES.split(',') as List,
            nexusUrl: params.NEXUS_URL,
            repository: params.NEXUS_REPOSITORY,
            version: "${env.BRANCH_NAME}-${env.BUILD_NUMBER}"
          )
        }
      }
    }

    stage('Deploy dev') {
      when { anyOf { branch 'dev'; branch 'main' } }
      steps {
        script {
          env.TARGET_ENV = 'dev'
          deployEnv('dev')
        }
      }
    }

    stage('E2E dev') {
      when {
        allOf {
          anyOf { branch 'dev'; branch 'main' }
          expression { !params.SKIP_E2E }
        }
      }
      steps {
        script {
          env.TARGET_ENV = 'dev'
          withEnv(["E2E_BASE_URL=${params.E2E_URL_DEV}"]) {
            sh './deploy/e2e.sh dev'
          }
        }
      }
    }

    stage('Deploy stage') {
      // Promotion to stage is gated by the dev E2E result.
      when {
        allOf {
          anyOf { branch 'dev'; branch 'main' }
          expression { !params.SKIP_E2E }
        }
      }
      steps {
        script {
          env.TARGET_ENV = 'stage'
          deployEnv('stage')
        }
      }
    }

    stage('E2E stage') {
      when {
        allOf {
          anyOf { branch 'dev'; branch 'main' }
          expression { !params.SKIP_E2E }
        }
      }
      steps {
        script {
          env.TARGET_ENV = 'stage'
          withEnv(["E2E_BASE_URL=${params.E2E_URL_STAGE}"]) {
            sh './deploy/e2e.sh stage'
          }
        }
      }
    }

    stage('Approve prod') {
      when {
        allOf {
          anyOf {
            branch 'main'
            expression { params.FORCE_PROD }
          }
          expression { !params.SKIP_E2E }
        }
      }
      steps {
        timeout(time: 24, unit: 'HOURS') {
          input message: "¿Desplegar ${env.VERSION} a prod?", ok: 'Desplegar a prod', submitter: 'admin'
        }
      }
    }

    stage('Deploy prod') {
      when {
        allOf {
          anyOf {
            branch 'main'
            expression { params.FORCE_PROD }
          }
          expression { !params.SKIP_E2E }
        }
      }
      steps {
        script {
          env.TARGET_ENV = 'prod'
          deployEnv('prod')
        }
      }
    }

    stage('Tag release') {
      when {
        allOf {
          anyOf {
            branch 'main'
            expression { params.FORCE_PROD }
          }
          expression { !params.SKIP_E2E }
        }
      }
      steps {
        withCredentials([string(credentialsId: 'github-token', variable: 'GITHUB_TOKEN')]) {
          sh "./deploy/tag-release.sh '${env.VERSION}'"
        }
      }
    }

  }

  post {
    always {
      archiveArtifacts artifacts: 'deploy/releases/*.json,deploy/releases/*.tsv,tests/e2e-playwright/results.xml,tests/e2e-playwright/playwright-report/**', allowEmptyArchive: true
      script {
        catchError(buildResult: 'UNSTABLE', stageResult: 'UNSTABLE') {
          junit allowEmptyResults: true, testResults: 'tests/e2e-playwright/results.xml'
        }
      }
    }
    success {
      script { notify('success', 'Pipeline completado') }
    }
    unstable {
      script { notify('unstable', 'Pipeline completado con advertencias (tests base)') }
    }
    failure {
      script { notify('failure', 'Pipeline falló') }
    }
    cleanup { cleanWs(deleteDirs: true, notFailBuild: true) }
  }
}

/**
 * Deploys one environment. For ssh, loads the deploy key; for local, uses the
 * Docker daemon of the agent.
 */
def deployEnv(String envName) {
  if (env.DEPLOY_MODE == 'ssh') {
    withCredentials([sshUserPrivateKey(
      credentialsId: 'circleguard-deploy',
      keyFileVariable: 'DEPLOY_SSH_KEY'
    )]) {
      sh "./deploy/deploy.sh '${envName}' '${env.VERSION}'"
    }
  } else {
    sh "./deploy/deploy.sh '${envName}' '${env.VERSION}'"
  }
}

/**
 * Sends a notification if the discord-webhook credential exists. A missing
 * notification must never fail the deployment.
 */
def notify(String status, String message) {
  try {
    withCredentials([string(credentialsId: 'discord-webhook', variable: 'DISCORD_WEBHOOK_URL')]) {
      sh "./deploy/notify.sh '${status}' '${env.TARGET_ENV ?: 'ci'}' '${env.VERSION ?: 'unknown'}' '${message}'"
    }
  } catch (Exception exc) {
    echo "Notificación omitida: ${exc.message}"
  }
}
