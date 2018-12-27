# PVWA Ansible Role

This Playbook will install the [CyberArk PVWA](https://www.cyberark.com/products/privileged-account-security-solution/core-privileged-account-security/) software on a Windows 2016 server / VM / instance.

## Requirements
------------
- The host running the playbook must have network connectivity to the remote hosts in the inventory
- Windows 2016 must be installed on the remote host
- Administrator credentials for access to the remote host (either Local or Domain)
- Network connectivity to the CyberArk vault and the repository server
- CPM package version 10.6 and above, including the location of the CD images

## Role Variables

These are the variables used in this playbook:

### Flow Variables

| Variable                          | Required     | Default                                           | Comments
|:----------------------------------|:-------------|:--------------------------------------------------|:---------
| pvwa_prerequisites                | no           | false                                             | Install PVWA pre-requisites
| pvwa_install                      | no           | false                                             | Install PVWA
| pvwa_postinstall                  | no           | false                                             | PVWA port install role
| pvwa_hardening                    | no           | false                                             | PVWA hardening role
| pvwa_registration                 | no           | false                                             | PVWA Register with Vault
| pvwa_upgrade                      | no           | false                                             | N/A
| pvwa_clean                        | no           | false                                             | Clean server after deployment
| pvwa_uninstall                    | no           | false                                             | N/A

### Deployment Variables

| Variable                          | Required     | Default                                         | Comments
|:----------------------------------|:-------------|:------------------------------------------------|:---------
| vault_ip                          | yes          | None                                            | Vault IP address to perform registration
| vault_password                    | yes          | None                                            | Vault password to perform registration
| accept_eula                       | yes          | **No**                                          | Accepting EULA condition
| pvwa_url                          | yes          | None                                            | URL of registered PVWA
| pvwa_auth_type                    | yes          | **cyberark;ldap**                               | Authentication Type
| pvwa_iis_app_folder               | yes          | **C:\inetpub\wwwroot\Password\Vault**           | IIS Application Folder
| pvwa_app_name                     | yes          | **PasswordVault**                               | Web Application Name
| pvwa_zip_file_path                | yes          | None                                            | Zip File path of CyberArk packages
| pvwa_base_bin_drive               | no           | **C:**                                          | Base path to extract CyberArk packages
| pvwa_extract_folder               | no           | **{{pvwa_base_bin_drive}}\\Cyberark\\packages** | Path to extract the CyberArk packages
| pvwa_artifact_name                | no           | **pvwa.zip**                                    | Zip file name of the PVWA package
| pvwa_component_folder             | no           | **Central Policy Manager**                      | The name of PVWA unzip folder
| pvwa_installation_drive           | no           | **C:**                                          | Base drive to install PVWA
| dr_vault_ip                       | no           | None                                            | Vault DR  IP address to perform registration
| vault_port                        | no           | **1858**                                        | Vault port
| vault_username                    | no           | **administrator**                               | Vault username to perform registration

## Dependencies


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
to call the CPM role with several parameters:

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

[Apache 2](LICENSE)
