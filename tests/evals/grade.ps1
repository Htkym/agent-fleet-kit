function Get-FleetEvaluationGrade($Baseline, [string]$Fixture, [string[]]$AllowedPaths, [string]$Executable, [string[]]$Arguments) {
    $beforeTest = Get-FleetSnapshot $Fixture -Exclude $Baseline.excluded
    $baseFiles = @{}; foreach ($file in $Baseline.files) { $baseFiles[$file.path] = $file.sha256 }
    $currentFiles = @{}; foreach ($file in $beforeTest.files) { $currentFiles[$file.path] = $file.sha256 }
    $changed = @(@($baseFiles.Keys) + @($currentFiles.Keys) | Sort-Object -Unique | Where-Object { $baseFiles[$_] -cne $currentFiles[$_] })
    $unexpected = @($changed | Where-Object { $_ -notin $AllowedPaths })
    $gitChanged = $Baseline.commit -cne $beforeTest.commit -or $Baseline.branch -cne $beforeTest.branch -or $Baseline.staged_digest -cne $beforeTest.staged_digest
    if ($unexpected.Count -or $gitChanged) {
        return @{status='artifact-failed';changed_paths=$changed;unexpected_paths=$unexpected;git_changed=$gitChanged;test=@{exit_code=$null;timed_out=$false;stdout='';stderr='Verification not run: protected input or Git state changed'};test_ran=$false}
    }
    # Run only the trusted verifier, after its bytes and the write boundary have been checked.
    $test = Invoke-FleetProcess $Executable $Arguments $Fixture
    $afterTest = Get-FleetSnapshot $Fixture -Exclude $Baseline.excluded
    $sourceChanged = $beforeTest.digest -cne $afterTest.digest -or $beforeTest.staged_digest -cne $afterTest.staged_digest -or $beforeTest.commit -cne $afterTest.commit
    @{status=$(if ($test.exit_code -eq 0 -and -not $test.timed_out -and -not $sourceChanged) {'artifact-verified'} else {'artifact-failed'});changed_paths=$changed;unexpected_paths=$unexpected;git_changed=$gitChanged;test=$test;test_ran=$true;verifier_changed_source=$sourceChanged;verified_revision=$beforeTest.digest}
}
