describe "ansible_test_kitchen_windows_role ansible role" {
    Context "pvwa Installation Path" {
        $Path = "C:\Program Files (x86)\Cyberark\pvwa\Recordings"
        it "pvwa Recordings Directory Exists" {
            Test-Path -Path $Path | Should be $true
        }
    }
}