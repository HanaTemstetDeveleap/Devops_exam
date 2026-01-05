#!/bin/bash
# =============================================================================
# Jenkins Bootstrap Script
# Automatically installs Jenkins, plugins, and creates CI/CD jobs
# =============================================================================

set -e  # Exit on any error

echo "===================================================================="
echo "Starting Jenkins installation..."
echo "===================================================================="

# Update system
apt-get update
apt-get upgrade -y

# Install prerequisites
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    git \
    unzip \
    xmlstarlet

# =============================================================================
# Install Docker
# =============================================================================
echo "Installing Docker..."

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io

systemctl start docker
systemctl enable docker

# =============================================================================
# Install AWS CLI v2
# =============================================================================
echo "Installing AWS CLI..."

curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
rm -rf aws awscliv2.zip

# =============================================================================
# Install Java (required for Jenkins)
# =============================================================================
echo "Installing Java 17..."

apt-get install -y openjdk-17-jdk

# =============================================================================
# Install Jenkins
# =============================================================================
echo "Installing Jenkins..."

curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | tee \
  /usr/share/keyrings/jenkins-keyring.asc > /dev/null

echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
  https://pkg.jenkins.io/debian-stable binary/ | tee \
  /etc/apt/sources.list.d/jenkins.list > /dev/null

apt-get update
apt-get install -y jenkins

# Add jenkins user to docker group
usermod -aG docker jenkins

# Start Jenkins
systemctl start jenkins
systemctl enable jenkins

# =============================================================================
# Wait for Jenkins to start
# =============================================================================
echo "Waiting for Jenkins to start..."
sleep 60

# Get initial admin password
JENKINS_PASSWORD=$(cat /var/lib/jenkins/secrets/initialAdminPassword)
echo "Jenkins Initial Admin Password: $JENKINS_PASSWORD"

# Store password in SSM Parameter Store
aws ssm put-parameter \
    --name "/jenkins/initial-admin-password" \
    --value "$JENKINS_PASSWORD" \
    --type "SecureString" \
    --region us-east-1 \
    --overwrite || echo "Failed to store password in SSM"

# =============================================================================
# Install Jenkins Plugins via CLI
# =============================================================================
echo "Installing Jenkins plugins..."

# Download Jenkins CLI
JENKINS_CLI="/tmp/jenkins-cli.jar"
wget -O $JENKINS_CLI http://localhost:8080/jnlpJars/jenkins-cli.jar
sleep 10

# Install plugins
PLUGINS=(
    "git"
    "workflow-aggregator"
    "docker-workflow"
    "job-dsl"
    "credentials"
    "credentials-binding"
)

for plugin in "${PLUGINS[@]}"; do
    echo "Installing plugin: $plugin"
    java -jar $JENKINS_CLI -s http://localhost:8080/ -auth admin:$JENKINS_PASSWORD install-plugin $plugin -deploy || echo "Plugin $plugin may already be installed"
done

# Restart Jenkins to load plugins
echo "Restarting Jenkins to load plugins..."
java -jar $JENKINS_CLI -s http://localhost:8080/ -auth admin:$JENKINS_PASSWORD safe-restart
sleep 90

# =============================================================================
# Create Job DSL Seed Job
# =============================================================================
echo "Creating Job DSL seed job..."

# Create jobs.groovy file
cat > /tmp/jobs.groovy <<'GROOVYEOF'
// Job DSL Script - Creates 4 CI/CD Pipeline Jobs

def gitRepo = 'YOUR_GIT_REPO_URL'  // TODO: Replace with actual repo
def gitBranch = '*/main'

// CI Job for Service 1
pipelineJob('CI-Service1') {
    description('CI - Builds and pushes Service 1 Docker image to ECR')
    triggers { scm('H/5 * * * *') }
    definition {
        cpsScm {
            scm {
                git {
                    remote { url(gitRepo) }
                    branches(gitBranch)
                    extensions {
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

// CI Job for Service 2
pipelineJob('CI-Service2') {
    description('CI - Builds and pushes Service 2 Docker image to ECR')
    triggers { scm('H/5 * * * *') }
    definition {
        cpsScm {
            scm {
                git {
                    remote { url(gitRepo) }
                    branches(gitBranch)
                    extensions {
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

// CD Job for Service 1
pipelineJob('CD-Service1') {
    description('CD - Deploys Service 1 to ECS')
    parameters {
        stringParam('IMAGE_VERSION', 'latest', 'Docker image version to deploy')
    }
    definition {
        cpsScm {
            scm {
                git {
                    remote { url(gitRepo) }
                    branches(gitBranch)
                }
            }
            scriptPath('jenkins/pipelines/Jenkinsfile-CD-Service1')
            lightweight(true)
        }
    }
}

// CD Job for Service 2
pipelineJob('CD-Service2') {
    description('CD - Deploys Service 2 to ECS')
    parameters {
        stringParam('IMAGE_VERSION', 'latest', 'Docker image version to deploy')
    }
    definition {
        cpsScm {
            scm {
                git {
                    remote { url(gitRepo) }
                    branches(gitBranch)
                }
            }
            scriptPath('jenkins/pipelines/Jenkinsfile-CD-Service2')
            lightweight(true)
        }
    }
}
GROOVYEOF

# Create seed job XML config
cat > /tmp/seed-job-config.xml <<'XMLEOF'
<?xml version='1.1' encoding='UTF-8'?>
<project>
  <description>Seed job that creates all CI/CD pipeline jobs</description>
  <keepDependencies>false</keepDependencies>
  <properties/>
  <scm class="hudson.scm.NullSCM"/>
  <canRoam>true</canRoam>
  <disabled>false</disabled>
  <blockBuildWhenDownstreamBuilding>false</blockBuildWhenDownstreamBuilding>
  <blockBuildWhenUpstreamBuilding>false</blockBuildWhenUpstreamBuilding>
  <triggers/>
  <concurrentBuild>false</concurrentBuild>
  <builders>
    <javaposse.jobdsl.plugin.ExecuteDslScripts plugin="job-dsl">
      <targets>jobs.groovy</targets>
      <usingScriptText>false</usingScriptText>
      <sandbox>false</sandbox>
      <ignoreExisting>false</ignoreExisting>
      <ignoreMissingFiles>false</ignoreMissingFiles>
      <failOnMissingPlugin>false</failOnMissingPlugin>
      <failOnSeedCollision>false</failOnSeedCollision>
      <unstableOnDeprecation>false</unstableOnDeprecation>
      <removedJobAction>IGNORE</removedJobAction>
      <removedViewAction>IGNORE</removedViewAction>
      <removedConfigFilesAction>IGNORE</removedConfigFilesAction>
      <lookupStrategy>JENKINS_ROOT</lookupStrategy>
    </javaposse.jobdsl.plugin.ExecuteDslScripts>
  </builders>
  <publishers/>
  <buildWrappers/>
</project>
XMLEOF

# Create job directory
mkdir -p /var/lib/jenkins/jobs/seed-job
mkdir -p /var/lib/jenkins/workspace/seed-job

# Copy files
cp /tmp/seed-job-config.xml /var/lib/jenkins/jobs/seed-job/config.xml
cp /tmp/jobs.groovy /var/lib/jenkins/workspace/seed-job/jobs.groovy

# Set ownership
chown -R jenkins:jenkins /var/lib/jenkins/jobs/seed-job
chown -R jenkins:jenkins /var/lib/jenkins/workspace/seed-job

# Reload Jenkins configuration
curl -X POST http://localhost:8080/reload --user admin:$JENKINS_PASSWORD

echo "===================================================================="
echo "Jenkins installation completed!"
echo "===================================================================="
echo "Initial admin password: $JENKINS_PASSWORD"
echo "Password stored in SSM: /jenkins/initial-admin-password"
echo ""
echo "NEXT STEPS:"
echo "1. Access Jenkins UI"
echo "2. Go to seed-job and edit jobs.groovy"
echo "3. Replace YOUR_GIT_REPO_URL with your actual Git repository"
echo "4. Run the seed-job - it will create all 4 CI/CD jobs automatically!"
echo "===================================================================="
