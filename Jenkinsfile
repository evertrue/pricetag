def name = 'registry.evertrue.com/evertrue/pricetag'
def safeBranchName = env.BRANCH_NAME.replaceAll(/\//, "-")

node {
  try {
    stage 'Checkout'
      checkout scm

    withCredentials([[$class: 'StringBinding', credentialsId: 'FURY_AUTH', variable: 'FURY_AUTH']]) {
      stage 'Build Docker image'
        sh "docker build --build-arg BUNDLE_GEM__FURY__IO=${env.FURY_AUTH} -t ${name}:${safeBranchName}-${env.BUILD_ID} ."
    }

    stage 'Push Docker image'
      sh "docker push ${name}:${safeBranchName}-${env.BUILD_ID}"

      if (env.BRANCH_NAME == 'master' ) {
        sh "docker tag ${name}:${safeBranchName}-${env.BUILD_ID} ${name}:latest"
        sh "docker push ${name}:latest"
      }

    slackSend color: 'good', message: "${env.JOB_NAME} - #${env.BUILD_NUMBER} Success (<${env.BUILD_URL}|Open>)"
  } catch (e) {
    currentBuild.result = "FAILED"
    slackSend color: 'bad', message: "${env.JOB_NAME} - #${env.BUILD_NUMBER} Failure (<${env.BUILD_URL}|Open>)"
    throw e
  }

  step([$class: 'GitHubCommitStatusSetter'])
}
