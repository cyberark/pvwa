# PVWA Ansible Role
This Ansible Role will deploy and install CyberArk Password Vault Web Access including the pre-requisites, application, hardening and connect to an existing Vault environment.

## Requirements
------------
- Windows 2016 installed on the remote host
- WinRM open on port 5986 (**not 5985**) on the remote host
- Pywinrm is installed on the workstation running the playbook
- The workstation running the playbook must have network connectivity to the remote host
- The remote host must have Network connectivity to the CyberArk vault and the repository server
  - 443 port outbound
  - 445 port inbound
  - 1858 port outbound
- Administrator access to the remote host
- PVWA CD image

## Role Variables
These are the variables used in this playbook:

### Flow Variables
Variable                          | Required     | Default                                         | Comments
:----------------------------------|:-------------|:------------------------------------------------|:---------
pvwa_prerequisites                | no           | false                                           | Install PVWA pre-requisites
pvwa_install                      | no           | false                                           | Install PVWA
pvwa_hardening                    | no           | false                                           | Apply PVWA hardening
pvwa_registration                 | no           | false                                           | Connect PVWA to the Vault
pvwa_clean                        | no           | false                                           | N/A

### Deployment Variables
Variable                          | Required     | Default                                         | Comments
:----------------------------------|:-------------|:------------------------------------------------|:---------
vault_ip                          | yes          | None                                            | Vault IP address to perform registration
vault_port                        | no           | **1858**                                        | Vault port
vault_username                    | no           | **administrator**                               | Vault username to perform registration
vault_password                    | yes          | None                                            | Vault password to perform registration
dr_vault_ip                       | no           | None                                            | Vault DR IP address to perform registration
accept_eula                       | yes          | **No**                                          | Accepting EULA condition (Yes/No)
pvwa_url                          | yes          | None                                            | URL of registered PVWA
pvwa_zip_file_path                | yes          | None                                            | CyberArk PVWA installation Zip file package path
pvwa_auth_type                    | yes          | **cyberark;ldap**                               | Authentication Type
pvwa_iis_app_folder               | yes          | **C:\inetpub\wwwroot\PasswordVault**            | IIS Application Folder
pvwa_app_name                     | yes          | **PasswordVault**                               | Web Application Name
pvwa_installation_drive           | no           | **C:**                                          | Destination installation drive

## Dependencies
None

## Usage
The role consists of a number of different tasks which can be enabled or disabled for the particular
run.

`pvwa_install`

This task will deploy the PVWA to required folder and validate successful deployment.

`pvwa_hardening`

This task will run the PVWA hardening process.

`pvwa_registration`

This task perform registration with active Vault.

`pvwa_validateparameters`

This task will validate which PVWA steps have already occurred on the server to prevent repetition.

`pvwa_clean`

This task will clean the configuration (inf) files from the installation, delete the
PVWA installation logs from the Temp folder and delete the cred files.

## Example Playbook
Below is an example of how you can incorporate this role into an Ansible playbook
to call the PVWA role with several parameters:

```
---
- include_role:
    name: pvwa
  vars:
    pvwa_install: true
    pvwa_hardening: true
    pvwa_clean: true
```

## Running the  playbook:
For an example of how to incorporate this role into a complete playbook, please see the
**[pas-orchestrator](https://github.com/cyberark/pas-orchestrator)** example.

## License
Apache License, Version 2.0
