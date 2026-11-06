pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '20', artifactNumToKeepStr: '10'))
    timeout(time: 60, unit: 'MINUTES')
  }

  triggers {
    githubPush()
    pollSCM('H/15 * * * *')
  }

  parameters {
    choice(name: 'SERVICES_MODE', choices: ['changed', 'all'], description: 'changed = solo servicios modificados; all = los 8 servicios')
    string(name: 'NEXUS_URL', defaultValue: '', description: 'URL base de Nexus. Vacío omite la publicación.')
    string(name: 'NEXUS_REPOSITORY', defaultValue: 'circleguard-artifacts', description: 'Repositorio raw de Nexus')
    booleanParam(name: 'RUN_SONAR', defaultValue: true, description: 'Ejecutar SonarQube con quality gate bloqueante')
  }

  environment {
    ALL_SERVICES = 'circleguard-auth-service,circleguard-identity-service,circleguard-promotion-service,circleguard-notification-service,circleguard-form-service,circleguard-file-service,circleguard-gateway-service,circleguard-dashboard-service'
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

    stage('Publish') {
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
  }

  post {
    success { script { cgNotify('success', 'Pipeline CI completado') } }
    unstable { script { cgNotify('unstable', 'Pipeline CI inestable') } }
    failure { script { cgNotify('failure', 'Pipeline CI falló') } }
    cleanup { cleanWs(deleteDirs: true, notFailBuild: true) }
  }
}
