describe "ansible_test_kitchen_windows_role ansible role" {
    Context "PVWA Installation Path" {
        $Path = "C:\Cyberark\Password Vault Web Access"
        it "PVWA Directory Exists" {
            Test-Path -Path $Path | Should be $true
        }
    }
}