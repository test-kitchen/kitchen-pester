describe 'default' {
  it 'creates a test file' {
    test-path "$env:Temp\test.txt" | should be $true
  }

  it 'creates a test file with correct content' {
    "$env:Temp\test.txt" | should contain 'testing'
  }  
}