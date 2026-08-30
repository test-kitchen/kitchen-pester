# The same assertions as the default suite, against a Pester pinned to 4.x by
# kitchen.windows.yml. The verifier picks its Invoke-Pester dialect from the
# version it finds on the SUT, so this is the only thing that covers the
# Pester 4 branch end to end.
#
# Written to the subset of the assertion syntax that Pester 4 and 5 share, so
# that a mistake in the pin fails on the version assertion below rather than on
# a parse error.
describe 'pester4' {
  context 'Pester version' {
    it 'ran under Pester 4' {
      $pester = Get-Module Pester | Sort-Object Version -Descending | Select-Object -First 1
      $pester.Version.Major | Should -Be 4
    }
  }

  context 'provisioning file' {
    it 'creates a test file' {
      "$env:Temp\test.txt" | Should -Exist
    }

    it 'creates a test file with correct content' {
      Get-Content "$env:Temp\test.txt" | Should -Contain 'testing'
    }
  }

  context 'environment variables' {
    it 'sets environment variables expected' {
      $env:API_KEY | Should -BeExactly 'Some key value'
      $env:PUSH_REPO | Should -BeExactly 'https://push.example.com'
    }
  }
}
