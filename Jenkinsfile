pipeline {
  agent {
    node {
      label 'ansible'
    }
  }
  environment {
    AWS_REGION = sh(script: 'curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | python -c "import json,sys;obj=json.load(sys.stdin);print obj[\'region\']"', returnStdout: true).trim()
    shortCommit = sh(script: "git log -n 1 --pretty=format:'%h'", returnStdout: true).trim()
    PATH = '$HOME/.rbenv/bin:$PATH'
  }
  stages {
    stage('Install virtual environment') {
      steps {
        sh '''
            python -m pip install --user virtualenv
            python -m virtualenv --no-site-packages .testenv
            . .testenv/bin/activate
            .testenv/bin/pip install -r tests/requirements.txt
        '''
      }
    }
    // stage('ansible-lint validation') {
    //   steps {
    //     sh '.testenv/bin/ansible-lint tasks/* defaults/* meta/*'
    //   }
    // }
    stage('yamllint validation') {
      steps {
        sh '.testenv/bin/yamllint .'
      }
    }
    stage('replace tags with commit id') {
      steps {
        sh '''
            sed -i -- "s/kitchen-type: windows/commit-id: commit-${shortCommit}/g" .kitchen.yml
            sed -i -- "s/\\"tag:kitchen-type\\": windows/\\"tag:commit-id\\": commit-${shortCommit}/g" tests/default.yml
            sed -i -- "s/tag_kitchen_type_windows/tag_commit_id_commit_${shortCommit}/g" tests/default.yml
            sed -i -- "s/kitchen-type=windows/commit-id=commit-${shortCommit}/g" tests/inventory/ec2.ini
            sed -i -- "s/tag_kitchen_type_windows/tag_commit_id_commit_${shortCommit}/g" tests/inventory/generate_inventory.sh
            mv tests/group_vars/tag_kitchen_type_windows.yml tests/group_vars/tag_commit_id_commit_${shortCommit}.yml
        '''
      }
    }
    stage('Provision testing environment') {
      steps {
        sh 'kitchen create'
      }
    }
    stage('Update hosts file') {
      steps {
        sh '''
            chmod +x tests/inventory/ec2.py
            ansible-inventory -i tests/inventory/ec2.py --list tag_commit_id_${shortCommit} --export -y > ./tests/inventory/hosts
        '''
      }
    }
    stage('Run playbook on windows machine') {
      steps {
        sh 'kitchen converge'
      }
    }
    stage('Run pester tests') {
      steps {
        sh 'kitchen verify'
      }
    }
  }
  post {
    always {
      sh 'kitchen destroy'
    }
  }
}
