function ConvertFrom-PesterOutputObject {
  param (
    [parameter(ValueFromPipeline=$true)]
    [object]
    $InputObject
  )
  begin {
    $PesterModule = Import-Module Pester -Passthru
  }
  process {
    $DescribeGroup = $InputObject.testresult | Group-Object Describe
    foreach ($DescribeBlock in $DescribeGroup) {
      $PesterModule.Invoke({Write-Screen $args[0]}, "Describing $($DescribeBlock.Name)")
      $ContextGroup = $DescribeBlock.group | Group-Object Context
      foreach ($ContextBlock in $ContextGroup) {
        $PesterModule.Invoke({Write-Screen $args[0]}, "`tContext $($subheader.name)")
        foreach ($TestResult in $ContextBlock.group) {
          $PesterModule.Invoke({Write-PesterResult $args[0]}, $TestResult)
        }
      }
    }
    $PesterModule.Invoke({Write-PesterReport $args[0]}, $InputObject)
  }
}