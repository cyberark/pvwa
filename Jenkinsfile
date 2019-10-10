pipeline {
  agent {
    node {
      label 'ansible'
    }
  }
  environment {
    AWS_REGION = sh(script: 'curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | python -c "import json,sys;obj=json.load(sys.stdin);print obj[\'region\']"', returnStdout: true).trim()
    shortCommit = sh(script: "git log -n 1 --pretty=format:'%h'", returnStdout: true).trim()
  }
  stages {
    stage('Install virtual environment') {
      steps {
        sh '''
            python -m pip install --user virtualenv
            python -m virtualenv --no-site-packages .testenv
            source .testenv/bin/activate
            pip install -r tests/requirements.txt
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
        sh '''
            source .testenv/bin/activate
            yamllint .
        '''
      }
    }
    stage('replace tags with commit id') {
      steps {
        sh '''
            sed -i -- "s/kitchen-type: pvwa/commit-id: commit-${shortCommit}/g" .kitchen.yml
            sed -i -- "s/\\"tag:kitchen-type\\": pvwa/\\"tag:commit-id\\": commit-${shortCommit}/g" tests/default.yml
            sed -i -- "s/tag_kitchen_type_pvwa/tag_commit_id_commit_${shortCommit}/g" tests/default.yml
            sed -i -- "s/kitchen-type=pvwa/commit-id=commit-${shortCommit}/g" tests/inventory/ec2.ini
            sed -i -- "s/tag_kitchen_type_pvwa/tag_commit_id_commit_${shortCommit}/g" tests/inventory/generate_inventory.sh
            mv tests/group_vars/tag_kitchen_type_pvwa.yml tests/group_vars/tag_commit_id_commit_${shortCommit}.yml
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
    stage('Update hosts file') {
      steps {
        sh '''
            source .testenv/bin/activate
            chmod +x tests/inventory/ec2.py
            ansible-inventory -i tests/inventory/ec2.py --list tag_commit_id_${shortCommit} --export -y > ./tests/inventory/hosts
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
    // stage('Run pester tests') {
    //   steps {
    //     sh '''
    //       export PATH="$HOME/.rbenv/bin:$PATH"
    //       eval "$(rbenv init -)"
    //       rbenv global 2.5.1
    //       kitchen verify
    //     '''
    //   }
    // }
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
