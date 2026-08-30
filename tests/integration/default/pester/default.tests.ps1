describe 'default' {
  context 'Pester version' {
    it 'ran under Pester 5, the version the gallery ships' {
      $pester = Get-Module Pester | Sort-Object Version -Descending | Select-Object -First 1
      $pester.Version.Major | Should -BeGreaterOrEqual 5
    }
  }

  context 'provisioning file' {
    it 'creates a test file' {
      "$env:Temp\test.txt" | should -Exist
    }

    it 'creates a test file with correct content' {
      Get-Content "$env:Temp\test.txt" | should -contain 'testing'
    }
  }

  context 'environment variables' {
    it 'sets environment variables expected' {
      $env:API_KEY | Should -BeExactly 'Some key value'
      $env:PUSH_REPO | Should -BeExactly 'https://push.example.com'
    }
  }
}
