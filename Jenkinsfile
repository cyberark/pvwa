pipeline {
  agent {
    node {
      label 'ansible'
    }
  }
  environment {
    AWS_REGION = sh(script: 'curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | python3 -c "import json,sys;obj=json.load(sys.stdin);print (obj[\'region\'])"', returnStdout: true).trim()
    shortCommit = sh(script: "git log -n 1 --pretty=format:'%h'", returnStdout: true).trim()
  }
  stages {
    stage('Install virtual environment') {
      steps {
        sh '''
            python3 -m pip install --user virtualenv
            python3 -m virtualenv .testenv
            source .testenv/bin/activate
            pip install -r tests/requirements.txt
        '''
      }
    }
    stage('yamllint validation') {
      steps {
        sh '''
          source .testenv/bin/activate
          yamllint .
        '''
      }
    }
    stage('Provision testing environment') {
      steps {
        sh '''
          export PATH="$HOME/.rbenv/bin:$PATH"
          eval "$(rbenv init -)"
          rbenv global 2.5.1
          kitchen create
        '''

      }
    }
    stage('Run playbook on windows machine') {
      steps {
        sh '''
          export PATH="$HOME/.rbenv/bin:$PATH"
          eval "$(rbenv init -)"
          rbenv global 2.5.1
          source .testenv/bin/activate
          kitchen converge
        '''
      }
    }
  }
  post {
    always {
      sh '''
        export PATH="$HOME/.rbenv/bin:$PATH"
        eval "$(rbenv init -)"
        rbenv global 2.5.1
        kitchen destroy
      '''
    }
  }
}
