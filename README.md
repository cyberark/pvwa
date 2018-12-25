# pvwa

This Playbook will install the CyberArk PVWA software on a Windows 2016 server / VM / instance

Requirements
------------

- Windows 2016 must be installed on the server
- Administrator credentials (either Local or Domain)
- Network connection to the vault and the repository server (???? The server which holds the packages ????)
- Location of PVWA CD image


## Role Variables

A list of vaiables the playbook is using

**Flow Variables**

| Variable                          | Required     | Default                                                                        | Comments                                 |
|-----------------------------------|--------------|--------------------------------------------------------------------------------|------------------------------------------|
| pvwa_prerequisites                | no           | false                                                                          | Install PVWA pre requisites              |
| pvwa_install                      | no           | false                                                                          | Install PVWA                             |
| pvwa_postinstall                  | no           | false                                                                          | PVWA port install role                   |
| pvwa_hardening                    | no           | false                                                                          | PVWA hardening role                      |
| pvwa_registration                 | no           | false                                                                          | PVWA Register with Vault                 |
| pvwa_upgrade                      | no           | false                                                                          | N/A                                      |
| pvwa_clean                        | no           | false                                                                          | Clean server after deployment            |
| pvwa_uninstall                    | no           | false                                                                          | N/A                                      |

**Deployment Variables**

| Variable                          | Required     | Default                                                                        | Comments                                 |
|-----------------------------------|--------------|--------------------------------------------------------------------------------|------------------------------------------|
| pvwa_base_bin_drive               | no           | "C:"                                                                           | Base path to extract CyberArk packages   |
| pvwa_zip_file_path                | yes          | None                                                                           | Zip File path of CyberArk packages       |
| pvwa_extract_folder               | no           | "{{pvwa_base_bin_drive}}\\Cyberark\\packages"                                  | Path to extract the CyberArk packages    |
| pvwa_artifact_name                | no           | "pvwa.zip"                                                                     | zip file name of pvwa package            |
| pvwa_component_folder             | no           | "Central Policy Manager"                                                       | The name of PVWA unzip folder            |
| pvwa_installation_drive           | no           | "C:"                                                                           | Base drive to install PVWA               |
| vault_ip                          | yes          | None                                                                           | Vault ip to perform registration         |
| dr_vault_ip                       | no           | None                                                                           | vault dr ip to perform registration      |
| vault_port                        | no           | 1858                                                                           | vault port                               |
| vault_username                    | no           | "administrator"                                                                | vault username to perform registration   |
| vault_password                    | yes          | None                                                                           | vault password to perform registration   |
| pvwa_url                          | yes          | None                                                                           | URL of registered PVWA                   |
| pvwa_auth_type                    | yes          | cyberark;ldap                                                                  | Authentication Type                      |
| pvwa_iis_app_folder               | yes          | C:\inetpub\wwwroot\Password\Vault                                              | IIS Application Folder                   |
| pvwa_app_name                     | yes          | PasswordVault                                                                  | Web Application Name                     |
| accept_eula                       | yes          | "No"                                                                           | Accepting EULA condition                 |

## Usage

**pvwa_install**

This task will deploy the PVWA to required folder and validate deployment succeed.

**pvwa_hardening**

This task will run the PVWA hardening process

**pvwa_registration**

This task perform registration with active Vault

**pvwa_validateparameters**

This task validate which PVWA steps already occurred on the server so the other tasks won't run again

**pvwa_clean**

This task will clean inf files from installation, delete pvwa installation logs from Temp folder & Delete cred files


## Example Playbook

Example playbook to show how to call the PVWA main playbook with several parameters:

    ---
    - hosts: localhost
      connection: local
      tasks:
        - include_task:
            name: main
          vars:
            pvwa_install: true
            pvwa_hardening: true
            pvwa_clean: true

## Running the  playbook:

To run the above playbook:

    ansible-playbook -i ../inventory.yml pvwa-orchestrator.yml -e "pvwa_install=true pvwa_installation_drive='D:'"

## License

Apache 2
