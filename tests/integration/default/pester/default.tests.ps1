describe 'default' {
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
